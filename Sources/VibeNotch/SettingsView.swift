import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    let closeAction: () -> Void
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var keychainGranted: Bool = ClaudePlanFetcher.hasOAuthToken
    @ObservedObject private var appearance: AppearanceStore = .shared
    @ObservedObject private var placement: PlacementStore = .shared
    @Environment(\.ccTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: centered title with back chip overlaid on the leading
            // edge. Built as a Text + .overlay so the title's centering is
            // calculated against the full row width, independent of the
            // chip's size.
            Text("Settings")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(theme.text(.primary))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 28)
                .overlay(alignment: .leading) {
                    Button(action: closeAction) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Back")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(theme.text(.primary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(theme.chrome(0.12)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Back to stats")
                }

            Divider().background(theme.chrome(0.08))

            // Placement picker: anchored under the notch, or free-floating
            // anywhere the user drags it.
            VStack(alignment: .leading, spacing: 8) {
                Text("Placement")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(theme.text(.tertiary))
                HStack(spacing: 3) {
                    ForEach(Placement.allCases) { option in
                        PlacementChip(
                            option: option,
                            selected: placement.mode == option,
                            theme: theme
                        ) {
                            placement.mode = option
                        }
                    }
                }
            }

            Divider().background(theme.chrome(0.08))

            // Appearance picker. 5 options: Auto/Dark/Light + two glass
            // variants (clear material vs. soft white tint). "Auto" follows
            // the macOS system Dark/Light setting.
            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(theme.text(.tertiary))
                HStack(spacing: 3) {
                    ForEach(Appearance.allCases) { option in
                        AppearanceChip(
                            option: option,
                            selected: appearance.current == option,
                            theme: theme
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                appearance.current = option
                            }
                        }
                    }
                }
            }

            Divider().background(theme.chrome(0.08))

            // Bottom row: toggle on the leading edge, Quit on the trailing
            // edge. Sharing a row instead of giving Quit its own bottom
            // band kills the dead space and keeps the destructive action
            // visually separate from primary toggles.
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("Launch at login")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(theme.text(.secondary))
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
                // Keychain trust indicator (Claude only). Green checkmark = the
                // user granted access; orange lock = denied or no `claude /login`
                // token in the Keychain yet. Codex needs no keychain — its
                // plan-% is read straight from the local ~/.codex session logs.
                HStack(spacing: 4) {
                    Image(systemName: keychainGranted ? "checkmark.shield.fill" : "lock.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(keychainGranted ? .green : .orange)
                    Text(keychainGranted ? "Keychain (Claude)" : "No access")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.text(.secondary))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(theme.chrome(0.08)))
                .help(keychainGranted
                    ? "Keychain access granted — Claude plan-usage % is the exact figure from Anthropic. (Codex plan-% comes from local ~/.codex logs — no keychain needed.)"
                    : "No Keychain access — run `claude /login` or relaunch VibeNotch and click Always Allow when prompted. (This is for Claude only; Codex needs no keychain.)")
                .onTapGesture {
                    keychainGranted = ClaudePlanFetcher.hasOAuthToken
                }
                Spacer(minLength: 8)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.red.opacity(0.55)))
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

/// One segment of the appearance picker. Selected state shows a filled chip
/// in the accent color; unselected is a translucent chrome chip.
private struct AppearanceChip: View {
    let option: Appearance
    let selected: Bool
    let theme: Theme
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(option.label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(selected ? .white : theme.text(.secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                    selected
                        ? theme.accentStart
                        : theme.chrome(hover ? 0.14 : 0.08)
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(option.help)
    }
}

/// Two-option chip for the Placement picker. Same visual treatment as
/// `AppearanceChip` so the Settings panel reads as one consistent control.
private struct PlacementChip: View {
    let option: Placement
    let selected: Bool
    let theme: Theme
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(option.label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(selected ? .white : theme.text(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                    selected
                        ? theme.accentStart
                        : theme.chrome(hover ? 0.14 : 0.08)
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(option.help)
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
            .fill(isOn
                  ? Color(nsColor: .systemGreen)
                  : Color(nsColor: .quaternaryLabelColor))
            .frame(width: trackWidth, height: trackHeight)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .offset(x: isOn ? travel : -travel)
            )
            .overlay(
                Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
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
