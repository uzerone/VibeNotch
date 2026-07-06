import SwiftUI

/// Compensation offsets that make content appear to *emerge from the notch*
/// rather than fade in place. When a compact view scales up from the notch
/// line, its center would otherwise drift; these offsets pre-shift the
/// scaled-down endpoint so the growth reads as extruding out of the black
/// housing — the signature iOS Dynamic Island move.
///
/// Adapted from the DynamicNotch engine's transition math. The ratio (3/13)
/// and the vertical half-delta are the values Apple's Island visually matches.
enum NotchTransitionMetrics {
    /// Horizontal drift ratio applied to the notch width. Content inserted at
    /// the scaled-down endpoint starts pulled toward the notch's optical
    /// center by this fraction of the notch width, so growth spreads outward
    /// symmetrically instead of sliding sideways.
    static let horizontalCompensationRatio: CGFloat = 3.0 / 13.0

    static func horizontalCompensationOffset(for notchWidth: CGFloat) -> CGFloat {
        -(max(0, notchWidth) * horizontalCompensationRatio)
    }

    /// Vertical pre-shift: half the distance the content still has to grow
    /// downward from the notch line, so the scaled-down endpoint sits centered
    /// on the notch rather than below it.
    static func verticalCompensationOffset(for notchHeight: CGFloat, baseHeight: CGFloat) -> CGFloat {
        -(max(0, notchHeight - baseHeight) / 2)
    }
}
