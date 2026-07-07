import SwiftUI

/// Left light: identifies which Claude model is active. Color = family,
/// secondary cues encode variants:
///   • a soft halo ring → 1M-context variant
///   • a faint inner sparkle pulse → extended-thinking enabled
struct ModelDot: View {
    let model: String?
    let traits: ModelTraits
    @State private var blink = false

    var body: some View {
        ZStack {
            // Halo for 1M-context variant.
            if traits.oneMillionContext {
                Circle()
                    .strokeBorder(color.opacity(0.55), lineWidth: 1)
                    .frame(width: 14, height: 14)
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 4)
                // Subtle blink for sessions using extended thinking —
                // a session-level cue, not a per-phase indicator.
                .opacity(traits.thinking ? (blink ? 0.15 : 1.0) : 1.0)
                .animation(traits.thinking
                           ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                           : .default,
                           value: blink)
        }
        .frame(width: 14, height: 14)
        .onAppear { blink = true }
    }

    private var color: Color {
        ModelDot.colorForModel(model)
    }

    static func colorForModel(_ model: String?) -> Color {
        guard let m = model?.lowercased() else { return Color.gray.opacity(0.55) }
        // Fable / Mythos — flagship rose-magenta. The warmest, most saturated
        // hue in the set so the top-tier model stands apart from the cool
        // Claude trio (purple/blue/mint) and the teal Codex, while staying
        // clear of the amber reserved for "approaching limit".
        if m.contains("fable") || m.contains("mythos") {
            return Color(red: 1.00, green: 0.42, blue: 0.72)
        }
        // Opus — electric royal purple. Bright and saturated so it reads
        // crisp at the 8pt dot scale, but still distinctively "Opus" in
        // the purple family.
        if m.contains("opus")   { return Color(red: 0.72, green: 0.42, blue: 1.00) }
        // Sonnet — modern blue. Confident contemporary indigo-blue,
        // balanced between cool and neutral. The kind of blue you see in
        // well-designed productivity apps.
        if m.contains("sonnet") { return Color(red: 0.28, green: 0.58, blue: 1.00) }
        // Haiku — energetic mint-green. Light and alive, mirroring Haiku's
        // speed-and-lightness positioning. Distinct from both the regal
        // purple and the cool blue.
        if m.contains("haiku")  { return Color(red: 0.28, green: 0.88, blue: 0.65) }
        // OpenAI Codex (gpt-5.x / codex) — signature teal-green. Distinct from
        // all three Claude families so the "auto" pill makes the active
        // provider obvious at a glance.
        if m.hasPrefix("gpt") || m.contains("codex")
            || m.contains("o3") || m.contains("o4") {
            return Color(red: 0.10, green: 0.72, blue: 0.55)
        }
        return Color.gray.opacity(0.55)
    }
}

/// Right light: working status. Color = state, animation = liveness.
///   • orange slow pulse → actively writing (rarely rendered — the dropdown's
///     pulsing dots carry the working state; this remains as a fallback)
///   • green fast blink → waiting on the user
///   • gray steady → idle
struct WorkDot: View {
    let state: WorkState
    @State private var pulse = false

    private var color: Color {
        switch state {
        case .idle: return Color.gray.opacity(0.55)
        case .working: return Color(red: 1.0, green: 0.55, blue: 0.15)
        case .awaitingDecision: return Color.green
        }
    }

    private var period: Double? {
        switch state {
        case .idle: return nil
        case .working: return 0.9
        case .awaitingDecision: return 0.45
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.6), radius: 4)
            .scaleEffect(period != nil && pulse ? 1.35 : 1.0)
            .opacity(period != nil && pulse
                     ? (state == .awaitingDecision ? 0.3 : 0.6)
                     : 1.0)
            .animation(period.map { .easeInOut(duration: $0).repeatForever(autoreverses: true) }
                       ?? .default,
                       value: pulse)
            .onAppear { pulse = true }
    }
}

/// FINISH state checkmark with a soft breathing pulse. The work dot
/// (which used to convey "waiting on you" via a fast blink) is hidden
/// in the awaiting state, so this carries that signal — gentler than
/// the dot's old fast strobe but persistent enough to draw the eye.
struct PulsingCheckmark: View {
    @State private var pulse = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.green)
            .shadow(color: Color.green.opacity(0.55), radius: pulse ? 4 : 1.5)
            .scaleEffect(pulse ? 1.12 : 1.0)
            .opacity(pulse ? 0.88 : 1.0)
            .animation(
                .easeInOut(duration: 0.95).repeatForever(autoreverses: true),
                value: pulse
            )
            .onAppear { pulse = true }
    }
}

/// Three small dots that pulse in sequence — the canonical "loading"
/// indicator from iOS Dynamic Island. Each dot fades on a staggered
/// delay so the row reads as a left-to-right wave.
struct PulsingDots: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(animating ? 1.0 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

/// One colored slice of the session gauge — a model family's share of the
/// used portion. `share` values across a track sum to 1.
struct TrackSegment: Identifiable, Equatable {
    let label: String
    let color: Color
    let share: Double
    var id: String { label }
}

/// HIG-aligned linear progress indicator with gauge-style semantic
/// coloring: the fill shifts from the cool accent gradient to a warm
/// amber as utilization climbs past 80% — same rule the iOS Battery
/// gauge follows. Below 80% reads as "you have headroom", above signals
/// "approaching limit".
///
/// When `segments` carries more than one model family, the used portion is
/// drawn as stacked family-colored slices — the one bar answers both "how
/// much" (length) and "which model" (color). The semantic warning fill
/// always wins past 80%: safety signal over decoration.
struct ProgressTrack: View {
    let progress: Double
    var segments: [TrackSegment] = []
    @Environment(\.ccTheme) private var theme

    private var fillColors: [Color] {
        if progress >= 0.95 {
            // Critical — saturated coral. Same vibe as system red without
            // shouting.
            return [Color(red: 1.0, green: 0.45, blue: 0.40),
                    Color(red: 1.0, green: 0.30, blue: 0.30)]
        } else if progress >= 0.8 {
            // Caution — amber gradient. Reads as warm but not alarming.
            return [Color(red: 1.0, green: 0.75, blue: 0.35),
                    Color(red: 1.0, green: 0.55, blue: 0.25)]
        }
        return [theme.accentStart, theme.accentEnd]
    }

    private var showsModelSplit: Bool {
        segments.count > 1 && progress < 0.8
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Empty track behind the colored fill.
                Capsule()
                    .fill(theme.progressTrack)
                if showsModelSplit {
                    // Family-colored slices of the used portion. A 2pt floor
                    // keeps a sliver visible for tiny shares; the total still
                    // reads correctly at gauge scale.
                    HStack(spacing: 1) {
                        ForEach(segments) { seg in
                            Capsule()
                                .fill(seg.color)
                                .frame(width: max(2, geo.size.width * progress * seg.share))
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: progress)
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(colors: fillColors,
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(4, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.35), value: progress)
                }
            }
        }
        .frame(height: 6)
    }
}

