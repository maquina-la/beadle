import AppKit
import SwiftUI

/// The Beadle mark: a flat-top hexagon with three hexagonal beads punched
/// through it, each bead turned 30 degrees against the outer shell.
///
/// The geometry mirrors `design/export.py`, which produces the SVG masters and
/// the app icon. Every proportion is held to the outer circumradius, so the
/// mark can be drawn at any size — 15pt in the menu bar, 1024pt in the icon —
/// without being redrawn.
enum BeadleMark {
    private static let beadRadiusRatio: CGFloat = 8.0 / 27.0
    private static let beadDistanceRatio: CGFloat = 11.0 / 27.0

    /// Beads sit on the hexagon's edge midpoints, one of them straight up.
    /// On the vertices instead, the whole mark reads as a rotated triangle.
    private static let beadAngles: [CGFloat] = [-90, 30, 150]

    /// Fraction of each edge given over to the corner. The corner curves
    /// through the true vertex, which stays crisp enough to read as a hexagon
    /// at 16px while losing the needle points that alias into grey.
    private static let shellRounding: CGFloat = 0.18
    private static let beadRounding: CGFloat = 0.22

    /// The mark, centred in `rect` and filled with the even-odd rule so the
    /// beads punch through rather than sit on top.
    static func path(in rect: CGRect) -> CGPath {
        let radius = min(rect.width / 2, rect.height / sqrt(3))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let path = CGMutablePath()
        appendHexagon(to: path, center: center, radius: radius,
                      rotation: 0, rounding: shellRounding)
        for angle in beadAngles {
            let radians = angle * .pi / 180
            let bead = CGPoint(
                x: center.x + radius * beadDistanceRatio * cos(radians),
                y: center.y + radius * beadDistanceRatio * sin(radians))
            appendHexagon(to: path, center: bead,
                          radius: radius * beadRadiusRatio,
                          rotation: -90, rounding: beadRounding)
        }
        return path
    }

    /// A template image, so the menu bar tints, inverts and highlights it the
    /// way it does every other status item.
    static func templateImage(height: CGFloat = 15) -> NSImage {
        let size = NSSize(width: (height * 2 / sqrt(3)).rounded(), height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            context.addPath(path(in: rect))
            context.setFillColor(NSColor.black.cgColor)  // template: alpha only
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func appendHexagon(to path: CGMutablePath, center: CGPoint,
                                      radius: CGFloat, rotation: CGFloat,
                                      rounding: CGFloat) {
        let corners = (0..<6).map { index -> CGPoint in
            let radians = (rotation + CGFloat(index) * 60) * .pi / 180
            return CGPoint(x: center.x + radius * cos(radians),
                           y: center.y + radius * sin(radians))
        }
        for index in corners.indices {
            let corner = corners[index]
            let previous = corners[(index + 5) % 6]
            let next = corners[(index + 1) % 6]
            let entry = CGPoint(x: corner.x + (previous.x - corner.x) * rounding,
                                y: corner.y + (previous.y - corner.y) * rounding)
            let exit = CGPoint(x: corner.x + (next.x - corner.x) * rounding,
                               y: corner.y + (next.y - corner.y) * rounding)
            if index == 0 {
                path.move(to: entry)
            } else {
                path.addLine(to: entry)
            }
            path.addQuadCurve(to: exit, control: corner)
        }
        path.closeSubpath()
    }
}

/// The mark as a SwiftUI shape, for use inside the app. Fill it with
/// `FillStyle(eoFill: true)` or the beads will not punch through.
struct BeadleMarkShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path(BeadleMark.path(in: rect))
    }
}
