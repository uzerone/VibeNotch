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

/// HIG-aligned linear progress indicator with gauge-style semantic
/// coloring: the fill shifts from the cool accent gradient to a warm
/// amber as utilization climbs past 80% — same rule the iOS Battery
/// gauge follows. Below 80% reads as "you have headroom", above signals
/// "approaching limit".
struct ProgressTrack: View {
    let progress: Double
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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Empty track behind the colored fill.
                Capsule()
                    .fill(theme.progressTrack)
                Capsule()
                    .fill(
                        LinearGradient(colors: fillColors,
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(4, geo.size.width * progress))
                    .animation(.easeInOut(duration: 0.35), value: progress)
            }
        }
        .frame(height: 6)
    }
}

/// Horizontal stacked bar showing per-model usage. Each segment is
/// colored by its `ModelDot` family color; the legend shows name +
/// percentage + dollar cost so users can tell at a glance which model
/// is doing the work AND which is doing the spending (Opus ≈ 5× Sonnet).
struct ModelSplitBar: View {
    struct Segment: Identifiable {
        let label: String
        let fraction: Double
        let cost: Double
        let color: Color
        var id: String { label }
    }
    let title: String
    let segments: [Segment]

    /// Lays out segment widths so the bar never overflows its track. The naïve
    /// `width * fraction` overflows once the (n-1) inter-segment gaps and the
    /// per-segment minimum are added in. Here we lay out within the width that
    /// remains after spacing, apply a `minWidth` floor, then rescale the result
    /// down if the floors pushed the total back over budget.
    static func segmentWidths(fractions: [Double],
                              available: CGFloat,
                              spacing: CGFloat,
                              minWidth: CGFloat = 2) -> [CGFloat] {
        guard !fractions.isEmpty else { return [] }
        let usable = max(0, available - spacing * CGFloat(fractions.count - 1))
        let total = fractions.reduce(0, +)
        // Distribute `usable` by fraction, flooring each at `minWidth`.
        var widths = fractions.map { f -> CGFloat in
            let raw = total > 0 ? usable * CGFloat(f / total) : usable / CGFloat(fractions.count)
            return max(minWidth, raw)
        }
        // The floors can push the sum back over `usable`; rescale to fit.
        let sum = widths.reduce(0, +)
        if sum > usable, sum > 0 {
            let scale = usable / sum
            widths = widths.map { $0 * scale }
        }
        return widths
    }

    @Environment(\.ccTheme) private var theme

    var body: some View {
        // De-crammed three-row layout: caption alone, then the bar, then the
        // legend on its own left-origin row. Nothing right-justified into the
        // card edge, so cost figures never kiss the border, and the bar gets
        // real air instead of being pinched under a crowded title line.
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(theme.text(.tertiary))
            GeometryReader { geo in
                let spacing: CGFloat = 1
                let widths = Self.segmentWidths(
                    fractions: segments.map(\.fraction),
                    available: geo.size.width,
                    spacing: spacing)
                HStack(spacing: spacing) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                        Capsule()
                            .fill(seg.color)
                            .frame(width: widths[idx])
                    }
                }
            }
            .frame(height: 6)
            // Legend below the bar: dot + name + percent + cost per segment,
            // anchored left with the trailing spacer eating the empty width.
            HStack(spacing: 14) {
                ForEach(segments) { seg in
                    HStack(spacing: 4) {
                        Circle().fill(seg.color).frame(width: 6, height: 6)
                        Text("\(seg.label) \(Int((seg.fraction * 100).rounded()))%")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.text(.secondary))
                            .monospacedDigit()
                        if seg.cost > 0 {
                            Text(String(format: "$%.2f", seg.cost))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(theme.text(.tertiary))
                                .monospacedDigit()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
