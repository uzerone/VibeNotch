import Foundation

/// Which usage source a snapshot came from. Carried in `ProviderSnapshot`
/// so the UI can tint/label the pill for whichever provider is currently
/// driving the display (the "auto" merge in `UsageMonitor`).
enum Provider: String, Equatable {
    case claude
    case codex
}

/// A per-provider usage engine. Each provider polls its own log directory,
/// owns its own pricing table and plan-% source, and produces a
/// provider-scoped snapshot. The coordinator (`UsageMonitor`) owns one
/// instance per provider and merges their snapshots.
///
/// `computeSnapshot` is the file-derived hot path (cheap on cache hits, runs
/// on a background queue). Claude's slower HTTP plan-% refresh lives outside
/// this protocol — the coordinator drives `ClaudeProvider.fetchPlan()`
/// directly on its own timer because it needs the typed `FetchError`; Codex
/// derives plan-% from local logs inside `computeSnapshot`.
protocol UsageProvider: AnyObject {
    var provider: Provider { get }

    /// Recompute usage from disk for the given `now`. Returns `nil` when the
    /// provider has no data directory at all (e.g. the tool isn't installed).
    func computeSnapshot(now: Date) -> ProviderSnapshot?
}
