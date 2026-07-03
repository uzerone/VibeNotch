import Foundation

enum WorkState: Equatable {
    case idle
    case working
    case awaitingDecision
}

struct ModelTraits: Equatable {
    /// Session capability — the last assistant turn contained a thinking
    /// block. Drives the THINKING chip in the expanded card; that's a
    /// session-level signal, not a moment-by-moment phase indicator
    /// (phases alternate too fast to be useful as a label).
    var thinking: Bool = false
    var oneMillionContext: Bool = false
    var fastMode: Bool = false
    /// Codex reasoning effort (`"low"`/`"medium"`/`"high"`), surfaced as a
    /// chip. Provider-agnostic field — Claude leaves it nil.
    var reasoningEffort: String? = nil
}

/// A usage snapshot scoped to a single provider. The coordinator
/// (`UsageMonitor`) merges per-provider snapshots and publishes the winning
/// one; `provider` records which source it came from so the UI can tint and
/// label the pill accordingly.
///
/// `Equatable` so the coordinator can skip republishing an unchanged snapshot
/// — the 5s poll usually produces an identical value, and dropping the no-op
/// publish saves a full SwiftUI diff of the island every tick.
struct ProviderSnapshot: Equatable {
    var provider: Provider = .claude

    var tokensToday: Int = 0
    var costToday: Double = 0
    var tokensBlock: Int = 0
    var costBlock: Double = 0
    var blockStart: Date?
    /// Number of session files with a billed turn inside the active window —
    /// drives the "×N" badge when more than one session is running at once.
    var activeSessions: Int = 0
    var workState: WorkState = .idle
    var lastActivity: Date?
    var currentModel: String?
    var currentModelTraits: ModelTraits = .init()

    /// Tokens/cost consumed in the *current 5h session block*, broken down by
    /// raw model id — the window that's actively consuming the user's plan
    /// quota. Renders the per-model split bar in the card.
    var tokensByModelBlock: [String: Int] = [:]
    var costByModelBlock: [String: Double] = [:]

    /// Authoritative plan-budget figures. For Claude this comes from
    /// Anthropic's `/api/oauth/usage` endpoint (same data Claude Code's
    /// `/usage` slash command shows); for Codex it's read straight from the
    /// `rate_limits` block in the local session logs. `nil` until the first
    /// fetch/parse completes or when no plan data is available locally.
    var planUsage: PlanUsage?
    /// Human-readable reason the last plan fetch failed, if any (e.g. "token
    /// expired — run claude /login"). Shown under the SESSION block while the
    /// plan gauge is missing. Claude-only; nil for Codex.
    var planUsageHint: String?

    var isWorking: Bool { workState == .working }
    var isAwaitingDecision: Bool { workState == .awaitingDecision }
    var hasActivity: Bool { workState != .idle }
}

/// The UI binds to `monitor.snapshot` of this type. It's the provider-scoped
/// snapshot of whichever provider currently wins the "auto" merge — keeping
/// the alias means every existing `snapshot.X` access stays valid.
typealias UsageSnapshot = ProviderSnapshot
