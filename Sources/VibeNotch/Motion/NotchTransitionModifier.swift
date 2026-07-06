import SwiftUI

/// A single set of transform endpoints (scale + offset + blur + opacity) that
/// a `.modifier(active:identity:)` transition interpolates between. Grouping
/// them in `.compositingGroup()` keeps the blur and opacity applied to the
/// composited result rather than each layer independently, so content morphs
/// as one object instead of dissolving piecemeal.
struct NotchTransitionModifier: ViewModifier {
    var blur: CGFloat = 0
    var opacity: Double = 1
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: scaleX, y: scaleY, anchor: anchor)
            .offset(x: offsetX, y: offsetY)
            .blur(radius: blur)
            .opacity(opacity)
            .compositingGroup()
    }
}
