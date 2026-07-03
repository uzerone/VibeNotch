import Foundation
import Combine

/// Coordinates the per-provider usage engines and publishes a single snapshot
/// for the UI to bind to. In "auto" mode it polls every provider and surfaces
/// whichever one has the most recent activity, so the pill follows whatever
/// the user is actively running (Claude *or* Codex).
final class UsageMonitor: ObservableObject {
    @Published var snapshot = UsageSnapshot()

    private let claude = ClaudeProvider()
    private let codex = CodexProvider()
    private var providers: [UsageProvider] { [claude, codex] }

    private var timer: Timer?
    private var planTimer: Timer?
    private var planTask: Task<Void, Never>?
    /// Async plan-% for Claude is refreshed on a slower timer than the 5s file
    /// poll; cache it here so the file poll doesn't stomp it back to nil.
    private var lastClaudePlan: PlanUsage?
    private var lastClaudePlanHint: String?
    /// Exponential backoff after the usage endpoint rate-limits us (HTTP 429):
    /// polls are skipped until this instant. Doubling 2 → 4 → 8 → 16 min (the
    /// cap), reset by the next successful fetch. Other errors don't back off —
    /// a transport blip is usually local and the next 60s poll is fine.
    private var planBackoffUntil: Date?
    private var planBackoffLevel = 0

    /// Serial queue prevents two refreshes from racing on provider caches.
    private let refreshQueue = DispatchQueue(label: "VibeNotch.refresh", qos: .utility)

    func start() {
        refresh()
        // 5s is a good cadence for the lights; provider caches make most ticks
        // near-free, so we don't gain much by going slower. Timers go into
        // `.common` mode so polling doesn't stall while the user drags the
        // free-move window (event-tracking pauses `.default`-mode timers);
        // the tolerance lets the system coalesce wakeups and save power.
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Plan-% rarely moves fast and the endpoint is rate-sensitive — 60s
        // is plenty and matches what the web UI seems to poll at.
        refreshPlanUsage()
        let pt = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshPlanUsage()
        }
        pt.tolerance = 5
        RunLoop.main.add(pt, forMode: .common)
        planTimer = pt
    }

    func stop() {
        timer?.invalidate(); timer = nil
        planTimer?.invalidate(); planTimer = nil
        planTask?.cancel(); planTask = nil
    }

    // MARK: - Plan % (Claude / HTTP)

    private func refreshPlanUsage() {
        // Still inside a 429 backoff window — stay off the endpoint.
        if let until = planBackoffUntil, Date() < until { return }
        planTask?.cancel()
        planTask = Task { [weak self] in
            guard let self else { return }
            do {
                let usage = try await self.claude.fetchPlan()
                await MainActor.run {
                    self.lastClaudePlan = usage
                    self.lastClaudePlanHint = nil
                    self.planBackoffUntil = nil
                    self.planBackoffLevel = 0
                    if self.snapshot.provider == .claude {
                        self.snapshot.planUsage = usage
                        self.snapshot.planUsageHint = nil
                    }
                }
            } catch let err as ClaudePlanFetcher.FetchError {
                await MainActor.run {
                    if case .http(429) = err {
                        self.planBackoffLevel = min(self.planBackoffLevel + 1, 4)
                        let delay = 120.0 * pow(2, Double(self.planBackoffLevel - 1))
                        self.planBackoffUntil = Date().addingTimeInterval(delay)
                    }
                    self.lastClaudePlanHint = ClaudePlanFetcher.hint(for: err)
                    // Stale data is more useful than nothing — only clear on
                    // explicit auth failure.
                    if case .unauthorized = err { self.lastClaudePlan = nil }
                    if self.snapshot.provider == .claude {
                        self.snapshot.planUsageHint = self.lastClaudePlanHint
                        if case .unauthorized = err { self.snapshot.planUsage = nil }
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastClaudePlanHint = ClaudePlanFetcher.hint(for: .transport(error))
                    if self.snapshot.provider == .claude {
                        self.snapshot.planUsageHint = self.lastClaudePlanHint
                    }
                }
            }
        }
    }

    // MARK: - File poll (both providers, auto merge)

    private func refresh() {
        refreshQueue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            let snaps = self.providers.compactMap { $0.computeSnapshot(now: now) }
            // "Auto": the provider with the most recent activity wins.
            let winner = snaps.max {
                ($0.lastActivity ?? .distantPast) < ($1.lastActivity ?? .distantPast)
            }
            DispatchQueue.main.async {
                guard var w = winner else { return }
                // Re-apply the out-of-band Claude plan-% (refreshed on a
                // separate, slower timer) so the file poll doesn't drop it.
                if w.provider == .claude {
                    // Don't republish a plan reading whose window has already
                    // reset server-side — after a fetch failure `lastClaudePlan`
                    // is intentionally kept (stale > nothing), but once its
                    // `resetsAt` is in the past the utilization and clock are
                    // simply wrong, so drop it rather than drive the pill from
                    // an expired window.
                    if let p = self.lastClaudePlan, !p.isExpired(asOf: now) {
                        w.planUsage = p
                    }
                    w.planUsageHint = self.lastClaudePlanHint
                }
                // Most 5s ticks produce an identical snapshot; skipping the
                // no-op publish saves a full SwiftUI diff of the island (and
                // the hit-area/click-through churn that follows it).
                if self.snapshot != w { self.snapshot = w }
            }
        }
    }
}
