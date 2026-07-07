import SwiftUI
import AppKit
import Combine

/// Drives the **menu-bar placement**: a text item in the system menu bar that
/// reads "23% · 8:45 PM", with a click popping a compact stats card. Owns its
/// `NSStatusItem` and `NSPopover`; `AppDelegate` calls `activate()` /
/// `deactivate()` as the user switches placement modes.
///
/// This is intentionally separate from the floating `IslandView` pill — menu
/// bar apps follow a different interaction model (a status item + on-demand
/// popover, not an always-present hover pill), so reusing the island's hover
/// geometry here would be a poor fit. The popover hosts its own `MenuBarCard`,
/// which shares the island's data and visual language.
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let monitor: UsageMonitor
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []
    /// Last title written, so an unchanged snapshot doesn't re-set the title
    /// (which forces AppKit to re-measure and re-lay-out the item needlessly).
    private var lastTitle: String?

    init(monitor: UsageMonitor) {
        self.monitor = monitor
        super.init()
    }

    /// Whether the menu-bar item is currently installed.
    var isActive: Bool { statusItem != nil }

    /// Install the status item and start mirroring usage into its title.
    func activate() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem = item
        refreshTitle()

        // Mirror every snapshot change into the title. `.receive(on:)` keeps
        // the UI update on the main actor even though the monitor may publish
        // from a background poll completion.
        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshTitle() }
            .store(in: &cancellables)
    }

    /// Remove the status item and tear down the popover/subscriptions.
    func deactivate() {
        cancellables.removeAll()
        if let popover, popover.isShown { popover.performClose(nil) }
        popover = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        lastTitle = nil   // so a later re-activate writes the first title fresh
    }

    /// Build the menu-bar title and write it only if it changed. Skipping
    /// no-op writes avoids needless re-layout of the status item.
    private func refreshTitle() {
        guard let button = statusItem?.button else { return }
        let title = Self.menuTitle(for: monitor.snapshot)
        guard title != lastTitle else { return }
        lastTitle = title
        button.title = title
    }

    /// Build the menu-bar title: "23% · 8:45 PM" when plan data is available,
    /// otherwise a token/cost fallback so the item is never blank.
    ///
    /// The menu-bar item is `variableLength`, so its width follows the title's
    /// rendered width and the item visibly slides left/right whenever that
    /// width changes. Two things drive that: the percent's digit count
    /// (`9%` → `100%`) and the clock's hour digit count (`8:45 PM` is one glyph
    /// narrower than `12:45 PM`). Monospaced digits alone don't fix it — they
    /// equalize same-length digit runs, not different-length ones. So we pad
    /// both fields to a fixed width with FIGURE SPACE (U+2007), which renders
    /// at digit width in the monospaced-digit font and never collapses. The
    /// result is a constant-width title that doesn't jitter as the numbers or
    /// the clock change.
    static func menuTitle(for s: UsageSnapshot) -> String {
        if let five = s.planUsage?.fiveHour {
            let pct = Int((max(0, min(1, five.utilization)) * 100).rounded())
            let pctField = padLeft("\(pct)%", toWidth: 4)   // "  7%" … "100%"
            if let reset = five.resetsAt {
                return "\(pctField) · \(stableClock(reset))"
            }
            return pctField
        }
        // No plan budget (e.g. Codex, or pre-login Claude) — show block tokens.
        if s.tokensBlock > 0 {
            return UsageFormat.tokens(s.tokensBlock)
        }
        return "—"
    }

    /// Figure space (U+2007): a typographic space the width of a digit. Used to
    /// pad numeric fields so they hold a constant width without shifting.
    private static let figureSpace = "\u{2007}"

    /// Left-pads `s` with figure spaces to a fixed character width, so the
    /// field's rendered width is constant regardless of how many digits the
    /// value has. No-op if `s` is already at least that wide.
    private static func padLeft(_ s: String, toWidth width: Int) -> String {
        let pad = width - s.count
        guard pad > 0 else { return s }
        return String(repeating: figureSpace, count: pad) + s
    }

    /// Clock string with a constant width. `DateFormatter`'s short style emits a
    /// 1- or 2-digit hour (`8:45 PM` vs `12:45 PM`), which changes the item's
    /// width every time the hour crosses that boundary. We pad a single-digit
    /// hour with one figure space so the field is always the 2-digit-hour width.
    private static func stableClock(_ date: Date) -> String {
        let raw = clockFormatter.string(from: date)
        // The hour is the run of digits before the first ":". If it's a single
        // digit, prepend one figure space to match the 2-digit-hour width.
        if let colon = raw.firstIndex(of: ":") {
            let hourDigits = raw.distance(from: raw.startIndex, to: colon)
            if hourDigits == 1 { return figureSpace + raw }
        }
        return raw
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }
        let pop = NSPopover()
        pop.behavior = .transient            // auto-closes when you click away
        pop.delegate = self
        // The card is dark-only; force the popover chrome (arrow, corner
        // material) dark too, so light-mode users don't get a light arrow
        // pointing at a black card.
        pop.appearance = NSAppearance(named: .darkAqua)
        pop.contentViewController = NSHostingController(
            rootView: MenuBarCard(monitor: monitor)
                .environment(\.ccTheme, Theme(resolved: .dark))
        )
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = pop
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}

/// The compact card shown when the menu-bar item is clicked. Mirrors the
/// island's expanded card — model header, session gauge, reset countdown,
/// today's spend — in a self-contained popover-sized view. Reads the same
/// `monitor.snapshot` so the numbers always agree with the pill.
private struct MenuBarCard: View {
    @ObservedObject var monitor: UsageMonitor
    @Environment(\.ccTheme) private var theme
    @State private var showSettings = false
    /// Slow display clock for the countdown strings — the snapshot publisher
    /// is deduplicated, so an open popover needs its own tick to stay fresh.
    @State private var now = Date()

    private static let displayTick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var s: UsageSnapshot { monitor.snapshot }

    var body: some View {
        Group {
            if showSettings {
                // Instant swap, like the island — no fancy settings animation.
                SettingsView(closeAction: { showSettings = false })
            } else {
                stats
            }
        }
        // Generous inset to match the island card's breathing room.
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        // One fixed width for both faces (stats and Settings) so the popover
        // never resizes when you toggle into Settings. 360 fits the Settings
        // picker rows; the stats face centers within it.
        .frame(width: 360)
        .background(theme.panelFill)
        .onReceive(Self.displayTick) { now = $0 }
    }

    private var stats: some View {
        // Same rhythm as the island's expanded card: 16pt whitespace between
        // sections (no hairline dividers), the shared SESSION / TODAY blocks,
        // and the gear living in the header — so the two faces read identically.
        VStack(alignment: .leading, spacing: 16) {
            header
            SessionSection(snapshot: s, now: now)
            TodaySection(snapshot: s)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ModelDot(model: s.currentModel, traits: s.currentModelTraits)
            Text(modelName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(theme.text(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            // Live status, single line, immediately left of the gear — the
            // same cluster the island header uses.
            if s.workState != .idle {
                HStack(spacing: 6) {
                    if s.workState == .working {
                        PulsingDots(color: theme.text(.primary))
                    } else {
                        WorkDot(state: s.workState)
                    }
                    Text(s.workState == .working ? "Working" : "Waiting")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.text(.secondary))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            // The gear is the menu-bar popover's only way into Settings (which
            // is how you switch back to Notch / Free), so it lives in the
            // header exactly like the island's — and Quit lives inside Settings
            // for both faces.
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.text(.tertiary))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(theme.chrome(0.08)))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private var modelName: String {
        ModelDisplay.displayName(for: s.currentModel)
    }
}
