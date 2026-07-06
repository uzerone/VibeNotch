import SwiftUI
import Combine

/// Stores the user's island-motion preset. Mirrors `ExpandTriggerStore` /
/// `PlacementStore` — a shared singleton backed by `UserDefaults` that the
/// island view observes, so changing the preset re-tunes the springs live.
///
/// Defaults to `.balanced` (the DynamicNotch engine's everyday feel). A
/// Settings picker can surface this later; for now it's a stable, centralized
/// source of truth the motion code reads.
final class AnimationPreferenceStore: ObservableObject {
    static let shared = AnimationPreferenceStore()

    private static let key = "VibeNotch.animationPreset"

    @Published var preset: NotchAnimationPreset {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? NotchAnimationPreset.balanced.rawValue
        self.preset = NotchAnimationPreset(rawValue: raw) ?? .balanced
    }
}
