import SwiftUI
import AppKit
import Combine

/// How the island is positioned on screen.
///
/// • `notch` — anchored under the menu bar / camera notch, top-center.
///   Square top edge so it merges visually with the menu bar.
/// • `freeMove` — floats anywhere; user drags the pill to position it.
///   Fully-rounded silhouette since it's no longer docking to anything.
/// • `menuBar` — no floating pill at all; a text item in the system menu bar
///   shows "23% · 8:45 PM", and clicking it pops the full stats card.
enum Placement: String, CaseIterable, Identifiable {
    case notch
    case freeMove = "free_move"
    case menuBar = "menu_bar"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notch:    return "Notch"
        case .freeMove: return "Free"
        case .menuBar:  return "Menu"
        }
    }

    var systemImage: String {
        switch self {
        case .notch:    return "rectangle.topthird.inset.filled"
        case .freeMove: return "arrow.up.and.down.and.arrow.left.and.right"
        case .menuBar:  return "menubar.rectangle"
        }
    }

    var help: String {
        switch self {
        case .notch:    return "Anchored under the menu bar / notch"
        case .freeMove: return "Drag to place anywhere on screen"
        case .menuBar:  return "Show usage as a menu-bar item; click for details"
        }
    }
}

/// Stores the user's placement choice and — for free-move mode — the last
/// origin the user dragged the window to (in screen coords). AppDelegate
/// observes both: mode changes trigger a reposition; the origin is updated
/// when the user finishes dragging so it survives restarts.
final class PlacementStore: ObservableObject {
    static let shared = PlacementStore()

    private static let modeKey = "VibeNotch.placement"
    private static let originXKey = "VibeNotch.freeOriginX"
    private static let originYKey = "VibeNotch.freeOriginY"

    @Published var mode: Placement {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    /// Whether the Mac's built-in (notched) display is currently present —
    /// i.e. the lid is open. AppDelegate refreshes this from `NSScreen` on
    /// launch and whenever the screen configuration changes (lid open/close,
    /// display connect/disconnect). When false (lid closed / clamshell), the
    /// notch is physically gone, so `.notch` placement is neither offered nor
    /// allowed — only Menu and Free remain, defaulting to Menu.
    @Published var notchAvailable: Bool = true {
        didSet {
            // Lid just closed while docked to the notch: there's no camera
            // housing to anchor to anymore, so fall back to the menu-bar item
            // (the requested clamshell default) rather than stranding the pill.
            if !notchAvailable && mode == .notch {
                mode = .menuBar
            }
        }
    }

    /// Placement modes offered in Settings, given the current lid state.
    /// Lid open: all three. Lid closed: Menu + Free only (no notch to dock to).
    /// Order matches `Placement.allCases` so the segmented control is stable.
    var availablePlacements: [Placement] {
        notchAvailable ? Placement.allCases : [.menuBar, .freeMove]
    }

    /// Last window origin (bottom-left, screen coords) in free-move mode.
    /// `nil` until the user moves the window at least once; AppDelegate
    /// falls back to screen-center on first switch.
    @Published var freeOrigin: CGPoint? {
        didSet {
            if let p = freeOrigin {
                UserDefaults.standard.set(p.x, forKey: Self.originXKey)
                UserDefaults.standard.set(p.y, forKey: Self.originYKey)
            }
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.modeKey) ?? Placement.notch.rawValue
        self.mode = Placement(rawValue: raw) ?? .notch

        let d = UserDefaults.standard
        if d.object(forKey: Self.originXKey) != nil,
           d.object(forKey: Self.originYKey) != nil {
            self.freeOrigin = CGPoint(x: d.double(forKey: Self.originXKey),
                                      y: d.double(forKey: Self.originYKey))
        } else {
            self.freeOrigin = nil
        }
    }
}
