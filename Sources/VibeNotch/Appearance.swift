import SwiftUI
import AppKit
import Combine

/// Resolved "concrete" appearance — what actually gets rendered. VibeNotch is
/// dark-only (the island has to vanish into the black camera-housing notch), so
/// `light` is retained only as a dormant code path in `Theme`; nothing produces
/// it at runtime.
enum ResolvedAppearance {
    case dark
    case light
}

/// Global appearance store. VibeNotch ships dark-only — there's no user-facing
/// light/auto switch — so `resolved` is a constant. Kept as an
/// `ObservableObject` singleton so the views' `@ObservedObject` wiring and the
/// `.environment(\.ccTheme)` plumbing stay unchanged.
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()
    private init() {}

    var resolved: ResolvedAppearance { .dark }
}

/// Color tokens. Every surface in the island reads from here so a single
/// appearance change re-paints everything coherently.
struct Theme {
    let resolved: ResolvedAppearance

    /// True when the resolved palette is light — drives text color picks.
    var isLight: Bool { resolved == .light }

    var panelFill: Color {
        isLight ? Color(white: 0.97) : .black
    }

    var borderTopHighlight: Color {
        isLight ? .black.opacity(0.10) : .white.opacity(0.12)
    }
    var borderBottomShade: Color {
        isLight ? .black.opacity(0.02) : .white.opacity(0.02)
    }

    var shadow: Color {
        isLight ? .black.opacity(0.18) : .black.opacity(0.45)
    }

    var primaryText: Color {
        isLight ? Color(white: 0.08) : .white
    }

    /// Apple HIG-style named opacity tiers. Mirrors `NSColor.labelColor`,
    /// `secondaryLabelColor`, etc. — primary 100%, secondary ~78%, tertiary
    /// ~52%, quaternary ~32%. Replaces ad-hoc opacity values across the UI
    /// so the hierarchy reads consistently.
    enum TextTier { case primary, secondary, tertiary, quaternary }
    func text(_ tier: TextTier) -> Color {
        let alpha: Double
        switch tier {
        case .primary:    alpha = 1.0
        case .secondary:  alpha = 0.78
        case .tertiary:   alpha = 0.52
        case .quaternary: alpha = 0.32
        }
        return isLight ? Color(white: 0.08).opacity(alpha) : .white.opacity(alpha)
    }

    func secondaryText(_ alpha: Double = 0.65) -> Color {
        isLight ? Color(white: 0.08).opacity(alpha) : .white.opacity(alpha)
    }

    func chrome(_ alpha: Double = 0.08) -> Color {
        isLight ? .black.opacity(alpha) : .white.opacity(alpha)
    }

    var progressTrack: Color { chrome(0.08) }

    var accentStart: Color {
        isLight
            ? Color(red: 0.20, green: 0.55, blue: 0.95)
            : Color(red: 0.55, green: 0.85, blue: 1.0)
    }
    var accentEnd: Color {
        isLight
            ? Color(red: 0.35, green: 0.35, blue: 0.95)
            : Color(red: 0.45, green: 0.55, blue: 1.0)
    }
}

extension View {
    /// Fills an accessory's background with a flat `fill` behind the given
    /// shape — trait chips, the ×N badge, progress tracks, the keychain pill.
    /// (Formerly a Liquid Glass surface; the app is now opaque-only.)
    func chromeBackground<S: Shape>(in shape: S, fill: Color) -> some View {
        background(shape.fill(fill))
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(resolved: .dark)
}

extension EnvironmentValues {
    var ccTheme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
