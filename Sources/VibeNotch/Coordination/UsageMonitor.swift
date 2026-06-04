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
    private var lastClaudePlanError: ClaudePlanFetcher.FetchError?

    /// Serial queue prevents two refreshes from racing on provider caches.
    private let refreshQueue = DispatchQueue(label: "VibeNotch.refresh", qos: .utility)

    func start() {
        refresh()
        // 5s is a good cadence for the lights; provider caches make most ticks
        // near-free, so we don't gain much by going slower.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Plan-% rarely moves fast and the endpoint is rate-sensitive — 60s
        // is plenty and matches what the web UI seems to poll at.
        refreshPlanUsage()
        planTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshPlanUsage()
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        planTimer?.invalidate(); planTimer = nil
        planTask?.cancel(); planTask = nil
    }

    // MARK: - Plan % (Claude / HTTP)

    private func refreshPlanUsage() {
        planTask?.cancel()
        planTask = Task { [weak self] in
            guard let self else { return }
            do {
                let usage = try await self.claude.fetchPlan()
                await MainActor.run {
                    self.lastClaudePlan = usage
                    self.lastClaudePlanError = nil
                    if self.snapshot.provider == .claude {
                        self.snapshot.planUsage = usage
                        self.snapshot.planUsageError = nil
                    }
                }
            } catch let err as ClaudePlanFetcher.FetchError {
                await MainActor.run {
                    self.lastClaudePlanError = err
                    // Stale data is more useful than nothing — only clear on
                    // explicit auth failure.
                    if case .unauthorized = err { self.lastClaudePlan = nil }
                    if self.snapshot.provider == .claude {
                        self.snapshot.planUsageError = err
                        if case .unauthorized = err { self.snapshot.planUsage = nil }
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastClaudePlanError = .transport(error)
                    if self.snapshot.provider == .claude {
                        self.snapshot.planUsageError = .transport(error)
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
                    if let p = self.lastClaudePlan { w.planUsage = p }
                    w.planUsageError = self.lastClaudePlanError
                }
                self.snapshot = w
            }
        }
    }
}
