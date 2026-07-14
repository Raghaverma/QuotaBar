import SwiftUI

/// The silhouette of the island. The **top** corners curve *inward* (concave fillets) so
/// the island's shoulders melt into the flat black bezel above them — reading as a
/// continuation of the hardware notch rather than a rectangle stuck on top of it. The
/// **bottom** corners curve *outward* (convex), like Apple's Dynamic Island, so the panel
/// that drops down feels like the same physical object stretching.
///
/// Both radii are `animatableData`, so the shape can spring open and settle closed
/// without the path snapping between states.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = max(0, min(topCornerRadius, min(rect.width, rect.height) / 2))
        let b = max(0, min(bottomCornerRadius, min(rect.width, rect.height) / 2))
        var p = Path()

        // Start at the top-left, flush with the bezel.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left: concave inverse fillet bending inward + down.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + t, y: rect.minY + t),
            control: CGPoint(x: rect.minX + t, y: rect.minY)
        )

        // Left edge down to where the bottom fillet begins.
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))

        // Bottom-left: convex rounded corner.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
            control: CGPoint(x: rect.minX + t, y: rect.maxY)
        )

        // Bottom edge.
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))

        // Bottom-right: convex rounded corner.
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            control: CGPoint(x: rect.maxX - t, y: rect.maxY)
        )

        // Right edge back up to the top fillet.
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))

        // Top-right: concave inverse fillet.
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - t, y: rect.minY)
        )

        p.closeSubpath()
        return p
    }
}
