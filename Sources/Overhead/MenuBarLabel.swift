import AppKit
import SwiftUI

/// Draws the menu bar item: a plane glyph turned to the aircraft's heading,
/// followed by short text such as "GLF6 · 4,200 ft".
///
/// The whole item is drawn as one template image. A menu bar label only
/// honors an image and plain text, so rotation, monospaced digits and the
/// fade between aircraft all have to be drawn by hand.
enum MenuBarRenderer {
    static let height: CGFloat = 18
    private static let glyphBox: CGFloat = 18

    /// A plane seen from above, nose up (north), centered on the origin.
    private static let planePath: CGPath = {
        let path = CGMutablePath()
        // Fuselage.
        path.addRoundedRect(in: CGRect(x: -1.15, y: -6.6, width: 2.3, height: 14.2), cornerWidth: 1.15, cornerHeight: 1.15)
        // Wings and tailplane, mirrored left and right.
        for side in [CGFloat(-1), 1] {
            path.move(to: CGPoint(x: side * 0.9, y: 2.4))
            path.addLine(to: CGPoint(x: side * 7.6, y: -1.7))
            path.addLine(to: CGPoint(x: side * 7.6, y: -3.3))
            path.addLine(to: CGPoint(x: side * 0.9, y: -1.2))
            path.closeSubpath()
            path.move(to: CGPoint(x: side * 0.9, y: -3.9))
            path.addLine(to: CGPoint(x: side * 3.5, y: -5.9))
            path.addLine(to: CGPoint(x: side * 3.5, y: -7.1))
            path.addLine(to: CGPoint(x: side * 0.9, y: -6.3))
            path.closeSubpath()
        }
        return path
    }()

    static func image(heading: Double, text: String, contentOpacity: Double, dim: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black.withAlphaComponent(contentOpacity),
        ]
        let label = NSAttributedString(string: text, attributes: attributes)
        let textSize = text.isEmpty ? .zero : label.size()
        let width = glyphBox + (text.isEmpty ? 0 : 4 + ceil(textSize.width) + 1)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            // Drawn as a vector path so it stays sharp at any angle.
            context.saveGState()
            context.translateBy(x: glyphBox / 2, y: height / 2)
            // Headings run clockwise from north; this space turns counter-clockwise.
            context.rotate(by: -heading * .pi / 180)
            context.addPath(planePath)
            context.setFillColor(NSColor.black.withAlphaComponent(dim ? 0.38 : max(0.38, contentOpacity)).cgColor)
            context.fillPath()
            context.restoreGState()

            if !text.isEmpty {
                let y = (height - textSize.height) / 2
                label.draw(at: NSPoint(x: glyphBox + 4, y: y))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(nsImage: MenuBarRenderer.image(
            heading: model.menuHasAircraft ? model.menuHeading : 45,
            text: model.menuHasAircraft ? model.menuText : "",
            contentOpacity: model.menuContentOpacity,
            dim: !model.menuHasAircraft
        ))
        .accessibilityLabel(model.menuHasAircraft ? "Overhead: \(model.menuText)" : "Overhead: no aircraft nearby")
    }
}
