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
            .tracking(0.6)
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
            Spacer()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(snapshot.planUsage?.fiveHour != nil ? "SESSION" : "5-HOUR BLOCK")
            if let five = snapshot.planUsage?.fiveHour {
                // Single hero: the session-used %. TODAY below carries spend,
                // and the gauge carries the rest.
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(UsageFormat.percent(five.utilization))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(theme.text(.primary))
                        .monospacedDigit()
                    Text("used")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.text(.tertiary))
                    Spacer()
                }
                ProgressTrack(progress: max(0, min(1, five.utilization)))
            } else {
                // Dual-hero treatment: tokens on the left, dollars on the
                // right — both at the same display size so neither visually
                // outranks the other.
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(UsageFormat.tokens(snapshot.tokensBlock))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(theme.text(.primary))
                        .monospacedDigit()
                    Text("tokens")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.text(.tertiary))
                    Spacer()
                    Text(String(format: "$%.2f", snapshot.costBlock))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(theme.text(.primary))
                        .monospacedDigit()
                }
                ProgressTrack(progress: snapshot.blockProgress(asOf: now))
            }
            ResetRow(snapshot: snapshot, now: now)
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
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption("TODAY")
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "$%.2f", snapshot.costToday))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(theme.text(.primary))
                    .monospacedDigit()
                Spacer()
                Text(UsageFormat.tokens(snapshot.tokensToday))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.text(.secondary))
                    .monospacedDigit()
                Text("tokens")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(theme.text(.tertiary))
            }
        }
    }
}
