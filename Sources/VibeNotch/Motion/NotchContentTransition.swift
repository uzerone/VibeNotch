import SwiftUI

/// Notch-anchored content transitions — the motion that makes a view read as
/// *emerging from the notch* instead of fading in place.
///
/// Two flavors:
/// • `notchCompact` — a small status view (the dropdown row) puffing out from
///   the notch center: scale 0.2 → 1 with a horizontal/vertical pre-shift so
///   the growth spreads symmetrically out of the black housing.
/// • `notchExpanded` — the full card unfurling downward from the notch line:
///   anchored at `.top`, wider-than-tall initial scale so it reads as a sheet
///   dropping down rather than a dot inflating.
///
/// Both blur during the transition so the morph feels like a soft material
/// change, matching Apple's Dynamic Island. Adapted from the DynamicNotch
/// engine; trimmed to the two cases VibeNotch actually presents (no
/// live-activity / compact-removal-for-expansion branch).
extension AnyTransition {
    /// Gentle blur + fade cross-dissolve, composited as one group.
    static var blurAndFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(blur: 10, opacity: 0),
            identity: BlurFadeModifier(blur: 0, opacity: 1)
        )
    }

    /// Content emerging from / retreating into the notch.
    ///
    /// - Parameters:
    ///   - notchWidth: current pill width, drives horizontal compensation.
    ///   - notchHeight: current pill height at this state.
    ///   - baseHeight: the collapsed pill height (the notch line), so the
    ///     vertical pre-shift only accounts for the *grown* portion.
    ///   - isExpandedPresentation: `true` for the big card unfurling downward,
    ///     `false` for a compact status row puffing from the notch center.
    static func notchContent(
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        baseHeight: CGFloat,
        isExpandedPresentation: Bool
    ) -> AnyTransition {
        if isExpandedPresentation {
            return notchExpanded(notchWidth: notchWidth, notchHeight: notchHeight, baseHeight: baseHeight)
        }
        return notchCompact(notchWidth: notchWidth, notchHeight: notchHeight, baseHeight: baseHeight)
    }

    private static func notchCompact(notchWidth: CGFloat, notchHeight: CGFloat, baseHeight: CGFloat) -> AnyTransition {
        let horizontalOffset = NotchTransitionMetrics.horizontalCompensationOffset(for: notchWidth)
        let verticalOffset = NotchTransitionMetrics.verticalCompensationOffset(for: notchHeight, baseHeight: baseHeight)

        let active = NotchTransitionModifier(
            blur: 20, opacity: 0,
            offsetX: horizontalOffset, offsetY: verticalOffset,
            scaleX: 0.2, scaleY: 0.2, anchor: .center
        )
        return .asymmetric(
            insertion: .modifier(active: active, identity: NotchTransitionModifier(anchor: .center)),
            removal: .modifier(active: active, identity: NotchTransitionModifier(anchor: .center))
        )
    }

    private static func notchExpanded(notchWidth: CGFloat, notchHeight: CGFloat, baseHeight: CGFloat) -> AnyTransition {
        let horizontalOffset = NotchTransitionMetrics.horizontalCompensationOffset(for: notchWidth)
        let verticalOffset = NotchTransitionMetrics.verticalCompensationOffset(for: notchHeight, baseHeight: baseHeight)

        // Anchored at the top edge (the notch line): the card scales up wider
        // than tall (0.4 × 0.2) so it unfurls downward like a dropping sheet.
        // Only a third of the vertical compensation is applied — the card's own
        // top-anchored growth carries most of the downward motion.
        let active = NotchTransitionModifier(
            blur: 20, opacity: 0,
            offsetX: horizontalOffset, offsetY: verticalOffset / 3,
            scaleX: 0.4, scaleY: 0.2, anchor: .top
        )
        return .asymmetric(
            insertion: .modifier(active: active, identity: NotchTransitionModifier(anchor: .top)),
            removal: .modifier(active: active, identity: NotchTransitionModifier(anchor: .top))
        )
    }
}
