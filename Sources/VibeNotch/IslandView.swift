import SwiftUI
import AppKit

/// Holds the current target geometry. The AppDelegate updates this when the
/// active screen changes (e.g. lid open/close); the view observes it and
/// re-lays out automatically.
final class IslandConfig: ObservableObject {
    @Published var geometry: IslandGeometry

    init(geometry: IslandGeometry) {
        self.geometry = geometry
    }
}

/// Shared between the SwiftUI view and the `NSHostingView` subclass: tells
/// the host where the currently-visible pill is (in window coordinates) so
/// clicks outside that rect can pass through to whatever is beneath.
final class HitArea: ObservableObject {
    @Published var rect: CGRect = .zero
}

/// Geometry derived from `NSScreen` per Apple HIG. `notchHeight` is the
/// `safeAreaInsets.top` on a notched Mac, otherwise the menu-bar thickness.
/// `notchWidth` is the gap between `auxiliaryTopLeftArea` and
/// `auxiliaryTopRightArea`, or 0 on non-notched displays.
struct IslandGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    /// Host screen width, used to derive `scale`. Defaults to the DynamicNotch
    /// reference width so the placeholder geometry (before a real screen is
    /// bound) computes a sane scale of 1.0.
    var screenWidth: CGFloat = 1440

    /// True when the host screen has a real camera-housing notch; false for
    /// external displays, where we just lay out as a top-center pill.
    var hasPhysicalNotch: Bool { notchWidth > 0 }

    // MARK: - study (DynamicNotch) base geometry
    //
    // These mirror DynamicNotch's `NotchViewModel.updateDimensions()` +
    // `NotchModel` exactly, so the collapsed pill hugs the real notch the way
    // the reference engine does.

    /// Screen-relative scale. `max(0.35, screenWidth / 1440)` — the reference
    /// 1440pt base width, floored so tiny screens don't collapse the pill.
    var scale: CGFloat { max(0.35, screenWidth / 1440) }

    /// Collapsed base width. On a real notch: the camera-housing width plus a
    /// small scaled margin (`notchWidth + 14·scale`) so the pill sits flush
    /// around the housing. On external / notchless displays: `190·scale`.
    var baseWidth: CGFloat {
        hasPhysicalNotch ? notchWidth + 14 * scale : 190 * scale
    }

    /// Collapsed base height. On a real notch: the safe-area inset (the notch's
    /// own height). On external displays: `25·scale`.
    var baseHeight: CGFloat {
        hasPhysicalNotch ? notchHeight : 25 * scale
    }

    /// Base corner radius — `baseHeight / 3`, per the reference. Collapsed
    /// corners derive from this: bottom = `baseRadius`, top flare =
    /// `baseRadius − 4`.
    var baseRadius: CGFloat { baseHeight / 3 }

    /// Collapsed island width is the study base width — it hugs the real notch
    /// rather than being floored to a fixed minimum.
    var collapsedWidth: CGFloat { baseWidth }

    /// Idle collapsed: a pill the exact shape of the notch — visually
    /// indistinguishable from the camera housing.
    var idleSize: CGSize {
        CGSize(width: baseWidth, height: baseHeight)
    }

    /// Active collapsed: notch row + an info row dropping down below it.
    var activeSize: CGSize {
        CGSize(width: baseWidth, height: baseHeight + dropdownHeight)
    }

    var dropdownHeight: CGFloat { 30 }

    /// Expanded card: a modern rounded rectangle that grows downward from
    /// the notch line. Width is independent of the notch. When docked
    /// under the notch, we add `notchHeight` so the band hidden behind
    /// the camera housing doesn't eat into the visible card area.
    ///
    /// Height is sized to fit the Settings panel (header + Placement + Expand +
    /// login/Quit row); the pared-down stats view is shorter and just runs with
    /// extra breathing room.
    ///
    /// Width 384: after the dashboard's information diet, 420 left too much
    /// empty horizontal space, while 384 still comfortably fits the Settings
    /// bottom row (login toggle + keychain pill + Quit).
    func expandedSize(dockedUnderNotch: Bool) -> CGSize {
        let topBand = dockedUnderNotch ? notchHeight : 0
        // 232 is the BASE card: margins + header + SESSION (caption, 40pt
        // hero, track, reset row) + TODAY. Optional blocks add their own
        // height on top (see the extra-height constants below) so the card
        // hugs its content instead of reserving dead space for sections
        // that aren't showing.
        return CGSize(width: 384, height: topBand + 232)
    }

    /// Convenience for the docked default.
    var expandedSize: CGSize { expandedSize(dockedUnderNotch: hasPhysicalNotch) }

    /// Extra card height per optional row, so the silhouette hugs whatever
    /// is actually showing:
    /// • plan-fetch hint (orange row in SESSION)
    /// • weekly gauge row (7-day ≥ 50%)
    /// • per-model legend under the session track (> 1 model family)
    /// The Settings face has its own fixed height — its content doesn't vary.
    static let planHintExtraHeight: CGFloat = 22
    static let weeklyExtraHeight: CGFloat = 19
    static let modelLegendExtraHeight: CGFloat = 17
    static let settingsFaceHeight: CGFloat = 270

    /// Fixed window size — the tallest possible card (every optional row at
    /// once, or the Settings face if taller) plus a little slack. The window
    /// is transparent and click-through outside the pill rect, so oversizing
    /// the canvas costs nothing; the drawn card sizes itself within it. Used
    /// by AppDelegate for the window and by the view as the outer bound when
    /// publishing the hit rect.
    var canvasSize: CGSize {
        let s = expandedSize
        let maxExtras = max(
            Self.planHintExtraHeight + Self.weeklyExtraHeight + Self.modelLegendExtraHeight,
            Self.settingsFaceHeight - 232
        )
        return CGSize(width: s.width, height: s.height + maxExtras + 8)
    }

    /// Corner radius for the expanded card — fixed, modern rounded-rect feel
    /// rather than a giant pill.
    var expandedCornerRadius: CGFloat { 28 }
}

struct IslandView: View {
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var config: IslandConfig
    /// Write-only from this view (the host reads it for hit-testing) — held as
    /// a plain reference, NOT `@ObservedObject`, so publishing a new rect
    /// doesn't re-render the island that just wrote it.
    let hitArea: HitArea
    @ObservedObject var appearance: AppearanceStore = .shared
    @ObservedObject var placement: PlacementStore = .shared
    @ObservedObject var expandTrigger: ExpandTriggerStore = .shared
    @ObservedObject var motionPref: AnimationPreferenceStore = .shared

    @State private var expanded = false
    @State private var showSettings = false
    @State private var finishVisibleUntil: Date?
    /// The pill's live rendered size, updated continuously by a GeometryReader
    /// as the silhouette morphs. `updateHitArea()` prefers this over the
    /// discrete target `size` so the click region tracks the animation.
    @State private var livePillSize: CGSize = .zero
    /// Slow display clock for the time-derived strings (countdowns, "Xm ago",
    /// block progress). The snapshot publisher is deduplicated, so without
    /// this tick an idle card's "2h 13m left" would freeze.
    @State private var now = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let displayTick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// How long FINISH stays visible in notch mode before auto-dismissing
    /// back to the resets-countdown view. On external display / free-move
    /// the banner persists as long as the real state holds.
    private static let finishAutoDismissSeconds: TimeInterval = 4

    private var geometry: IslandGeometry { config.geometry }
    private var theme: Theme { Theme(resolved: appearance.resolved) }
    private var isFreeMove: Bool { placement.mode == .freeMove }

    /// Whether the card expands on hover (default) or on click. Drives which
    /// gesture is wired to `expanded` in the body.
    private var isClickToExpand: Bool { expandTrigger.current == .click }

    /// Apple HIG-aligned animation curves. One spring for UI interaction
    /// (hover/expand/settings), one slightly slower for the drop-in/out from
    /// the notch. Reduce Motion downgrades both to a brief fade.
    private var uiSpring: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.4, dampingFraction: 0.86)
    }
    private var dropSpring: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.22)
            : .spring(response: 0.55, dampingFraction: 0.82)
    }

    /// Notch-emergence transition for the content that swaps between the
    /// collapsed pill and the expanded card. Instead of a flat cross-fade, the
    /// content scales + blurs + shifts as if it grew out of (or retreated into)
    /// the black notch housing — the signature Dynamic Island morph. Reduce
    /// Motion falls back to a plain fade.
    ///
    /// `isExpandedPresentation` picks the flavor: the card unfurls downward
    /// from the notch line, while the collapsed dropdown puffs from the notch
    /// center. Geometry is read live so the compensation offsets track the
    /// pill's actual width/height in the current placement.
    private func contentTransition(expandedPresentation: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .notchContent(
            notchWidth: geometry.collapsedWidth,
            notchHeight: expandedPresentation ? size.height : geometry.activeSize.height,
            baseHeight: geometry.baseHeight,
            isExpandedPresentation: expandedPresentation
        )
    }

    /// The coordinated spring bundle that drives the island's silhouette morph.
    /// Selected from the user's motion preset; the floating capsule (no physical
    /// notch) gets slightly lower damping for a touch more bounce, matching the
    /// iPhone Dynamic Island feel. This replaces VibeNotch's two ad-hoc springs
    /// as the driver for the size/shape morph so idle↔active↔expanded all move
    /// with one coherent, tuned response.
    private var islandAnimations: NotchAnimations {
        let isCapsule = isFreeMove || !geometry.hasPhysicalNotch
        return .preset(motionPref.preset, isDynamicIsland: isCapsule)
    }

    /// The spring the silhouette resize rides. Under Reduce Motion it collapses
    /// to a brief fade-equivalent ease so the pill still settles without a
    /// bouncy morph.
    private var surfaceSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : islandAnimations.surfaceResize
    }

    /// The *bottom* corner radius of the pill/card silhouette (fed to
    /// `MorphNotchShape.bottomCornerRadius`).
    ///
    /// • Expanded card: the designed rounded-rect radius.
    /// • Collapsed: the study `baseRadius` (= `baseHeight / 3`), so the pill's
    ///   lower corners round exactly like the reference DynamicNotch pill.
    /// • Free-move: the `fullyRounded` shape path uses this on all four corners,
    ///   giving a capsule when `baseRadius` ≈ half the height.
    private var morphCornerRadius: CGFloat {
        if expanded { return geometry.expandedCornerRadius }
        return geometry.baseRadius
    }

    /// On a real notched MacBook display in notch placement, the collapsed
    /// pill must remain black so it visually merges with the camera
    /// housing. In free-move mode the pill isn't docked to the notch, so
    /// the user's theme always applies.
    private var effectiveTheme: Theme {
        if !isFreeMove && geometry.hasPhysicalNotch && !expanded {
            return Theme(resolved: .dark)
        }
        return theme
    }

    /// True when the island is rendered at all. Active states always show;
    /// the bare idle pill additionally stays present — and hoverable — where
    /// it can do so unobtrusively: docked over a physical notch it camouflages
    /// as the camera housing, and in free-move it's the user's own widget
    /// (dimmed when idle). Without this, an idle island had a zero hit-area
    /// and Settings became unreachable until new usage appeared. On external
    /// displays in notch placement the pill still vanishes when empty — a
    /// black pill under the menu bar has nothing to hide behind.
    private var visible: Bool {
        expanded || hasDropdownState || idleTargetAvailable
    }

    private var idleTargetAvailable: Bool {
        isFreeMove || geometry.hasPhysicalNotch
    }

    /// The bare idle pill in free-move mode dims so it reads as a dormant
    /// widget, not a stuck black blob. Docked over the notch it stays fully
    /// opaque — it must be pure black to merge with the housing.
    private var idleOpacity: Double {
        isFreeMove ? 0.5 : 1.0
    }

    private var hasRecentBlock: Bool {
        if let u = monitor.snapshot.planUsage?.fiveHour?.utilization, u > 0 { return true }
        return monitor.snapshot.blockStart != nil && monitor.snapshot.tokensBlock > 0
    }

    /// The dropdown row is meaningful in three cases: actively WORKING
    /// (pulsing dots), waiting on a decision (FINISH checkmark), or
    /// between turns with a live 5h block (tokens + resets clock). Outside
    /// these, the pill stays as the bare idle silhouette.
    private var hasDropdownState: Bool {
        monitor.snapshot.isWorking
            || displayedIsAwaitingDecision
            || hasRecentBlock
    }

    /// Real `isAwaitingDecision` filtered through the notch-mode
    /// auto-dismiss timer. In notch placement the FINISH banner shows for
    /// `finishAutoDismissSeconds`, then collapses to the resets view so
    /// it doesn't squat under the camera housing for the rest of the
    /// session. Elsewhere (external / free-move) the banner persists.
    private var displayedIsAwaitingDecision: Bool {
        guard monitor.snapshot.isAwaitingDecision else { return false }
        let inNotchMode = geometry.hasPhysicalNotch && !isFreeMove
        guard inNotchMode else { return true }
        if let until = finishVisibleUntil, Date() < until { return true }
        return false
    }

    /// Arms (or clears) the notch-mode FINISH auto-dismiss window. Centralized
    /// so it can run on the `isAwaitingDecision` transition *and* whenever the
    /// banner first becomes eligible without a transition — on view appear, or
    /// when switching into notch placement while already awaiting. Without this,
    /// a state that was already true (no `onChange` fires) would never arm the
    /// timer and the FINISH banner would be silently suppressed.
    private func armFinishTimerIfNeeded() {
        guard monitor.snapshot.isAwaitingDecision else { finishVisibleUntil = nil; return }
        guard finishVisibleUntil == nil else { return }   // already armed
        let until = Date().addingTimeInterval(Self.finishAutoDismissSeconds)
        finishVisibleUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishAutoDismissSeconds + 0.05) {
            if finishVisibleUntil == until { finishVisibleUntil = nil }
        }
    }

    /// Whether the plan-fetch hint row is currently part of the card —
    /// it adds height, so the expanded silhouette must grow with it.
    private var showsPlanHint: Bool {
        monitor.snapshot.planUsage?.fiveHour == nil
            && monitor.snapshot.planUsageHint != nil
    }

    /// Whether SessionSection is currently rendering its weekly gauge row —
    /// must mirror that view's own `>= 0.5` threshold so the card grows with it.
    private var showsWeeklyRow: Bool {
        (monitor.snapshot.planUsage?.sevenDay?.utilization ?? 0) >= 0.5
    }

    private var size: CGSize {
        let docked = geometry.hasPhysicalNotch && !isFreeMove
        if expanded {
            var s = geometry.expandedSize(dockedUnderNotch: docked)
            if showSettings {
                // Settings has fixed content — one fixed face height.
                s.height = (docked ? geometry.notchHeight : 0) + IslandGeometry.settingsFaceHeight
                return s
            }
            // Stats face hugs its content: optional rows add their height.
            if showsPlanHint { s.height += IslandGeometry.planHintExtraHeight }
            if showsWeeklyRow { s.height += IslandGeometry.weeklyExtraHeight }
            if modelSplitWorthShowing { s.height += IslandGeometry.modelLegendExtraHeight }
            return s
        }
        if hasDropdownState { return geometry.activeSize }
        return geometry.idleSize
    }

    /// The card's background silhouette: a solid fill + a gradient hairline
    /// edge + layered contact/ambient shadows so it reads as a panel floating
    /// above the desktop.
    private func panelBackground(_ t: Theme) -> some View {
        shape
            .fill(t.panelFill)
            .overlay(
                shape
                    .strokeBorder(
                        LinearGradient(colors: [
                            t.borderTopHighlight,
                            t.borderBottomShade
                        ], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5
                    )
            )
            // Layered shadows simulate `backgroundExtensionEffect` —
            // a tight contact shadow plus a wider ambient halo so the
            // card reads as floating above the desktop, with its
            // presence extending past the visible silhouette.
            .shadow(color: t.shadow.opacity(0.7), radius: 6, y: 2)
            .shadow(color: t.shadow.opacity(0.45), radius: 24, y: 14)
    }

    var body: some View {
        let t = effectiveTheme
        return VStack(spacing: 0) {
            ZStack {
                panelBackground(t)

                if expanded {
                    Group {
                        if showSettings {
                            SettingsView(closeAction: {
                                // Settings enter/exit is an instant swap — no
                                // spring/morph. The card stays put; only its
                                // contents switch between stats and settings.
                                showSettings = false
                            })
                        } else {
                            expandedContent
                        }
                    }
                    // Horizontal inset sizes the content to fit *inside* the
                    // NotchShape's throat (48pt top flare over a physical
                    // notch), plus a real breathing margin so nothing reads
                    // as touching the silhouette. 56pt docked / 32pt elsewhere.
                    .padding(.horizontal, (geometry.hasPhysicalNotch && !isFreeMove) ? 56 : 32)
                    // Top inset clears the camera housing AND the visible
                    // throat (flare 48 closes at y=48 = notchHeight+16), then
                    // adds margin so the header doesn't sit right at the
                    // throat's lip.
                    .padding(.top, (geometry.hasPhysicalNotch && !isFreeMove)
                                   ? geometry.notchHeight + 20
                                   : 16)
                    .padding(.bottom, 20)
                    // Top-align so an overflowing SettingsView never gets
                    // vertically centered — that was clipping the header
                    // ("Settings" + back button) above the visible card.
                    .frame(maxHeight: .infinity, alignment: .top)
                    // Unfurl downward from the notch line instead of fading in.
                    .transition(contentTransition(expandedPresentation: true))
                } else {
                    collapsedContent
                        // Puff out from / retreat into the notch center.
                        .transition(contentTransition(expandedPresentation: false))
                }
            }
            .frame(width: size.width, height: size.height)
            // Publish the *live* rendered pill size while it morphs, so the
            // click hit-area tracks the animating silhouette instead of jumping
            // to the target size the instant a transition starts. During a
            // spring resize SwiftUI runs intermediate layout passes, so this
            // reader fires continuously and keeps clicks aligned with what's
            // actually on screen. Placed inside the frame → reports the animated
            // frame; the outer scaleEffect (drop-in) is a visibility flip where
            // precise hit-testing doesn't matter.
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { livePillSize = proxy.size }
                        .onChange(of: proxy.size) { livePillSize = $0 }
                }
            )
            // `mask` instead of `clipShape`: keeps the rounded silhouette
            // without forcing the offscreen render pass that breaks the
            // NSVisualEffectView blur in glass mode.
            .mask(shape)
            .contentShape(shape)
            // "Drops down" from the notch: vertical scale 0 → 1 anchored at
            // the top edge makes the pill extrude downward. Opacity fades in
            // slightly later so the motion reads as growth, not a pop.
            .scaleEffect(x: 1, y: visible ? 1 : 0.02, anchor: .top)
            .opacity(visible
                     ? ((expanded || hasDropdownState) ? 1 : idleOpacity)
                     : 0)
            .animation(dropSpring, value: visible)
            // The silhouette morph — idle ↔ active (dropdown) ↔ expanded — now
            // rides the tuned island spring so the width/height/corner-radius
            // interpolate as one coherent Dynamic-Island motion instead of the
            // old ad-hoc drop spring. `size` and `morphCornerRadius` are both
            // functions of `hasDropdownState`/`expanded`, so animating on those
            // keys carries the whole continuous morph.
            .animation(surfaceSpring, value: hasDropdownState)
            .animation(surfaceSpring, value: expanded)
            .onHover { hovering in
                // Hover-to-expand only. In click mode the cursor entering or
                // leaving the pill must not change the expanded state — taps
                // own it there.
                guard !isClickToExpand else { return }
                // Hold expanded open while the settings panel is in use, even
                // if the cursor briefly slips outside the card.
                if !hovering && showSettings { return }
                // Expand rides the tuned island spring so the silhouette and its
                // content grow together coherently (the `.transition` and the
                // frame/radius `.animation(surfaceSpring, value: expanded)` then
                // share one response).
                withAnimation(surfaceSpring) {
                    expanded = hovering
                }
            }
            // Click-to-expand: tapping the pill toggles it. A tap on an inner
            // control (the gear) is consumed by that control first, so this
            // only fires for the pill background — collapsing from empty space
            // works, while the gear still opens Settings. No-op in hover mode.
            .onTapGesture {
                guard isClickToExpand else { return }
                // Leaving Settings open while collapsing would strand the panel;
                // collapse always returns to the stats face.
                withAnimation(surfaceSpring) {
                    if expanded { showSettings = false }
                    expanded.toggle()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.ccTheme, t)
        .onAppear { updateHitArea(); armFinishTimerIfNeeded() }
        .onReceive(Self.displayTick) { now = $0 }
        .onChange(of: visible) { _ in updateHitArea() }
        .onChange(of: expanded) { _ in updateHitArea() }
        .onChange(of: monitor.snapshot.hasActivity) { _ in updateHitArea() }
        // Track the live morphing frame — this fires on every intermediate
        // layout pass during a spring resize, keeping the click region glued to
        // the animating silhouette.
        .onChange(of: livePillSize) { _ in updateHitArea() }
        .onChange(of: size.width) { _ in updateHitArea() }
        .onChange(of: size.height) { _ in updateHitArea() }
        .onChange(of: geometry.expandedSize.width) { _ in updateHitArea() }
        .onChange(of: geometry.expandedSize.height) { _ in updateHitArea() }
        // Arm the FINISH auto-dismiss timer the moment `isAwaitingDecision`
        // flips true. Schedule a delayed re-render so the dropdown
        // collapses cleanly when the window passes — without needing
        // UsageMonitor to tick at exactly the right moment.
        .onChange(of: monitor.snapshot.isAwaitingDecision) { _ in armFinishTimerIfNeeded() }
        // Re-arm when entering notch placement while already awaiting — the
        // snapshot didn't transition, so the line above wouldn't fire.
        .onChange(of: isFreeMove) { _ in armFinishTimerIfNeeded() }
        .onChange(of: geometry.hasPhysicalNotch) { _ in armFinishTimerIfNeeded() }
        // Smart animation — every state change in the snapshot interpolates
        // through the same spring as hover/expand. Chips appearing, lights
        // hiding when work starts, model swaps mid-session, dropdown text
        // switching between WORKING / FINISH / resets — all coherent.
        .animation(uiSpring, value: monitor.snapshot.workState)
        .animation(uiSpring, value: monitor.snapshot.currentModel)
        .animation(uiSpring, value: monitor.snapshot.currentModelTraits.thinking)
        .animation(uiSpring, value: monitor.snapshot.currentModelTraits.oneMillionContext)
        .animation(uiSpring, value: monitor.snapshot.currentModelTraits.fastMode)
        .animation(uiSpring, value: monitor.snapshot.activeSessions)
        .animation(uiSpring, value: hideLightsForActiveState)
        // Optional rows growing/shrinking the expanded card interpolate
        // through the springs instead of snapping — the silhouette morphs
        // with each row that appears (hint, weekly gauge, model legend).
        .animation(uiSpring, value: showsPlanHint)
        .animation(surfaceSpring, value: showsWeeklyRow)
        .animation(surfaceSpring, value: modelSplitWorthShowing)
    }

    /// Publishes the visible pill rect in NSHostingView coordinates so the
    /// host can mask off clicks outside it. When the island is hidden
    /// (idle + not expanded), the rect is empty so every click falls through.
    private func updateHitArea() {
        let rect: CGRect
        if visible {
            // Prefer the live morphing size; fall back to the discrete target
            // before the GeometryReader has reported (first frame / onAppear).
            let pill = livePillSize == .zero ? size : livePillSize
            let outer = geometry.canvasSize
            rect = CGRect(
                x: (outer.width - pill.width) / 2,
                y: outer.height - pill.height,
                width: pill.width,
                height: pill.height
            )
        } else {
            rect = .zero
        }
        // Skip no-op writes — every publish re-runs the host's click-through
        // evaluation.
        if hitArea.rect != rect { hitArea.rect = rect }
    }

    /// The pill silhouette.
    /// The pill / card silhouette — a `MorphNotchShape` (VibeNotch's port of
    /// DynamicNotch's `NotchShape`).
    ///
    /// Docked under the notch, the top edge is full-width and flat at the notch
    /// line, and the top two corners tuck **inward** (a concave throat) as the
    /// sides descend, so the surface reads as growing out of the black camera
    /// housing exactly like the reference. The bottom corners are convex. The
    /// expanded card keeps the same throat — content is sized to fit inside the
    /// throat rather than the shape being changed to fit the content.
    ///
    /// Free-move detaches from any edge, so there it's a fully-rounded capsule
    /// (all four corners convex) instead.
    private var shape: some InsettableShape {
        MorphNotchShape(
            topFlareRadius: topFlareRadius,
            bottomCornerRadius: morphCornerRadius,
            fullyRounded: isFreeMove
        )
    }

    /// How far the top corners tuck inward — the concave notch throat that
    /// makes the surface read as growing out of the notch line.
    ///
    /// • Free-move: 0 — the fully-rounded capsule path ignores it anyway.
    /// • On an external display (notch placement, no camera housing): 0 — a
    ///   concave top hanging under a plain menu bar would look wrong, so flat.
    /// • Collapsed pill over a physical notch: the study `baseRadius − 4`
    ///   (≈ 7pt) — a tuck sized to the narrow pill so it folds into the housing.
    /// • Expanded card over a physical notch: a larger, deliberately *visible*
    ///   throat (`expandedTopFlare`, 48pt). The card's top ≈ 32pt band is hidden
    ///   behind the camera housing, so the flare MUST exceed the notch height to
    ///   show the concave throat *below* the housing — 48pt leaves ≈ 16pt of the
    ///   throat visible at the menu-bar line. Content is sized to fit inside the
    ///   resulting 288pt usable mid-width.
    private var topFlareRadius: CGFloat {
        if isFreeMove { return 0 }
        guard geometry.hasPhysicalNotch else { return 0 }
        return expanded ? Self.expandedTopFlare : max(0, geometry.baseRadius - 4)
    }

    /// Pronounced top reverse-corner for the expanded card. Must exceed the
    /// notch height (~32pt) so the inward throat shows below the camera housing;
    /// 48pt reveals ≈ 16pt of throat while the 288pt usable mid-width still
    /// clears the 280pt content (at 52pt horizontal padding).
    private static let expandedTopFlare: CGFloat = 48

/// Collapsed pill. Layout depends on whether the pill is currently
    /// docked under a physical notch.
    ///
    /// • Notched + notch placement: top row is empty (merges with the
    ///   camera housing); lights/info live in a dropdown row below it.
    ///
    /// • External display OR free-move placement: no camera to dodge, so
    ///   the top row IS the pill — lights sit directly on it, flanking
    ///   the info text.
    private var collapsedContent: some View {
        let dockedUnderNotch = geometry.hasPhysicalNotch && !isFreeMove
        if dockedUnderNotch {
            return AnyView(notchCollapsedContent)
        } else {
            return AnyView(externalCollapsedContent)
        }
    }

    /// When the user is actively in WORKING or FINISH state, the dropdown
    /// IS the status indicator (pulsing dots / green checkmark) — side
    /// lights become redundant noise. Hide them so the active state reads
    /// like a clean iOS Dynamic Island moment.
    /// True when the dropdown is in idle-with-block "reset clock only"
    /// mode — model + tokens fall away, leaving a minimal clock chip.
    /// Hover for full details (the expanded card has model + tokens).
    private var isResetOnlyDropdown: Bool {
        hasRecentBlock
            && !monitor.snapshot.isWorking
            && !displayedIsAwaitingDecision
    }

    private var hideLightsForActiveState: Bool {
        monitor.snapshot.isWorking
            || displayedIsAwaitingDecision
            || isResetOnlyDropdown
    }

    /// The idle-state WorkDot is just a static gray dot — it conveys
    /// nothing the absence of animation doesn't already. Skip it.
    private var showWorkDot: Bool {
        !hideLightsForActiveState && monitor.snapshot.workState != .idle
    }

    private var notchCollapsedContent: some View {
        VStack(spacing: 0) {
            // Notch row — flush with the camera housing.
            Color.clear.frame(height: geometry.notchHeight)

            if hasDropdownState {
                HStack(spacing: 0) {
                    if !hideLightsForActiveState {
                        ModelDot(model: monitor.snapshot.currentModel,
                                 traits: monitor.snapshot.currentModelTraits)
                        Spacer(minLength: 6)
                    } else {
                        Spacer(minLength: 0)
                    }
                    dropdownCenter
                    if showWorkDot {
                        Spacer(minLength: 6)
                        WorkDot(state: monitor.snapshot.workState)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: geometry.dropdownHeight)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var externalCollapsedContent: some View {
        // Single horizontal row that fills the pill. Lights only show in
        // idle / between-turns state; during WORKING and FINISH the
        // dropdown content carries the status indicator itself.
        HStack(spacing: 0) {
            if !hideLightsForActiveState {
                ModelDot(model: monitor.snapshot.currentModel,
                         traits: monitor.snapshot.currentModelTraits)
                Spacer(minLength: 6)
            } else {
                Spacer(minLength: 0)
            }
            if hasDropdownState {
                dropdownCenter
                if showWorkDot {
                    Spacer(minLength: 6)
                }
            }
            if showWorkDot {
                WorkDot(state: monitor.snapshot.workState)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }

    /// Pretty display name for the active model — see `ModelDisplay`.
    private var modelDisplayName: String {
        ModelDisplay.displayName(for: monitor.snapshot.currentModel)
    }

    /// Variant tags to chip alongside the model name, each with a tooltip
    /// explaining what it means — most users won't recognize "1M" or "FAST"
    /// without one.
    private var modelTraitTags: [(label: String, help: String)] {
        var tags: [(String, String)] = []
        let t = monitor.snapshot.currentModelTraits
        if t.oneMillionContext {
            tags.append(("1M", "1M-context variant — bigger context window, higher per-token cost"))
        }
        if t.thinking {
            tags.append(("THINKING", "Extended thinking is on — slower, deeper reasoning"))
        }
        if t.fastMode {
            tags.append(("FAST", "/fast mode is toggled — same model at faster output speed"))
        }
        if let e = t.reasoningEffort {
            tags.append((e.uppercased(), "Codex reasoning effort — how much the model deliberates per turn"))
        }
        return tags
    }

    /// Activity-badge style trait chip, inspired by Apple's Landmarks
    /// sample. A tint-gradient capsule with a hairline stroke; the model's hue
    /// is carried by the fill, the stroke, and the text.
    private func traitChip(_ text: String, help: String) -> some View {
        let tint = ModelDot.colorForModel(monitor.snapshot.currentModel)
        return Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.5)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            // Tint-gradient capsule (top→bottom) with the model hue carried by
            // the fill, the hairline stroke, and the foreground.
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.16)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
            )
            .foregroundColor(tint)
            .help(help)
    }

    /// Short one-word status — avoids line-wraps in the header. The active
    /// session count is shown separately as a small badge when > 1.
    /// Mirrors the dropdown's THINKING/WORKING split so the two views
    /// don't disagree about what Claude is doing.
    private var headerLabel: String {
        switch monitor.snapshot.workState {
        case .working:          return "Working"
        case .awaitingDecision: return "Waiting"
        case .idle:             return "Idle"
        }
    }

    private var headerLabelColor: Color { theme.text(.secondary) }

    /// Center text inside the dropdown. State-driven:
    /// - working + thinking → "THINKING · 1h 23m"
    /// - working            → "WORKING · 1h 23m"
    /// - awaitingDecision   → "FINISH"
    /// - idle (block live)  → "14.3k · resets 8:23 AM"
    @ViewBuilder
    private var dropdownCenter: some View {
        // The collapsed pill on a notched display always uses the dark
        // theme (notch illusion), so use effectiveTheme — not the global one.
        let t = effectiveTheme
        if displayedIsAwaitingDecision {
            HStack(spacing: 5) {
                PulsingCheckmark()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6).combined(with: .opacity),
                        removal: .opacity
                    ))
                Text("FINISH")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.green)
            }
            .lineLimit(1)
        } else if monitor.snapshot.isWorking {
            HStack(spacing: 6) {
                PulsingDots(color: workingWordColor)
                Text(workingWord)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(workingWordColor)
                separator
                Text(monitor.snapshot.blockStart.map { UsageFormat.elapsed(since: $0, now: now) } ?? "—")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(t.text(.secondary))
                    .monospacedDigit()
            }
            .lineLimit(1)
        } else {
            // Idle-with-block — utilization % and reset clock, side by
            // side. Lights hide so the dropdown reads as a clean status
            // chip; model + tokens live in the expanded card.
            HStack(spacing: 6) {
                if let five = monitor.snapshot.planUsage?.fiveHour {
                    Text(UsageFormat.percent(five.utilization))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(t.text(.primary))
                        .monospacedDigit()
                } else {
                    Text(UsageFormat.tokens(monitor.snapshot.tokensBlock))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(t.text(.primary))
                        .monospacedDigit()
                }
                separator
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(t.text(.tertiary))
                    Text(monitor.snapshot.sessionResetDate.map(UsageFormat.clock) ?? "—")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(t.text(.secondary))
                        .monospacedDigit()
                }
            }
            .lineLimit(1)
        }
    }

    private var workingWord: String { "WORKING" }

    private var workingWordColor: Color { effectiveTheme.primaryText }

    private var separator: some View {
        Circle()
            .fill(effectiveTheme.text(.quaternary))
            .frame(width: 2, height: 2)
    }

    /// True when more than one model family has tokens in this session block —
    /// SessionSection then shows its per-family legend row (and slices the
    /// gauge), so the card must grow by `modelLegendExtraHeight`. Mirrors the
    /// family aggregation SessionSection itself performs.
    private var modelSplitWorthShowing: Bool {
        var families = Set<String>()
        for (model, tokens) in monitor.snapshot.tokensByModelBlock where tokens > 0 {
            families.insert(ModelDisplay.familyLabel(for: model))
            if families.count > 1 { return true }
        }
        return false
    }

    private var expandedContent: some View {
        let t = theme
        // Calm-minimal rhythm: 16pt of whitespace *is* the section divider —
        // no hairlines in the main stack. Inside each section the spacing is
        // 6pt, so the card reads on exactly two gap sizes and the eye glides.
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ModelDot(model: monitor.snapshot.currentModel,
                         traits: monitor.snapshot.currentModelTraits)
                // The model name is the flexible element in this row — it
                // truncates when space runs short, so the status cluster on
                // the right never has to wrap.
                Text(modelDisplayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(t.text(.primary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                ForEach(modelTraitTags, id: \.label) { tag in
                    traitChip(tag.label, help: tag.help)
                }
                Spacer(minLength: 6)
                // Status cluster sits inline, immediately left of the gear —
                // one row, so the two stop fighting for the top-right corner.
                // The freshness age folds in as "· 12s ago" instead of
                // stacking beneath. Idle = empty cluster, gear stands alone.
                // `fixedSize` + layoutPriority keep the words on ONE line —
                // when the row is tight the model name truncates instead of
                // "Working" wrapping to two lines.
                if monitor.snapshot.workState != .idle {
                    HStack(spacing: 6) {
                        // Match the dropdown's visual language — pulsing
                        // three-dot indicator while working, tinted by the
                        // same workingWordColor so the header and dropdown
                        // agree on what state means.
                        if monitor.snapshot.workState == .working {
                            PulsingDots(color: workingWordColor)
                        } else {
                            WorkDot(state: monitor.snapshot.workState)
                        }
                        Text(headerLabel)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(headerLabelColor)
                            .lineLimit(1)
                        if let last = monitor.snapshot.lastActivity {
                            Text("· \(UsageFormat.relative(last, now: now))")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(t.text(.tertiary))
                                .lineLimit(1)
                        }
                        if monitor.snapshot.activeSessions > 1 {
                            Text("×\(monitor.snapshot.activeSessions)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(t.text(.secondary))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .chromeBackground(in: Capsule(), fill: t.chrome(0.10))
                                .help("\(monitor.snapshot.activeSessions) active sessions")
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                }
                Button {
                    // Instant swap into settings — no fancy animation.
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(t.text(.tertiary))
                        .frame(width: 22, height: 22)
                        .chromeBackground(in: Circle(), fill: t.chrome(0.08))
                }
                .buttonStyle(.plain)
            }

            // SESSION and TODAY are the shared card sections — the same
            // views the menu-bar popover renders, so the two faces always
            // agree on layout and numbers. No hairlines between them: the
            // 16pt root rhythm is the separator. The per-model split lives
            // *inside* SESSION now — the gauge's used portion is sliced by
            // family color, with a one-line legend — so there's no separate
            // BY MODEL block anymore.
            SessionSection(snapshot: monitor.snapshot, now: now)

            TodaySection(snapshot: monitor.snapshot)
        }
    }
}
