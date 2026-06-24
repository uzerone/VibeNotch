import SwiftUI
import Combine

/// What gesture opens (and closes) the expanded stats card.
///
/// • `hover` — the card expands while the cursor is over the pill and
///   collapses when it leaves. The original, zero-click behaviour.
/// • `click` — the card stays put until you click the pill; click again
///   (or click any empty area of the card) to collapse. Friendlier when you
///   want to read the stats without holding the cursor in place, or on a
///   trackpad where hovering the notch is fiddly.
enum ExpandTrigger: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hover: return "Hover"
        case .click: return "Click"
        }
    }

    var systemImage: String {
        switch self {
        case .hover: return "cursorarrow.rays"
        case .click: return "cursorarrow.click"
        }
    }

    var help: String {
        switch self {
        case .hover: return "Expand while hovering, collapse when the cursor leaves"
        case .click: return "Click to expand, click again to collapse"
        }
    }
}

/// Stores the user's expand-trigger choice. Mirrors `PlacementStore` /
/// `AppearanceStore` — a shared singleton backed by `UserDefaults` that the
/// island view observes so a change re-wires the gesture immediately.
final class ExpandTriggerStore: ObservableObject {
    static let shared = ExpandTriggerStore()

    private static let key = "VibeNotch.expandTrigger"

    @Published var current: ExpandTrigger {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ExpandTrigger.hover.rawValue
        self.current = ExpandTrigger(rawValue: raw) ?? .hover
    }
}
