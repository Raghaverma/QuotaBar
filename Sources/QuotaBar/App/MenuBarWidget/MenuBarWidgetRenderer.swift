import AppKit
import QuotaBarPresentation

/// Draws Stats-style menu-bar widgets (percent / bar / sparkline / ring) for a set
/// of entries into a single `NSImage` sized to fit. Colors are resolved for the
/// current menu-bar appearance so gauges stay legible on light and dark bars.
enum MenuBarWidgetRenderer {
    private static let height: CGFloat = 18
    private static let glyphWidth: CGFloat = 22
    private static let ringDiameter: CGFloat = 14
    private static let interItemGap: CGFloat = 10
    private static let glyphValueGap: CGFloat = 3

    /// Render every entry side by side. Returns nil if there's nothing to draw.
    static func image(
        entries: [StatusBarDisplayEntry],
        style: MenuBarWidgetStyle,
        history: [String: [Double]],
        appearanceDark: Bool
    ) -> NSImage? {
        guard !entries.isEmpty else { return nil }

        // Measure first so we can allocate the exact width.
        let segments = entries.map { segmentWidth(for: $0, style: style) }
        let totalWidth = segments.reduce(0, +) + interItemGap * CGFloat(entries.count - 1)
        let size = NSSize(width: max(totalWidth, glyphWidth), height: height)

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        var x: CGFloat = 0
        for (index, entry) in entries.enumerated() {
            drawSegment(
                entry: entry, style: style,
                history: history[entry.providerID] ?? [],
                appearanceDark: appearanceDark,
                originX: x
            )
            x += segments[index] + interItemGap
        }
        return image
    }

    // MARK: Measurement

    private static func segmentWidth(for entry: StatusBarDisplayEntry, style: MenuBarWidgetStyle) -> CGFloat {
        switch style {
        case .percent:
            return textWidth("\(entry.name) \(entry.percentText)")
        case .bar:
            return glyphWidth + glyphValueGap + textWidth(entry.percentText)
        case .sparkline:
            return 30 + glyphValueGap + textWidth(entry.percentText)
        case .ring:
            return ringDiameter + glyphValueGap + textWidth(entry.percentText)
        }
    }

    private static func textWidth(_ s: String) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    private static var font: NSFont { .menuBarFont(ofSize: 12) }

    // MARK: Drawing

    private static func drawSegment(
        entry: StatusBarDisplayEntry,
        style: MenuBarWidgetStyle,
        history: [Double],
        appearanceDark: Bool,
        originX: CGFloat
    ) {
        let fg = appearanceDark ? NSColor.white : NSColor.black
        let accent = color(forPercent: entry.remainingPercent, healthy: entry.isHealthy)

        switch style {
        case .percent:
            drawText("\(entry.name) \(entry.percentText)", at: originX, color: fg)

        case .bar:
            drawBar(percent: entry.remainingPercent, at: originX, color: accent, track: fg.withAlphaComponent(0.25))
            drawText(entry.percentText, at: originX + glyphWidth + glyphValueGap, color: fg)

        case .sparkline:
            drawSparkline(history: Array(history.suffix(30)), current: entry.remainingPercent, at: originX, width: 30, color: accent)
            drawText(entry.percentText, at: originX + 30 + glyphValueGap, color: fg)

        case .ring:
            drawRing(percent: entry.remainingPercent, at: originX, color: accent, track: fg.withAlphaComponent(0.25))
            drawText(entry.percentText, at: originX + ringDiameter + glyphValueGap, color: fg)
        }
    }

    private static func drawText(_ s: String, at x: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = (s as NSString).size(withAttributes: attrs)
        let y = (height - textSize.height) / 2
        (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    private static func drawBar(percent: Double?, at x: CGFloat, color: NSColor, track: NSColor) {
        let barWidth: CGFloat = 5
        let barHeight: CGFloat = 13
        let inset = (glyphWidth - barWidth) / 2
        let rect = NSRect(x: x + inset, y: (height - barHeight) / 2, width: barWidth, height: barHeight)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        track.setFill(); path.fill()
        let pct = CGFloat((percent ?? 0) / 100)
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * pct)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
        color.setFill(); fillPath.fill()
    }

    private static func drawRing(percent: Double?, at x: CGFloat, color: NSColor, track: NSColor) {
        let line: CGFloat = 2.5
        let rect = NSRect(x: x + 1, y: (height - ringDiameter) / 2, width: ringDiameter, height: ringDiameter)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = (ringDiameter - line) / 2

        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        trackPath.lineWidth = line
        track.setStroke(); trackPath.stroke()

        let pct = (percent ?? 0) / 100
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * pct, clockwise: true)
        arc.lineWidth = line
        arc.lineCapStyle = .round
        color.setStroke(); arc.stroke()
    }

    private static func drawSparkline(history: [Double], current: Double?, at x: CGFloat, width: CGFloat, color: NSColor) {
        var points = history
        if let current { points.append(current) }
        guard points.count >= 2 else {
            // Not enough history yet — draw a flat baseline at the current level.
            let y = height * CGFloat((current ?? 0) / 100)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: y)); line.line(to: NSPoint(x: x + width, y: y))
            line.lineWidth = 1.5
            color.withAlphaComponent(0.6).setStroke(); line.stroke()
            return
        }
        let vPad: CGFloat = 2
        let usableH = height - vPad * 2
        let stepX = width / CGFloat(points.count - 1)

        var cgPoints: [CGPoint] = []
        for (i, value) in points.enumerated() {
            let px = x + stepX * CGFloat(i)
            let py = vPad + usableH * CGFloat(min(max(value, 0), 100) / 100)
            cgPoints.append(CGPoint(x: px, y: py))
        }

        let path = NSBezierPath()
        path.move(to: cgPoints[0])

        for i in 0..<(cgPoints.count - 1) {
            let p0 = cgPoints[i]
            let p1 = cgPoints[i + 1]
            // Cubic bezier control points: horizontal tangents for a smooth curve
            let cp1 = CGPoint(x: p0.x + stepX / 3.0, y: p0.y)
            let cp2 = CGPoint(x: p1.x - stepX / 3.0, y: p1.y)
            path.curve(to: p1, controlPoint1: cp1, controlPoint2: cp2)
        }

        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        color.setStroke(); path.stroke()
    }

    /// Premium Green (mint) → Warm Amber → Coral Red (low/unhealthy).
    static func color(forPercent percent: Double?, healthy: Bool) -> NSColor {
        guard healthy, let pct = percent else {
            return NSColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1.0) // Neutral Gray
        }
        switch pct {
        case ..<20:
            return NSColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0)  // Coral Red
        case ..<50:
            return NSColor(red: 1.0, green: 0.63, blue: 0.0, alpha: 1.0)   // Warm Amber
        default:
            return NSColor(red: 0.0, green: 0.90, blue: 0.46, alpha: 1.0)  // Mint Green
        }
    }
}
