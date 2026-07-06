import SwiftUI

/// A bundle of coordinated spring animations that drive every part of the
/// island's motion — surface resize, content show/hide, and content
/// insertion/removal transitions — so they stay in phase with each other. One
/// value per preset; the whole feel of the island is tuned here.
///
/// Adapted from the DynamicNotch engine, trimmed to the animations VibeNotch
/// actually uses (the engine's live-activity expand/close variants collapse
/// into VibeNotch's single expanded-card case).
struct NotchAnimations {
    /// Spring for the pill silhouette resizing (idle ↔ dropdown ↔ card).
    let surfaceResize: Animation
    /// Spring the collapsed/dropdown content insertion & removal ride on.
    let openContentTransition: Animation
    /// Spring for the expanded card's content insertion.
    let expandContentTransition: Animation
    /// Spring for the expanded card's content removal (slightly slower so the
    /// card settles closed rather than snapping shut).
    let closeContentTransition: Animation
    /// Spring for the swipe-stretch release (jelly settling back to rest).
    let stretchReset: Animation

    static let `default` = preset(.balanced)

    /// Builds the animation bundle for a preset. On a floating capsule (no
    /// physical notch, `isDynamicIsland == true`) the damping is a touch lower
    /// so the motion has slightly more bounce, matching the iPhone Island feel.
    static func preset(_ preset: NotchAnimationPreset, isDynamicIsland: Bool = false) -> Self {
        let damping: Double = isDynamicIsland ? 0.75 : 0.8

        // Response is the single knob the presets vary: lower = snappier.
        let response: Double
        switch preset {
        case .snappy:   response = 0.41
        case .fast:     response = 0.44
        case .balanced: response = 0.47
        case .slow:     response = 0.50
        case .relaxed:  response = 0.53
        }

        return Self(
            surfaceResize: .spring(response: response, dampingFraction: damping),
            openContentTransition: .spring(response: response, dampingFraction: damping),
            // Expansion leads slightly; closing trails slightly — the same
            // small offsets the reference engine uses so open feels eager and
            // close feels settled.
            expandContentTransition: .spring(response: response - 0.02, dampingFraction: damping),
            closeContentTransition: .spring(response: response + 0.08, dampingFraction: damping),
            stretchReset: .spring(response: response, dampingFraction: damping)
        )
    }
}
