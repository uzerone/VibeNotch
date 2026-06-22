import Foundation

/// One plan-budget bucket. For Claude this is how Anthropic surfaces a bucket
/// via the `/api/oauth/usage` endpoint (backing Claude Code's `/usage` slash
/// command and the claude.ai "Plan usage" panel). For Codex the same shape is
/// filled from the `rate_limits` block emitted into the local session logs.
struct PlanBudget: Equatable {
    /// 0…1 (stored as a fraction). UI shows `utilization * 100`.
    var utilization: Double
    var resetsAt: Date?
}

struct PlanUsage: Equatable {
    var fiveHour: PlanBudget?       // "Current session" — the 5h block
    var sevenDay: PlanBudget?       // "All models" weekly bucket
    var sevenDayOpus: PlanBudget?   // Opus-only weekly (Claude only)
    var sevenDaySonnet: PlanBudget? // Sonnet-only weekly (Claude only)
    var fetchedAt: Date

    /// True once the five-hour window's reset time has passed: the reading is
    /// stale and its utilization no longer reflects the live block. Used to
    /// stop republishing a cached plan-% after the window has rolled over.
    /// Buckets without a `resetsAt` (or no five-hour bucket) are never treated
    /// as expired here — there's nothing to time them out against.
    func isExpired(asOf now: Date) -> Bool {
        guard let reset = fiveHour?.resetsAt else { return false }
        return reset <= now
    }
}
