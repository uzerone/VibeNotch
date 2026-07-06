import SwiftUI

/// The island silhouette that meets the menu bar / notch with an *inward-
/// flaring* throat instead of a hard corner — the signature Dynamic Island
/// shape. Adapted from the DynamicNotch engine's `NotchShape`.
///
/// Geometry (docked / top-anchored):
/// • The top two corners curve **inward** from the top edge: from the outer
///   top corner, a quadratic curve pulls down and toward the center by
///   `topFlareRadius`, so the surface is narrower at the very top and widens
///   as it drops — reading as growth out of the menu-bar line with a smooth
///   concave throat rather than a right angle.
/// • The bottom two corners are ordinary convex rounded corners of
///   `bottomCornerRadius`.
///
/// When `fullyRounded` is true (free-move, detached from any edge) the shape
/// degrades to a plain rounded rectangle using `bottomCornerRadius` on all
/// four corners.
///
/// `InsettableShape` conformance lets it back `.strokeBorder` (the panel's
/// hairline edge) as well as `.fill` / `.mask` / `.contentShape`.
struct MorphNotchShape: InsettableShape {
    /// How far the top corners flare inward. 0 → a flat top edge (the collapsed
    /// pill docked under a physical notch stays flat to merge with the housing).
    var topFlareRadius: CGFloat
    /// Convex radius of the bottom corners (and of all corners when
    /// `fullyRounded`).
    var bottomCornerRadius: CGFloat
    /// When true, ignore the flare and draw a plain rounded rect (free-move).
    var fullyRounded: Bool

    /// Inset applied by `.strokeBorder` / `.inset(by:)`.
    private var inset: CGFloat = 0

    init(topFlareRadius: CGFloat, bottomCornerRadius: CGFloat, fullyRounded: Bool) {
        self.topFlareRadius = topFlareRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.fullyRounded = fullyRounded
    }

    /// Animate the two radii together so the throat/corners morph smoothly with
    /// the rest of the island. `fullyRounded`/`inset` don't animate (they flip
    /// with placement / stroke, not per-frame).
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFlareRadius, bottomCornerRadius) }
        set {
            topFlareRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)

        // Free-move: detached from any edge → a plain rounded rectangle (all
        // four corners convex). The docked path below handles both the flat-top
        // collapsed pill (top == 0) and the flared expanded card (top > 0).
        if fullyRounded {
            return Path(roundedRect: r, cornerRadius: bottomCornerRadius, style: .continuous)
        }

        // Clamp so the two flares plus a bottom corner never exceed the width,
        // and the corners never exceed the height — avoids self-crossing paths
        // at tiny sizes mid-morph.
        let top = max(0, min(topFlareRadius, r.width / 2, r.height))
        let bottom = max(0, min(bottomCornerRadius, (r.width - 2 * top) / 2, r.height - top))

        var path = Path()

        // Start at the outer top-left, flare inward and down.
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addQuadCurve(
            to: CGPoint(x: r.minX + top, y: r.minY + top),
            control: CGPoint(x: r.minX + top, y: r.minY)
        )

        // Left edge down to the bottom-left corner.
        path.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: r.minX + top + bottom, y: r.maxY),
            control: CGPoint(x: r.minX + top, y: r.maxY)
        )

        // Bottom edge to the bottom-right corner.
        path.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        path.addQuadCurve(
            to: CGPoint(x: r.maxX - top, y: r.maxY - bottom),
            control: CGPoint(x: r.maxX - top, y: r.maxY)
        )

        // Right edge up, then flare outward to the top-right.
        path.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: r.maxX, y: r.minY),
            control: CGPoint(x: r.maxX - top, y: r.minY)
        )

        // Close the top edge.
        path.closeSubpath()
        return path
    }
}
