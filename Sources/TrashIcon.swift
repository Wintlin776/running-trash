import AppKit

/// Draws a flat, always-colored trash can with its lid flipped open, mid-"toss"
/// — a crumpled paper dropping in (empty) or overflowing (full). No drop shadow,
/// so it stays crisp on any desktop wallpaper.
enum TrashIcon {

    // Palette (sRGB).
    private static let bodyTop = NSColor(srgbRed: 0.80, green: 0.84, blue: 0.88, alpha: 1)
    private static let bodyBottom = NSColor(srgbRed: 0.60, green: 0.66, blue: 0.72, alpha: 1)
    private static let outline = NSColor(srgbRed: 0.30, green: 0.35, blue: 0.42, alpha: 1)
    private static let rimFill = NSColor(srgbRed: 0.72, green: 0.77, blue: 0.82, alpha: 1)
    private static let lidFill = NSColor(srgbRed: 0.84, green: 0.88, blue: 0.92, alpha: 1)
    private static let paper = NSColor(srgbRed: 0.97, green: 0.96, blue: 0.92, alpha: 1)
    private static let paperLine = NSColor(srgbRed: 0.72, green: 0.71, blue: 0.65, alpha: 1)

    /// A proper macOS app icon: the can on a teal rounded-square background.
    static func makeAppIcon(size: CGFloat) -> NSImage {
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            let rect = NSRect(x: 0, y: 0, width: size, height: size)

            // Big Sur-style squircle background with a soft gradient.
            let radius = size * 0.2237
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            let top = NSColor(srgbRed: 0.47, green: 0.76, blue: 0.82, alpha: 1)
            let bottom = NSColor(srgbRed: 0.19, green: 0.49, blue: 0.61, alpha: 1)
            NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: -90)

            // Drop the can into the middle with padding.
            let pad = size * 0.17
            let inner = size - pad * 2
            ctx.translateBy(x: pad, y: pad)
            ctx.scaleBy(x: inner / 80, y: inner / 80)
            drawCan(full: false)
            return true
        }
    }

    static func make(full: Bool, size: CGFloat) -> NSImage {
        // Draw in an 80pt design space, scaled to the requested size.
        let s = size / 80.0
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.scaleBy(x: s, y: s)
            drawCan(full: full)
            return true
        }
    }

    // MARK: - Pieces (80x80 design space, origin bottom-left)

    private static func drawCan(full: Bool) {
        let line: CGFloat = 2
        // Shift everything down a touch so the open lid never clips the top edge.
        NSGraphicsContext.current!.cgContext.translateBy(x: 0, y: -4)

        // --- Can body: a rounded trapezoid with a vertical sheen. ---
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 22, y: 52))
        body.line(to: NSPoint(x: 58, y: 52))
        body.line(to: NSPoint(x: 53, y: 14))
        body.curve(to: NSPoint(x: 48, y: 9),
                   controlPoint1: NSPoint(x: 52.5, y: 11),
                   controlPoint2: NSPoint(x: 51, y: 9))
        body.line(to: NSPoint(x: 32, y: 9))
        body.curve(to: NSPoint(x: 27, y: 14),
                   controlPoint1: NSPoint(x: 29, y: 9),
                   controlPoint2: NSPoint(x: 27.5, y: 11))
        body.close()

        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        NSGradient(starting: bodyTop, ending: bodyBottom)?.draw(in: body.bounds, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Vertical ridges.
        paperLine.withAlphaComponent(0.35).setStroke()
        for x in [34.0, 40.0, 46.0] {
            let r = NSBezierPath()
            r.move(to: NSPoint(x: x, y: 17))
            r.line(to: NSPoint(x: x, y: 48))
            r.lineWidth = 1.5
            r.stroke()
        }

        outline.setStroke()
        body.lineWidth = line
        body.lineJoinStyle = .round
        body.stroke()

        // --- Rim / lip across the top. ---
        let rim = NSBezierPath(roundedRect: NSRect(x: 17, y: 50, width: 46, height: 9),
                               xRadius: 4.5, yRadius: 4.5)
        rimFill.setFill()
        rim.fill()
        outline.setStroke()
        rim.lineWidth = line
        rim.stroke()

        if full {
            // Trash overflowing above the rim.
            drawPaperBall(center: NSPoint(x: 30, y: 60), radius: 8)
            drawPaperBall(center: NSPoint(x: 50, y: 60), radius: 7)
            drawPaperBall(center: NSPoint(x: 40, y: 66), radius: 9)
        } else {
            // One crumpled ball dropping in from the upper right.
            drawPaperBall(center: NSPoint(x: 52, y: 70), radius: 7)
        }

        // --- Open lid, hinged up on the left. ---
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: 19, y: 57)        // hinge point
        ctx.rotate(by: 31 * .pi / 180)        // flipped open
        let lid = NSBezierPath(roundedRect: NSRect(x: -2, y: -4.5, width: 43, height: 9),
                               xRadius: 4.5, yRadius: 4.5)
        lidFill.setFill()
        lid.fill()
        outline.setStroke()
        lid.lineWidth = line
        lid.stroke()
        // Knob on the lid.
        let knob = NSBezierPath(ovalIn: NSRect(x: 36, y: -3, width: 6, height: 6))
        rimFill.setFill()
        knob.fill()
        knob.lineWidth = 1.5
        knob.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawPaperBall(center: NSPoint, radius r: CGFloat) {
        let ball = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        paper.setFill()
        ball.fill()
        outline.withAlphaComponent(0.55).setStroke()
        ball.lineWidth = 1.5
        ball.stroke()

        // A couple of crinkle creases.
        paperLine.setStroke()
        let c1 = NSBezierPath()
        c1.move(to: NSPoint(x: center.x - r * 0.4, y: center.y + r * 0.2))
        c1.line(to: NSPoint(x: center.x + r * 0.2, y: center.y - r * 0.3))
        c1.lineWidth = 1
        c1.stroke()
        let c2 = NSBezierPath()
        c2.move(to: NSPoint(x: center.x - r * 0.1, y: center.y + r * 0.4))
        c2.line(to: NSPoint(x: center.x + r * 0.4, y: center.y + r * 0.1))
        c2.lineWidth = 1
        c2.stroke()
    }
}
