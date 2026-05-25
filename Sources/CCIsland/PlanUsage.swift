import Foundation
import Security

/// One plan-budget bucket as Anthropic surfaces it via the `/api/oauth/usage`
/// endpoint that backs Claude Code's `/usage` slash command and the
/// claude.ai web UI's "Plan usage" panel.
struct PlanBudget: Equatable {
    /// 0…1 (Anthropic stores it as a fraction). UI shows `utilization * 100`.
    var utilization: Double
    var resetsAt: Date?
}

struct PlanUsage: Equatable {
    var fiveHour: PlanBudget?       // "Current session" — the 5h block
    var sevenDay: PlanBudget?       // "All models" weekly bucket
    var sevenDayOpus: PlanBudget?   // Opus-only weekly (if surfaced)
    var sevenDaySonnet: PlanBudget? // Sonnet-only weekly (if surfaced)
    var fetchedAt: Date
}

/// Reads the OAuth access token stashed by Claude Code's `/login` flow and
/// hits Anthropic's private plan-usage endpoint. The endpoint is what powers
/// Claude Code's `/usage` slash command — same data the web UI shows, so this
/// is the only way to get plan-% that actually agrees with claude.ai.
final class PlanUsageFetcher {
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
    func fetch() async throws -> PlanUsage {
        guard let token = readOAuthToken() else { throw FetchError.noToken }

        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("claude-cli-compatible", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch { throw FetchError.transport(error) }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw FetchError.unauthorized }
        guard (200..<300).contains(status) else { throw FetchError.http(status) }

        // Persist raw payload for diagnostics — until the schema is settled,
        // having the actual server response trumps guessing field names.
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
        if let s = d["resets_at"] as? String { resets = Self.iso.date(from: s) }
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
            .appendingPathComponent("CCIsland", isDirectory: true)
        guard let dir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("last-usage.json"))
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Keychain

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
