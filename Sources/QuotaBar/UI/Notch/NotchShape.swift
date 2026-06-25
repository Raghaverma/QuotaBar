import SwiftUI

/// The shape of the notch island. The top corners use concave (inward) quadratic
/// curves that blend seamlessly into the MacBook's flat bezel — visually continuing
/// the physical hardware notch. The bottom corners use convex (outward) curves, like
/// Apple's Dynamic Island. Both radii are animatable so the shape can spring open
/// and snap closed without breaking.
struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat? = nil, bottomCornerRadius: CGFloat? = nil) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topCornerRadius, min(rect.width, rect.height) / 2)
        let b = min(bottomCornerRadius, min(rect.width, rect.height) / 2)
        var p = Path()

        // Top-left corner: concave inverse fillet — the curve bends inward so the
        // island's top edge reads as a continuation of the flat screen bezel.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + t, y: rect.minY + t),
            control: CGPoint(x: rect.minX + t, y: rect.minY)
        )

        // Left edge down to the bottom-left fillet start.
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))

        // Bottom-left corner: standard convex rounded corner.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
            control: CGPoint(x: rect.minX + t, y: rect.maxY)
        )

        // Bottom edge.
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))

        // Bottom-right corner: standard convex rounded corner.
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            control: CGPoint(x: rect.maxX - t, y: rect.maxY)
        )

        // Right edge up to the top-right fillet start.
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))

        // Top-right corner: concave inverse fillet.
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - t, y: rect.minY)
        )

        // Close along the top edge back to origin.
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return p
    }
}
