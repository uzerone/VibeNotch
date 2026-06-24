import Foundation
import Security

/// Reads the OAuth access token stashed by Claude Code's `/login` flow and
/// hits Anthropic's private plan-usage endpoint. The endpoint is what powers
/// Claude Code's `/usage` slash command — same data the web UI shows, so this
/// is the only way to get plan-% that actually agrees with claude.ai.
///
/// Claude-specific: Codex needs none of this — its plan-% is read straight from
/// the local session logs (see `CodexProvider`).
final class ClaudePlanFetcher {
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 15
        return URLSession(configuration: c)
    }()

    enum FetchError: Error {
        case noToken
        case unauthorized   // 401 — token expired, user needs `claude /login`
        case http(Int)
        case decode
        case transport(Error)
    }

    /// Human-readable hint shown in the UI when the fetch fails.
    static func hint(for err: FetchError) -> String {
        switch err {
        case .noToken: return "no claude /login token in keychain"
        case .unauthorized: return "token expired — run claude /login"
        case .http(let s): return "usage endpoint \(s)"
        case .decode: return "usage payload changed"
        case .transport: return "network error"
        }
    }

    /// One-shot fetch. Returns the parsed budgets or throws.
    ///
    /// Token acquisition is two-tier:
    ///   1. Try our own keychain cache (created and owned by VibeNotch — no
    ///      ACL prompt because we made it).
    ///   2. Miss / expired → read Claude Code's keychain item once, then
    ///      mirror it into the cache so step 1 services every subsequent
    ///      poll. This collapses the steady-state from one Claude Code-
    ///      credentials read every 60s to one read at first launch and after
    ///      `claude /login` refreshes the token.
    func fetch() async throws -> PlanUsage {
        let fromCache: Bool
        var token: String
        if let cached = cachedToken() {
            fromCache = true
            token = cached
        } else {
            fromCache = false
            guard let fresh = readOAuthToken() else { throw FetchError.noToken }
            token = fresh
            storeCachedToken(fresh)
        }

        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("claude-cli-compatible", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch { throw FetchError.transport(error) }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            // Cache may be stale (token rotated by `claude /login`). Drop it
            // and retry exactly once with a fresh read from Claude Code.
            clearCachedToken()
            if fromCache, let fresh = readOAuthToken(), fresh != token {
                storeCachedToken(fresh)
                token = fresh
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (d2, r2) = try await session.data(for: req)
                let s2 = (r2 as? HTTPURLResponse)?.statusCode ?? 0
                if s2 == 401 { throw FetchError.unauthorized }
                guard (200..<300).contains(s2) else { throw FetchError.http(s2) }
                return try parseResponse(d2)
            }
            throw FetchError.unauthorized
        }
        guard (200..<300).contains(status) else { throw FetchError.http(status) }
        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> PlanUsage {
        writeDiagnostic(data)

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.decode
        }

        // The response has been observed in two shapes; pick the right one.
        //   Shape A: { five_hour: {utilization, resets_at}, ... }
        //   Shape B: { rate_limits: { five_hour: {used_percentage, resets_at:<epoch>}, ... } }
        let buckets: [String: Any]
        if let rl = obj["rate_limits"] as? [String: Any] { buckets = rl }
        else { buckets = obj }

        return PlanUsage(
            fiveHour: parseBucket(buckets["five_hour"]),
            sevenDay: parseBucket(buckets["seven_day"]),
            sevenDayOpus: parseBucket(buckets["seven_day_opus"]),
            sevenDaySonnet: parseBucket(buckets["seven_day_sonnet"]),
            fetchedAt: Date()
        )
    }

    private func parseBucket(_ raw: Any?) -> PlanBudget? {
        guard let d = raw as? [String: Any] else { return nil }
        // Both `utilization` and `used_percentage` are 0-100 (verified
        // against the real `/api/oauth/usage` response). The repo's
        // `PlanBudget.utilization` is normalized to 0-1 for the UI's
        // ProgressTrack to consume directly.
        let pct: Double?
        if let v = d["utilization"] as? Double { pct = v }
        else if let v = d["utilization"] as? Int { pct = Double(v) }
        else if let v = d["used_percentage"] as? Double { pct = v }
        else if let v = d["used_percentage"] as? Int { pct = Double(v) }
        else { pct = nil }
        guard let p = pct else { return nil }
        let u = p / 100

        // `resets_at` can be an ISO string or a Unix epoch (sometimes seconds,
        // sometimes milliseconds).
        let resets: Date?
        if let s = d["resets_at"] as? String {
            // `iso` requires fractional seconds; fall back to whole-second ISO
            // so a reset on an exact second doesn't drop the countdown.
            resets = Self.iso.date(from: s) ?? Self.isoWhole.date(from: s)
        }
        else if let n = d["resets_at"] as? Double {
            resets = Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)
        } else if let n = d["resets_at"] as? Int {
            let v = Double(n)
            resets = Date(timeIntervalSince1970: v > 1e11 ? v / 1000 : v)
        } else { resets = nil }

        return PlanBudget(utilization: u, resetsAt: resets)
    }

    private func writeDiagnostic(_ data: Data) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first?
            .appendingPathComponent("VibeNotch", isDirectory: true)
        guard let dir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("last-usage.json"))
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback for `resets_at` values that land on a whole second (no `.NNN`),
    /// which the fractional-seconds formatter above rejects.
    private static let isoWhole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Keychain

    /// Whether the Claude Code OAuth token is currently readable from the
    /// Keychain. Used by the Settings panel to surface whether the user
    /// granted Keychain access (or hasn't run `claude /login` yet).
    ///
    /// Prefer the VibeNotch-owned cache: once it holds a token we *had* access
    /// and reading our own item never prompts. We only fall back to reading
    /// Claude Code's entry when the cache is genuinely empty (first launch,
    /// pre-`claude /login`) — and even then we mirror the result into the
    /// cache so this question never reaches Claude Code's keychain again. That
    /// keeps the Settings panel from re-triggering the ACL prompt on every
    /// open, and after a reboot the cache answers immediately.
    static var hasOAuthToken: Bool {
        let f = ClaudePlanFetcher()
        if f.cachedToken() != nil { return true }
        if let fresh = f.readOAuthToken() {
            f.storeCachedToken(fresh)
            return true
        }
        return false
    }

    /// Keychain item VibeNotch creates and owns. Reading this entry never
    /// triggers an ACL prompt because the app that created the item is
    /// automatically in the trusted-apps list — that's how macOS makes
    /// per-app keychain items work without user interaction.
    private static let cachedTokenService = "VibeNotch.cached.claude-token"
    private var cachedTokenAccount: String { NSUserName() }

    private func cachedToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.cachedTokenService,
            kSecAttrAccount as String: cachedTokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        return token
    }

    private func storeCachedToken(_ token: String) {
        let data = Data(token.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.cachedTokenService,
            kSecAttrAccount as String: cachedTokenAccount,
        ]
        // Upsert: try update first, fall back to add. Both paths pin
        // `kSecAttrAccessibleAfterFirstUnlock` so the cache survives a reboot
        // and is readable on every launch after the first post-boot unlock —
        // without it, an item could land in a state that's unreadable early
        // in the session, forcing a fall-back read of Claude Code's own
        // keychain entry (which is what re-triggers the ACL prompt).
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(base as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = base
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func clearCachedToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.cachedTokenService,
            kSecAttrAccount as String: cachedTokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Pulls the bearer token out of the keychain entry Claude Code creates
    /// on `/login`. The value is a JSON blob; we unwrap `claudeAiOauth.accessToken`.
    private func readOAuthToken() -> String? {
        // Claude Code has used a few different keychain service labels across
        // versions / install methods; try the known ones.
        let services = [
            "Claude Code-credentials",
            "claude-code-credentials",
            "Claude Code",
            "claude-code",
        ]
        for service in services {
            if let token = readToken(service: service) { return token }
        }
        return nil
    }

    private func readToken(service: String) -> String? {
        // First try with the POSIX username as account (the most common
        // layout), then fall back to service-only so installs that use the
        // email address or some other label still match.
        let accounts: [String?] = [NSUserName(), nil]
        for account in accounts {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if let a = account { query[kSecAttrAccount as String] = a }
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess, let data = item as? Data else { continue }
            if let token = extractToken(from: data) { return token }
        }
        return nil
    }

    private func extractToken(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let oauth = obj["claudeAiOauth"] as? [String: Any],
               let token = oauth["accessToken"] as? String { return token }
            if let token = obj["accessToken"] as? String { return token }
            if let token = obj["access_token"] as? String { return token }
        }
        // Some older installs stored just the raw token string.
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = raw, r.hasPrefix("sk-ant-") || r.hasPrefix("eyJ") { return r }
        return nil
    }
}
