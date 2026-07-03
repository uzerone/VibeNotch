import Foundation

/// Per-message usage entry kept in memory so we can re-window the 5h block
/// and dedupe retries without re-reading the file.
///
/// Claude Code re-emits the same assistant message on session
/// resume/edit/branch — empirically up to ~17x for a single (message.id,
/// requestId) pair. Aggregating raw entries inflates tokens and cost ~2x,
/// so every consumer must dedupe by `dedupKey`.
private struct ClaudeEntry {
    let ts: Date
    let totalTokens: Int
    let cost: Double
    /// `"\(message.id)|\(requestId)"`, or nil when either is missing.
    let dedupKey: String?
    /// Raw model id (`claude-opus-4-7`, `claude-sonnet-4-6`, …). Kept so the
    /// expanded card can show today's per-model split without re-parsing.
    let model: String?
}

/// Claude Code usage engine. Reads JSONL files from `~/.claude/projects`,
/// parses `"type":"assistant"` lines, computes today's totals, the current
/// fixed 5-hour billing block, per-model splits, work state, and the current
/// model + traits. Plan-% comes from `ClaudePlanFetcher` (HTTP).
final class ClaudeProvider: UsageProvider {
    let provider: Provider = .claude

    private let projectsURL: URL
    private let planFetcher = ClaudePlanFetcher()
    private var fileCache: [URL: FileCache<ClaudeEntry>] = [:]
    /// Cached result of `lastAssistantInfo` per file. Keyed on (size, mtime)
    /// so we re-scan the 64KB tail only when the file actually grew.
    private var tailCache: [URL: (size: UInt64, mtime: Date, info: LastAssistantInfo)] = [:]

    // Pre-allocated parsers — creating these per-line is expensive.
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.projectsURL = home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    // MARK: - Plan %

    /// Direct accessor for the coordinator's out-of-band plan timer, so it can
    /// handle `FetchError` cases (unauthorized vs transient) explicitly.
    func fetchPlan() async throws -> PlanUsage {
        try await planFetcher.fetch()
    }

    // MARK: - Snapshot

    func computeSnapshot(now: Date) -> ProviderSnapshot? {
        var snap = ProviderSnapshot(provider: .claude)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: projectsURL,
                                             includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                             options: [.skipsHiddenFiles]) else {
            return nil
        }

        let startOfToday = Calendar.current.startOfDay(for: now)
        let activeThreshold: TimeInterval = 30
        let awaitingThreshold: TimeInterval = 300
        // Keep entries from the earlier of (start of today, 10h ago) so a
        // 5h block that opened up to 5h ago is still fully accounted for and
        // today's totals always cover the full calendar day.
        let pruneCutoff = min(startOfToday, now.addingTimeInterval(-10 * 3600))

        var sawPaths = Set<URL>()
        var mostRecent: (URL, Date)?
        var allEntries: [ClaudeEntry] = []
        var activeSessionFiles = 0

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = vals?.contentModificationDate ?? .distantPast
            let size = UInt64(vals?.fileSize ?? 0)

            // Files whose latest write is older than our retention window
            // can't contribute to today or the active block — drop them.
            if mtime < pruneCutoff {
                fileCache.removeValue(forKey: url)
                tailCache.removeValue(forKey: url)
                continue
            }
            sawPaths.insert(url)

            if mostRecent == nil || mtime > mostRecent!.1 {
                mostRecent = (url, mtime)
            }

            // Cache hit: file unchanged since last poll. Still re-apply the
            // prune — `pruneCutoff` advances with wall-clock (and across
            // midnight), so an unchanged-but-recent file can hold entries that
            // have since aged out. Drop them from the cache so the in-memory
            // window stays consistent with the parse path.
            if var cached = fileCache[url],
               cached.size == size,
               cached.mtime == mtime {
                cached.entries.removeAll { $0.ts < pruneCutoff }
                fileCache[url] = cached
                if let ts = cached.entries.last?.ts,
                   now.timeIntervalSince(ts) < activeThreshold {
                    activeSessionFiles += 1
                }
                allEntries.append(contentsOf: cached.entries)
                continue
            }

            // Parse — incrementally if the file just grew, fully if it
            // shrank/rotated.
            let prev = fileCache[url]
            let startOffset: Int
            var entry = prev ?? FileCache<ClaudeEntry>(mtime: mtime, size: size,
                                                       parsedToOffset: 0, entries: [])
            if let prev, size < prev.size {
                // File rotated/truncated — re-parse from scratch.
                startOffset = 0
                entry.entries.removeAll(keepingCapacity: true)
            } else {
                startOffset = entry.parsedToOffset
            }

            // Drop entries that have aged out of the retention window.
            entry.entries.removeAll { $0.ts < pruneCutoff }

            entry.parsedToOffset = parseAppended(url: url, from: startOffset,
                                                 fileSize: size, into: &entry.entries,
                                                 pruneCutoff: pruneCutoff)
            entry.mtime = mtime
            entry.size = size
            fileCache[url] = entry

            if let ts = entry.entries.last?.ts,
               now.timeIntervalSince(ts) < activeThreshold {
                activeSessionFiles += 1
            }
            allEntries.append(contentsOf: entry.entries)
        }

        // Drop cache entries for files no longer present.
        if fileCache.count != sawPaths.count {
            for key in fileCache.keys where !sawPaths.contains(key) {
                fileCache.removeValue(forKey: key)
                tailCache.removeValue(forKey: key)
            }
        }

        // Drive the "auto" provider switch off the newest *billed entry*, not
        // the file mtime: an mtime bumps on any write (user line, summary,
        // non-assistant event), which would let a provider win the merge and
        // claim activity "now" with zero new cost. `lastActivity` is the latest
        // parsed assistant turn; `activeSessions` counts session files with a
        // turn inside the active window (drives the "×N" badge). `mostRecent`
        // (mtime) is still used to pick which file's tail to read for the
        // current model/work state.
        snap.lastActivity = allEntries.map(\.ts).max()
        snap.activeSessions = activeSessionFiles

        // Aggregate today's totals with global dedup. Same (msg.id, requestId)
        // can appear up to ~17x across files (session resume/edit/branch);
        // without dedup, totals and cost roughly double.
        var seenToday = Set<String>()
        for e in allEntries where e.ts >= startOfToday {
            if let k = e.dedupKey {
                if !seenToday.insert(k).inserted { continue }
            }
            snap.tokensToday += e.totalTokens
            snap.costToday += e.cost
        }

        // Determine the *current* fixed 5-hour window — matching Claude
        // Code's billing: the window starts at the first message after the
        // previous window expired, then runs for exactly 5 hours. Deduped.
        if let block = currentFixedBlock(entries: allEntries, now: now) {
            snap.blockStart = block.start
            snap.tokensBlock = block.tokens
            snap.costBlock = block.cost
            snap.tokensByModelBlock = block.tokensByModel
            snap.costByModelBlock = block.costByModel
        }

        // State + current model from the most-recently-modified file's tail.
        if let (mostRecentURL, mostRecentMtime) = mostRecent {
            let sinceMod = now.timeIntervalSince(mostRecentMtime)
            let lastInfo = lastAssistantInfo(at: mostRecentURL, mtime: mostRecentMtime,
                                             size: UInt64((try? mostRecentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
            snap.currentModel = lastInfo?.model
            snap.currentModelTraits = lastInfo?.traits ?? ModelTraits()
            if sinceMod < 3 {
                snap.workState = .working
            } else if sinceMod < awaitingThreshold, let stop = lastInfo?.stopReason,
                      stop == "end_turn" {
                // Turn genuinely finished — waiting on the user.
                snap.workState = .awaitingDecision
            } else if sinceMod < awaitingThreshold, lastInfo?.stopReason == "tool_use" {
                // Ambiguous: a trailing `tool_use` with no tool result yet is
                // either a tool still executing (working) or a permission
                // prompt (awaiting) — the JSONL can't distinguish them. Most
                // tool runs finish well within ~30s, while a permission
                // prompt sits quiet indefinitely, so quiet-under-30s reads as
                // working and longer quiet flips to awaiting. A long build
                // still mislabels after 30s, but no longer flashes FINISH the
                // moment a 3s-quiet tool call starts.
                snap.workState = sinceMod < 30 ? .working : .awaitingDecision
            } else {
                snap.workState = .idle
            }
        }

        return snap
    }

    /// Computes the current fixed 5-hour window from sorted entries:
    /// the window starts at the first entry after the previous window
    /// expired; we walk forward, opening a fresh window whenever an entry
    /// falls past `start + 5h`. Returns `nil` if the latest window has
    /// already elapsed (no active window — next message starts a new one).
    private func currentFixedBlock(entries: [ClaudeEntry], now: Date)
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
        var seen = Set<String>()

        for e in sorted {
            if e.ts >= windowStart.addingTimeInterval(windowLen) {
                // Previous window closed — start a fresh one anchored here.
                windowStart = e.ts
                tokens = 0
                cost = 0
                tokensByModel.removeAll(keepingCapacity: true)
                costByModel.removeAll(keepingCapacity: true)
                seen.removeAll(keepingCapacity: true)
            }
            if let k = e.dedupKey {
                if !seen.insert(k).inserted { continue }
            }
            tokens += e.totalTokens
            cost += e.cost
            if let m = e.model {
                tokensByModel[m, default: 0] += e.totalTokens
                costByModel[m, default: 0] += e.cost
            }
        }

        // If `now` is already past the current window, treat it as elapsed.
        if now >= windowStart.addingTimeInterval(windowLen) { return nil }
        return (windowStart, tokens, cost, tokensByModel, costByModel)
    }

    // MARK: - Parsing

    /// Parses the file from `offset` to EOF via the shared scanner, appending
    /// `ClaudeEntry` values. Only lines containing `"type":"assistant"` are
    /// JSON-decoded. Returns the new parsed offset.
    private func parseAppended(url: URL,
                               from offset: Int,
                               fileSize: UInt64,
                               into entries: inout [ClaudeEntry],
                               pruneCutoff: Date) -> Int {
        let marker: [UInt8] = Array("\"type\":\"assistant\"".utf8)
        var collected: [ClaudeEntry] = []
        let newOffset = JSONLScanner.scanAppended(url: url, from: offset,
                                                  fileSize: fileSize, marker: marker) { line in
            if let e = self.ingest(line: line, pruneCutoff: pruneCutoff) {
                collected.append(e)
            }
        }
        entries.append(contentsOf: collected)
        return newOffset
    }

    private func ingest(line: Data, pruneCutoff: Date) -> ClaudeEntry? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let tsStr = obj["timestamp"] as? String else { return nil }
        let ts = iso.date(from: tsStr) ?? isoFallback.date(from: tsStr) ?? .distantPast
        guard ts >= pruneCutoff else { return nil }

        let model = (message["model"] as? String) ?? "sonnet"
        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
        // Split the cache-create bucket into 5m vs 1h — they're billed at
        // 1.25x vs 2x base input rate. Falls back to all-5m when the
        // breakdown is missing.
        var cw1h = 0, cw5m = 0
        if let cc = usage["cache_creation"] as? [String: Any] {
            cw1h = (cc["ephemeral_1h_input_tokens"] as? Int) ?? 0
            cw5m = (cc["ephemeral_5m_input_tokens"] as? Int) ?? 0
        }
        if cw1h + cw5m == 0 { cw5m = cacheCreate }

        let pricing = ModelPricing.forModel(model)
        let total = input + output + cacheCreate + cacheRead
        let cost = Double(input) / 1_000_000 * pricing.input
                 + Double(output) / 1_000_000 * pricing.output
                 + Double(cw5m) / 1_000_000 * pricing.cacheWrite5m
                 + Double(cw1h) / 1_000_000 * pricing.cacheWrite1h
                 + Double(cacheRead) / 1_000_000 * pricing.cacheRead

        // (message.id, requestId) uniquely identifies a billed assistant
        // turn. The same turn shows up in the JSONL multiple times after
        // resume/edit/branch; we count it once.
        let mid = message["id"] as? String
        let rid = obj["requestId"] as? String
        let key: String? = (mid != nil && rid != nil) ? "\(mid!)|\(rid!)" : nil

        return ClaudeEntry(ts: ts, totalTokens: total, cost: cost, dedupKey: key, model: model)
    }

    typealias LastAssistantInfo = (stopReason: String?, model: String?, traits: ModelTraits)

    /// Reads the last ~64KB of `url` for state/model detection. Cached by
    /// (size, mtime) — re-scanned only when the file actually changed.
    private func lastAssistantInfo(at url: URL, mtime: Date, size: UInt64) -> LastAssistantInfo? {
        if let c = tailCache[url], c.size == size, c.mtime == mtime {
            return c.info
        }
        guard let lines = JSONLScanner.tailLines(url: url) else { return nil }

        var userCameLast = false
        for line in lines {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            if type == "user" {
                userCameLast = true
                continue
            }
            if type == "assistant",
               let message = obj["message"] as? [String: Any] {
                let model = message["model"] as? String
                let stop = userCameLast ? nil : message["stop_reason"] as? String

                var traits = ModelTraits()
                if let content = message["content"] as? [[String: Any]] {
                    traits.thinking = content.contains { ($0["type"] as? String) == "thinking" }
                }
                if let usage = message["usage"] as? [String: Any] {
                    let input = (usage["input_tokens"] as? Int) ?? 0
                    let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
                    let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                    traits.oneMillionContext = (input + cacheRead + cacheCreate) > 200_000
                    // Claude Code's `/fast` toggle surfaces in the usage
                    // payload as `speed: "fast"` (default is `"standard"`).
                    traits.fastMode = (usage["speed"] as? String) == "fast"
                }
                let info: LastAssistantInfo = (stop, model, traits)
                tailCache[url] = (size, mtime, info)
                return info
            }
        }
        return nil
    }
}
