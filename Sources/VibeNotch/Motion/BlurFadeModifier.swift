import SwiftUI

/// The simplest content morph: blur + fade, composited as one group. Used as a
/// gentle cross-dissolve when a full notch-emergence transition would be too
/// much (e.g. content that swaps in place at a fixed size).
struct BlurFadeModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .compositingGroup()
    }
}
