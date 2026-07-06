import SwiftUI

/// User-selectable motion feel for the island. Faster presets tighten the
/// spring response; slower ones soften it. Mirrors the DynamicNotch engine's
/// five-step scale, retitled in VibeNotch's plain-string style (no localization
/// keys). Surfaced in Settings in a later phase; `balanced` is the default.
enum NotchAnimationPreset: String, CaseIterable, Identifiable {
    case snappy
    case fast
    case balanced
    case slow
    case relaxed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .snappy:   return "Snappy"
        case .fast:     return "Fast"
        case .balanced: return "Balanced"
        case .slow:     return "Slow"
        case .relaxed:  return "Relaxed"
        }
    }

    var systemImage: String {
        switch self {
        case .snappy:   return "hare.fill"
        case .fast:     return "speedometer"
        case .balanced: return "gauge"
        case .slow:     return "hourglass"
        case .relaxed:  return "tortoise.fill"
        }
    }

    var help: String {
        switch self {
        case .snappy:   return "The fastest island motion, with the tightest response"
        case .fast:     return "Quicker than balanced, still smoother than snappy"
        case .balanced: return "The default spring feel — good for everyday use"
        case .slow:     return "A calmer preset with gentler motion than the default"
        case .relaxed:  return "The slowest and softest island motion"
        }
    }
}
