import Foundation

/// OpenAI Codex CLI usage engine. Reads `rollout-*.jsonl` session files from
/// `~/.codex/sessions` (honoring `CODEX_HOME`), parses `token_count` events for
/// per-turn token deltas + cost, derives the current 5h block and today's
/// totals, and reads the official plan-% straight out of the `rate_limits`
/// block (no network, no keychain). Work state and the current model/effort
/// come from a tail scan of the most-recently-modified session.
final class CodexProvider: UsageProvider {
    let provider: Provider = .codex

    private let sessionsURL: URL
    private var fileCache: [URL: FileCache<CodexEntry>] = [:]
    /// Per-file resolved model, so token_count entries (which don't carry the
    /// model) can be attributed. Model is stable within a session.
    private var fileModel: [URL: String] = [:]
    /// Per-file newest rate-limit windows, persisted across cache hits so a
    /// quiet session still contributes its last-known plan-%. Newest across all
    /// live files wins (see `latestPrimary`/`latestSecondary` below).
    private var filePlan: [URL: (ts: Date, primary: CodexRateWindow?, secondary: CodexRateWindow?)] = [:]
    /// The latest rate-limit windows seen this pass, with the timestamp of the
    /// event they came from — newest wins across all live files.
    private var latestPrimary: (ts: Date, window: CodexRateWindow)?
    private var latestSecondary: (ts: Date, window: CodexRateWindow)?
    private var planFetchedAt: Date?
    /// The file currently being parsed — lets `recordPlanWindow` (called from
    /// the scan closure) attribute windows to the right file.
    private var parsingURL: URL?
    /// Tail-scan cache (current model/effort/work-state) keyed by (size, mtime).
    private var tailCache: [URL: (size: UInt64, mtime: Date, info: CodexTailInfo)] = [:]

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init() {
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let base: URL
        if let env, !env.isEmpty {
            base = URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
        self.sessionsURL = base.appendingPathComponent("sessions", isDirectory: true)
    }

    // MARK: - Snapshot

    func computeSnapshot(now: Date) -> ProviderSnapshot? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsURL.path),
              let enumerator = fm.enumerator(at: sessionsURL,
                                             includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                             options: [.skipsHiddenFiles]) else {
            return nil
        }

        var snap = ProviderSnapshot(provider: .codex)
        let startOfToday = Calendar.current.startOfDay(for: now)
        let activeThreshold: TimeInterval = 30
        let awaitingThreshold: TimeInterval = 300
        let pruneCutoff = min(startOfToday, now.addingTimeInterval(-10 * 3600))

        var sawPaths = Set<URL>()
        var mostRecent: (URL, Date)?
        var allEntries: [CodexEntry] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-") else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = vals?.contentModificationDate ?? .distantPast
            let size = UInt64(vals?.fileSize ?? 0)

            if mtime < pruneCutoff {
                fileCache.removeValue(forKey: url)
                tailCache.removeValue(forKey: url)
                fileModel.removeValue(forKey: url)
                filePlan.removeValue(forKey: url)
                continue
            }
            sawPaths.insert(url)

            if mostRecent == nil || mtime > mostRecent!.1 {
                mostRecent = (url, mtime)
            }
            if now.timeIntervalSince(mtime) < activeThreshold {
                snap.activeSessions += 1
            }

            // Cache hit: file unchanged. Its plan window persists in `filePlan`.
            if let cached = fileCache[url], cached.size == size, cached.mtime == mtime {
                allEntries.append(contentsOf: cached.entries)
                continue
            }

            // Resolve the file's model (stable per session) before parsing
            // token_count entries so each entry can be attributed.
            let model = resolveModel(url: url, size: size, mtime: mtime)

            let prev = fileCache[url]
            let startOffset: Int
            var entry = prev ?? FileCache<CodexEntry>(mtime: mtime, size: size,
                                                     parsedToOffset: 0, entries: [])
            if let prev, size < prev.size {
                startOffset = 0
                entry.entries.removeAll(keepingCapacity: true)
                filePlan.removeValue(forKey: url)  // re-derive from a fresh scan
            } else {
                startOffset = entry.parsedToOffset
            }
            entry.entries.removeAll { $0.ts < pruneCutoff }

            parsingURL = url
            entry.parsedToOffset = parseAppended(url: url, from: startOffset,
                                                 fileSize: size, model: model,
                                                 into: &entry.entries, pruneCutoff: pruneCutoff)
            parsingURL = nil
            entry.mtime = mtime
            entry.size = size
            fileCache[url] = entry

            allEntries.append(contentsOf: entry.entries)
        }

        // Pick the newest rate-limit windows across every live file.
        latestPrimary = nil
        latestSecondary = nil
        for (_, p) in filePlan {
            if let prim = p.primary, latestPrimary == nil || p.ts > latestPrimary!.ts {
                latestPrimary = (p.ts, prim)
                planFetchedAt = p.ts
            }
            if let sec = p.secondary, latestSecondary == nil || p.ts > latestSecondary!.ts {
                latestSecondary = (p.ts, sec)
            }
        }

        // Drop caches for vanished files.
        if fileCache.count != sawPaths.count {
            for key in fileCache.keys where !sawPaths.contains(key) {
                fileCache.removeValue(forKey: key)
                tailCache.removeValue(forKey: key)
                fileModel.removeValue(forKey: key)
                filePlan.removeValue(forKey: key)
            }
        }

        snap.lastActivity = mostRecent?.1

        // Today's totals — deltas are already unique per turn, no dedup needed.
        for e in allEntries where e.ts >= startOfToday {
            snap.tokensToday += e.deltaTokens
            snap.costToday += e.cost
            snap.tokensByModelToday[e.model, default: 0] += e.deltaTokens
        }

        // Current fixed 5h block (token/cost figures; plan-% comes from
        // rate_limits below).
        if let block = currentFixedBlock(entries: allEntries, now: now) {
            snap.blockStart = block.start
            snap.tokensBlock = block.tokens
            snap.costBlock = block.cost
            snap.tokensByModelBlock = block.tokensByModel
            snap.costByModelBlock = block.costByModel
        }

        // Plan-%: authoritative, from the newest rate_limits seen.
        if latestPrimary != nil || latestSecondary != nil {
            snap.planUsage = PlanUsage(
                fiveHour: latestPrimary.map { budget($0.window) },
                sevenDay: latestSecondary.map { budget($0.window) },
                sevenDayOpus: nil,
                sevenDaySonnet: nil,
                fetchedAt: planFetchedAt ?? now
            )
        }

        // Current model + effort + work state from the most-recent file's tail.
        if let (url, mtime) = mostRecent {
            let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let tail = tailInfo(at: url, size: size, mtime: mtime)
            snap.currentModel = tail?.model ?? fileModel[url] ?? CodexParsing.defaultModel
            var traits = ModelTraits()
            traits.reasoningEffort = tail?.effort
            snap.currentModelTraits = traits

            let sinceMod = now.timeIntervalSince(mtime)
            if sinceMod < 3 || tail?.lastEvent == "task_started" {
                snap.workState = .working
            } else if sinceMod < awaitingThreshold, tail?.lastEvent == "task_complete" {
                snap.workState = .awaitingDecision
            } else {
                snap.workState = .idle
            }
        }

        return snap
    }

    // MARK: - Plan windows

    /// Records the rate-limit windows from a token_count event into the file's
    /// persisted plan slot (newest event per file wins). Called from the scan
    /// closure during `parseAppended`, keyed on `parsingURL`.
    private func recordPlanWindow(ts: Date, primary: CodexRateWindow?, secondary: CodexRateWindow?) {
        guard let url = parsingURL, primary != nil || secondary != nil else { return }
        if let existing = filePlan[url], existing.ts >= ts { return }
        // Carry forward whichever window the newest event omitted.
        let prev = filePlan[url]
        filePlan[url] = (ts, primary ?? prev?.primary, secondary ?? prev?.secondary)
    }

    private func budget(_ w: CodexRateWindow) -> PlanBudget {
        PlanBudget(utilization: w.usedPercent / 100, resetsAt: w.resetsAt)
    }

    // MARK: - Block

    private func currentFixedBlock(entries: [CodexEntry], now: Date)
        -> (start: Date, tokens: Int, cost: Double,
            tokensByModel: [String: Int], costByModel: [String: Double])? {
        guard !entries.isEmpty else { return nil }
        let sorted = entries.sorted { $0.ts < $1.ts }
        let windowLen: TimeInterval = 5 * 3600

        var windowStart = sorted[0].ts
        var tokens = 0
        var cost: Double = 0
        var tokensByModel: [String: Int] = [:]
        var costByModel: [String: Double] = [:]

        for e in sorted {
            if e.ts >= windowStart.addingTimeInterval(windowLen) {
                windowStart = e.ts
                tokens = 0
                cost = 0
                tokensByModel.removeAll(keepingCapacity: true)
                costByModel.removeAll(keepingCapacity: true)
            }
            tokens += e.deltaTokens
            cost += e.cost
            tokensByModel[e.model, default: 0] += e.deltaTokens
            costByModel[e.model, default: 0] += e.cost
        }

        if now >= windowStart.addingTimeInterval(windowLen) { return nil }
        return (windowStart, tokens, cost, tokensByModel, costByModel)
    }

    // MARK: - Parsing

    /// Resolves a session's model (stable per file) by scanning its tail for the
    /// latest `turn_context.model`, falling back to a cached value or the
    /// default. Cheap; the tail read is reused by `tailInfo`.
    private func resolveModel(url: URL, size: UInt64, mtime: Date) -> String {
        if let m = tailInfo(at: url, size: size, mtime: mtime)?.model { fileModel[url] = m; return m }
        if let cached = fileModel[url] { return cached }
        return CodexParsing.defaultModel
    }

    private func parseAppended(url: URL,
                               from offset: Int,
                               fileSize: UInt64,
                               model: String,
                               into entries: inout [CodexEntry],
                               pruneCutoff: Date) -> Int {
        let marker: [UInt8] = Array("token_count".utf8)
        var collected: [CodexEntry] = []
        let newOffset = JSONLScanner.scanAppended(url: url, from: offset,
                                                  fileSize: fileSize, marker: marker) { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let tsStr = obj["timestamp"] as? String,
                  let parsed = CodexParsing.tokenCount(obj, model: model) else { return }
            let ts = self.iso.date(from: tsStr) ?? self.isoFallback.date(from: tsStr) ?? .distantPast
            self.recordPlanWindow(ts: ts, primary: parsed.primary, secondary: parsed.secondary)
            guard ts >= pruneCutoff else { return }
            collected.append(CodexEntry(ts: ts, deltaTokens: parsed.delta,
                                        cost: parsed.cost, model: model))
        }
        entries.append(contentsOf: collected)
        return newOffset
    }

    // MARK: - Tail scan (model / effort / work state)

    private struct CodexTailInfo {
        var model: String?
        var effort: String?
        var lastEvent: String?   // last event_msg payload.type (task_started/complete/...)
    }

    private func tailInfo(at url: URL, size: UInt64, mtime: Date) -> CodexTailInfo? {
        if let c = tailCache[url], c.size == size, c.mtime == mtime { return c.info }
        guard let lines = JSONLScanner.tailLines(url: url) else { return nil }

        var info = CodexTailInfo()
        // `lines` is most-recent-first. Take the first of each we find.
        for line in lines {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if info.lastEvent == nil, let ev = CodexParsing.eventType(obj) {
                info.lastEvent = ev
            }
            if info.model == nil, let m = CodexParsing.model(fromTurnContext: obj) {
                info.model = m
            }
            if info.effort == nil, let e = CodexParsing.effort(fromTurnContext: obj) {
                info.effort = e
            }
            if info.model != nil && info.effort != nil && info.lastEvent != nil { break }
        }
        tailCache[url] = (size, mtime, info)
        return info
    }
}
