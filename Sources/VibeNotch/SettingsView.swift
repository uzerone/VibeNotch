import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    let closeAction: () -> Void
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var keychainGranted: Bool = ClaudePlanFetcher.hasOAuthToken
    @ObservedObject private var placement: PlacementStore = .shared
    @ObservedObject private var expandTrigger: ExpandTriggerStore = .shared
    @Environment(\.ccTheme) private var theme

    var body: some View {
        // System-Settings-style panel: captions + whitespace do the grouping
        // (matching the stats face's calm-minimal rhythm), controls are
        // neutral elevated segments — no accent-washed blocks — and the
        // destructive Quit is quiet.
        VStack(alignment: .leading, spacing: 14) {
            // Header: centered title, with a compact circular back button on
            // the leading edge — the mirror of the gear that opened us.
            Text("Settings")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(theme.text(.primary))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 24)
                .overlay(alignment: .leading) {
                    Button(action: closeAction) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.text(.tertiary))
                            .frame(width: 22, height: 22)
                            .chromeBackground(in: Circle(), fill: theme.chrome(0.08))
                    }
                    .buttonStyle(.plain)
                    .help("Back to stats")
                }

            Divider().background(theme.chrome(0.06))

            // Placement: anchored under the notch, free-floating, or menu bar.
            VStack(alignment: .leading, spacing: 6) {
                SectionCaption("PLACEMENT")
                SegmentedRow(
                    options: Placement.allCases,
                    isSelected: { placement.mode == $0 },
                    select: { placement.mode = $0 },
                    theme: theme
                )
            }

            // Expand trigger: open the stats card on hover, or on click.
            VStack(alignment: .leading, spacing: 6) {
                SectionCaption("EXPAND")
                SegmentedRow(
                    options: ExpandTrigger.allCases,
                    isSelected: { expandTrigger.current == $0 },
                    select: { expandTrigger.current = $0 },
                    theme: theme
                )
            }

            // Login row: label left, switch right — one setting per row, the
            // System Settings way, so nothing ever wraps.
            HStack {
                Text("Run at login")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.text(.secondary))
                    .lineLimit(1)
                Spacer()
                GreenSwitch(isOn: $launchAtLogin)
            }
            .onChange(of: launchAtLogin) { newValue in
                do {
                    try LoginItem.set(enabled: newValue)
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                    launchAtLogin = LoginItem.isEnabled
                }
            }

            // Bottom row: keychain trust status (quiet, tappable to refresh)
            // on the left; Quit on the right as red text on neutral chrome —
            // destructive but not shouting.
            HStack {
                // Keychain trust indicator (Claude only). Green checkmark = the
                // user granted access; orange lock = denied or no `claude
                // /login` token in the Keychain yet. Codex needs no keychain —
                // its plan-% is read straight from local ~/.codex session logs.
                HStack(spacing: 4) {
                    Image(systemName: keychainGranted ? "checkmark.shield.fill" : "lock.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(keychainGranted ? .green : .orange)
                    Text(keychainGranted ? "Keychain (Claude)" : "No access")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(theme.text(.tertiary))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .chromeBackground(in: Capsule(), fill: theme.chrome(0.06))
                .help(keychainGranted
                    ? "Keychain access granted — Claude plan-usage % is the exact figure from Anthropic. (Codex plan-% comes from local ~/.codex logs — no keychain needed.)"
                    : "No Keychain access — run `claude /login` or relaunch VibeNotch and click Always Allow when prompted. (This is for Claude only; Codex needs no keychain.)")
                .onTapGesture {
                    keychainGranted = ClaudePlanFetcher.hasOAuthToken
                }
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(nsColor: .systemRed))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .chromeBackground(in: Capsule(), fill: theme.chrome(0.08))
                }
                .buttonStyle(.plain)
                .help("Quit VibeNotch")
            }

            if let err = loginError {
                Text(err)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(.orange.opacity(0.9))
                    .lineLimit(2)
            }
        }
    }
}

/// Shared shape of the two picker option types — label + SF symbol + tooltip.
private protocol SegmentOption: Identifiable, Equatable {
    var label: String { get }
    var systemImage: String { get }
    var help: String { get }
}

extension Placement: SegmentOption {}
extension ExpandTrigger: SegmentOption {}

/// macOS-native-feeling segmented control: one recessed container, equal
/// segments, the selected one elevated on a *neutral* fill (no accent wash),
/// exactly like the pickers in System Settings' dark appearance.
private struct SegmentedRow<Option: SegmentOption>: View {
    let options: [Option]
    let isSelected: (Option) -> Bool
    let select: (Option) -> Void
    let theme: Theme

    @State private var hovered: Option.ID?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = isSelected(option)
                Button {
                    select(option)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(option.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundColor(selected ? theme.text(.primary) : theme.text(.tertiary))
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected
                                  ? theme.chrome(0.18)
                                  : theme.chrome(hovered == option.id ? 0.08 : 0.0))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hovered = option.id }
                    else if hovered == option.id { hovered = nil }
                }
                .help(option.help)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.chrome(0.06))
        )
    }
}

/// Custom SwiftUI switch that's guaranteed green when on, regardless of
/// the user's macOS accent color. SwiftUI's native `.switch` toggle style
/// on macOS ignores `.tint(.green)` and uses the system accent instead —
/// so we render the capsule + knob ourselves and control the palette.
/// Visually matches macOS System Settings toggles.
struct GreenSwitch: View {
    @Binding var isOn: Bool

    private let trackWidth: CGFloat = 32
    private let trackHeight: CGFloat = 18
    private var knobDiameter: CGFloat { trackHeight - 4 }
    private var travel: CGFloat { (trackWidth - knobDiameter) / 2 - 1 }

    var body: some View {
        Capsule()
            // Off track must stay visible on the pure-black card —
            // quaternaryLabelColor vanished there, leaving a floating knob.
            .fill(isOn
                  ? Color(nsColor: .systemGreen)
                  : Color.white.opacity(0.16))
            .frame(width: trackWidth, height: trackHeight)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .offset(x: isOn ? travel : -travel)
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    isOn.toggle()
                }
            }
            .accessibilityRepresentation { Toggle("", isOn: $isOn) }
    }
}

/// Toggles launch-at-login via the modern `SMAppService` API (macOS 13+).
/// Falls back gracefully on older systems by reporting via a thrown error.
enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func set(enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw NSError(domain: "VibeNotch", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Requires macOS 13+"])
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
