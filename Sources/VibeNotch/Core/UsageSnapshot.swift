import Foundation

enum WorkState {
    case idle
    case working
    case awaitingDecision
}

struct ModelTraits {
    /// Session capability — the last assistant turn contained a thinking
    /// block. Drives the THINKING chip in the expanded card; that's a
    /// session-level signal, not a moment-by-moment phase indicator
    /// (phases alternate too fast to be useful as a label).
    var thinking: Bool = false
    var oneMillionContext: Bool = false
    var fastMode: Bool = false
    var oneHourCache: Bool = false
    /// Codex reasoning effort (`"low"`/`"medium"`/`"high"`), surfaced as a
    /// chip. Provider-agnostic field — Claude leaves it nil.
    var reasoningEffort: String? = nil
}

/// A usage snapshot scoped to a single provider. The coordinator
/// (`UsageMonitor`) merges per-provider snapshots and publishes the winning
/// one; `provider` records which source it came from so the UI can tint and
/// label the pill accordingly.
struct ProviderSnapshot {
    var provider: Provider = .claude

    var tokensToday: Int = 0
    var costToday: Double = 0
    var tokensBlock: Int = 0
    var costBlock: Double = 0
    var blockStart: Date?
    var activeSessions: Int = 0
    var workState: WorkState = .idle
    var lastActivity: Date?
    var currentModel: String?
    var currentModelTraits: ModelTraits = .init()

    /// Tokens consumed today, broken down by raw model id. Used to render
    /// the per-model split (Opus / Sonnet / Haiku share) in the card.
    var tokensByModelToday: [String: Int] = [:]
    /// Same split but scoped to the *current 5h session block* — the
    /// window that's actively consuming the user's plan quota. More
    /// actionable than today's totals for a per-session percentage.
    var tokensByModelBlock: [String: Int] = [:]
    var costByModelBlock: [String: Double] = [:]

    /// Authoritative plan-budget figures. For Claude this comes from
    /// Anthropic's `/api/oauth/usage` endpoint (same data Claude Code's
    /// `/usage` slash command shows); for Codex it's read straight from the
    /// `rate_limits` block in the local session logs. `nil` until the first
    /// fetch/parse completes or when no plan data is available locally.
    var planUsage: PlanUsage?
    /// Reason the last plan fetch failed, if any — used to surface
    /// "log in with `/login`" hints in the UI. Claude-only; nil for Codex.
    var planUsageError: ClaudePlanFetcher.FetchError?

    var isWorking: Bool { workState == .working }
    var isAwaitingDecision: Bool { workState == .awaitingDecision }
    var hasActivity: Bool { workState != .idle }
}

/// The UI binds to `monitor.snapshot` of this type. It's the provider-scoped
/// snapshot of whichever provider currently wins the "auto" merge — keeping
/// the alias means every existing `snapshot.X` access stays valid.
typealias UsageSnapshot = ProviderSnapshot
