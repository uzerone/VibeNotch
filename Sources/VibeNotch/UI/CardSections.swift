import SwiftUI

/// Shared building blocks for the two stats faces — the island's expanded
/// card and the menu-bar popover card. Both render the same SESSION and
/// TODAY sections from the same snapshot, so keeping the blocks here
/// guarantees the two faces never drift apart (they briefly did: 30pt vs
/// 32pt heroes, popover missing the weekly row).
///
/// Every view takes `now` explicitly so the caller's refresh tick (a slow
/// 30s timer) drives countdown strings deterministically.

/// Uniform section caption — small, tracked, tertiary. Every block (SESSION,
/// TODAY, the model split) leads with one, so the eye navigates the card by
/// its headings instead of by guessing the hierarchy from number sizes.
struct SectionCaption: View {
    let text: String
    @Environment(\.ccTheme) private var theme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundColor(theme.text(.tertiary))
    }
}

/// The reset row, sitting directly under the session gauge — a clock glyph,
/// the human countdown ("2h 13m left"), and the exact reset time. This is
/// the prominent home for the "when does my quota refresh" answer.
struct ResetRow: View {
    let snapshot: UsageSnapshot
    let now: Date
    @Environment(\.ccTheme) private var theme

    var body: some View {
        // No trailing spacer — the row hugs its content so it centers under
        // the gauge inside the section's centered column.
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.text(.tertiary))
            Text(snapshot.sessionResetDate.map { UsageFormat.countdown(to: $0, now: now) } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(theme.text(.secondary))
                .monospacedDigit()
            Text("· resets \(snapshot.sessionResetDate.map(UsageFormat.clock) ?? "—")")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(theme.text(.tertiary))
                .monospacedDigit()
        }
    }
}

/// SESSION / 5-HOUR BLOCK section: plan-% gauge when the authoritative
/// figure is available, token+cost dual hero otherwise; then the reset row,
/// a plan-fetch hint when the gauge is missing for a fixable reason, and —
/// only once it's high enough to matter (≥ 50%) — the weekly bucket. Below
/// that threshold weekly is noise: the session gauge already tells you
/// you're fine. (The "information diet": surface a metric only when it
/// changes a decision.)
struct SessionSection: View {
    let snapshot: UsageSnapshot
    let now: Date
    @Environment(\.ccTheme) private var theme

    /// Per-model-family slices of this session block, for the in-track split
    /// and the legend row. Variants of one family (opus-4-6, opus-4-7 …)
    /// collapse into one slice with the shared family color; shares sum to 1.
    private var familySegments: [TrackSegment] {
        let totalTokens = snapshot.tokensByModelBlock.values.reduce(0, +)
        guard totalTokens > 0 else { return [] }
        var tokensByFamily: [String: Int] = [:]
        for (model, tokens) in snapshot.tokensByModelBlock {
            tokensByFamily[ModelDisplay.familyLabel(for: model), default: 0] += tokens
        }
        return tokensByFamily
            .sorted { $0.value > $1.value }
            .map { family, tokens in
                TrackSegment(
                    label: family,
                    color: ModelDot.colorForModel(ModelDisplay.idForFamily(family)),
                    share: Double(tokens) / Double(totalTokens)
                )
            }
    }

    /// Per-family dollar cost, carried in the legend's tooltip so the row
    /// itself stays one short line.
    private var costByFamily: [String: Double] {
        var costs: [String: Double] = [:]
        for (model, cost) in snapshot.costByModelBlock {
            costs[ModelDisplay.familyLabel(for: model), default: 0] += cost
        }
        return costs
    }

    /// One short centered line under the reset row: dot + family + share %.
    /// Dollar figures live in the hover tooltip — the gauge above already
    /// carries the proportions visually.
    @ViewBuilder
    private var familyLegend: some View {
        let segments = familySegments
        if segments.count > 1 {
            HStack(spacing: 12) {
                ForEach(segments) { seg in
                    HStack(spacing: 4) {
                        Circle().fill(seg.color).frame(width: 5, height: 5)
                        Text("\(seg.label) \(Int((seg.share * 100).rounded()))%")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.text(.tertiary))
                            .monospacedDigit()
                    }
                }
            }
            .help(segments.map { seg in
                let cost = costByFamily[seg.label] ?? 0
                return String(format: "%@ %d%% · $%.2f", seg.label, Int((seg.share * 100).rounded()), cost)
            }.joined(separator: "   "))
        }
    }

    var body: some View {
        // Centered column: the notch sits on the screen's center axis, so the
        // stat blocks mirror that symmetry instead of hugging the left edge.
        VStack(alignment: .center, spacing: 6) {
            SectionCaption(snapshot.planUsage?.fiveHour != nil ? "SESSION" : "5-HOUR BLOCK")
            if let five = snapshot.planUsage?.fiveHour {
                // Single hero: the session-used %. TODAY below carries spend,
                // and the gauge carries the rest.
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    // The card's single hero — the only bold element on the
                    // face, sized so the eye lands here first by construction.
                    Text(UsageFormat.percent(five.utilization))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(theme.text(.primary))
                        .monospacedDigit()
                    Text("used")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(theme.text(.tertiary))
                }
                // The used portion is sliced by model family when more than
                // one is in play — one bar answers "how much" and "who".
                ProgressTrack(progress: max(0, min(1, five.utilization)),
                              segments: familySegments)
            } else {
                // Dual-hero treatment: tokens on the left, dollars on the
                // right — both at the same display size so neither visually
                // outranks the other.
                // Dual-hero fallback: 32pt (not the single hero's 40) — two
                // numbers plus a label must share the ~280pt row, and 40pt
                // pairs overflow it once the token count grows past 5 glyphs.
                // Welded and centered like the rest of the stat blocks.
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(UsageFormat.tokens(snapshot.tokensBlock))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(theme.text(.primary))
                        .monospacedDigit()
                    Text("tokens")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(theme.text(.tertiary))
                    Text("·")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.text(.quaternary))
                    Text(String(format: "$%.2f", snapshot.costBlock))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(theme.text(.primary))
                        .monospacedDigit()
                }
                ProgressTrack(progress: snapshot.blockProgress(asOf: now))
            }
            ResetRow(snapshot: snapshot, now: now)
            // Per-model share of this session — replaces the old separate
            // BY MODEL block; the gauge above carries the same proportions
            // in color, this row just names them.
            familyLegend
            // Why the plan-% gauge is missing, when the user can fix it
            // ("token expired — run claude /login"). Only shown while the
            // gauge is actually absent — a transient network blip behind a
            // still-valid stale reading isn't worth alarming over.
            if snapshot.planUsage?.fiveHour == nil, let hint = snapshot.planUsageHint {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.orange)
                    Text(hint)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.orange.opacity(0.9))
                        .lineLimit(1)
                }
            }
            if let seven = snapshot.planUsage?.sevenDay, seven.utilization >= 0.5 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Weekly")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(theme.text(.tertiary))
                    Text(UsageFormat.percent(seven.utilization))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.text(.secondary))
                        .monospacedDigit()
                    ProgressTrack(progress: max(0, min(1, seven.utilization)))
                        .frame(maxWidth: 120)
                    Spacer()
                    if let reset = seven.resetsAt {
                        Text("resets \(UsageFormat.weekday(reset))")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(theme.text(.quaternary))
                    }
                }
            }
        }
    }
}

/// Today summary — secondary to the Session hero above. The dollar amount
/// anchors the left; the token count is the quieter metric, right-aligned.
/// Smaller than the gauge % so the eye reads Session first, Today second.
struct TodaySection: View {
    let snapshot: UsageSnapshot
    @Environment(\.ccTheme) private var theme

    var body: some View {
        // Centered like SESSION above — the welded dollars · tokens cluster
        // sits on the card's center axis, mirroring the notch.
        VStack(alignment: .center, spacing: 6) {
            SectionCaption("TODAY")
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "$%.2f", snapshot.costToday))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.text(.primary))
                    .monospacedDigit()
                // A typographic middot, not a Circle — a 2pt shape dropped to
                // the text baseline read as a stray period.
                Text("·")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.text(.quaternary))
                Text(UsageFormat.tokens(snapshot.tokensToday))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.text(.secondary))
                    .monospacedDigit()
                Text("tokens")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.text(.tertiary))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
