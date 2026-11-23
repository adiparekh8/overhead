import OverheadCore
import SwiftUI

/// A side-view silhouette of an aircraft, nose to the right.
/// Drawn in a 200 x 64 unit box and scaled to fit.
struct AircraftSilhouette: Shape {
    let shape: AircraftShape

    static let unitSize = CGSize(width: 200, height: 64)

    /// Width on screen, in points. Bigger aircraft are drawn bigger.
    static func displayWidth(for shape: AircraftShape) -> CGFloat {
        switch shape {
        case .superJumbo: return 250
        case .jumbo: return 240
        case .quadWidebody: return 230
        case .widebody: return 220
        case .narrowbody: return 180
        case .rearEngineJet: return 165
        case .turboprop: return 150
        case .businessJet: return 135
        case .helicopter: return 115
        case .pistonSingle: return 95
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Pieces()
        switch shape {
        case .superJumbo:
            fuselage(&p, tail: 4, nose: 197, top: 17, bottom: 43)
            fin(&p, baseFront: 54, baseRear: 22, topFront: 24, topRear: 8, baseY: 19, topY: 1)
            stabilizer(&p, x: 36, y: 27, length: 26)
            wing(&p, rootFront: 124, rootRear: 86, rootY: 41, tipFront: 70, tipRear: 60, tipY: 55)
            pod(&p, x: 104, y: 44, width: 24, height: 11)
            pod(&p, x: 78, y: 49, width: 20, height: 9)
        case .jumbo:
            fuselage(&p, tail: 4, nose: 197, top: 22, bottom: 43)
            // The hump.
            p.addRoundedRect(in: CGRect(x: 126, y: 14, width: 62, height: 18), cornerSize: CGSize(width: 9, height: 9))
            fin(&p, baseFront: 50, baseRear: 20, topFront: 22, topRear: 8, baseY: 24, topY: 2)
            stabilizer(&p, x: 34, y: 30, length: 26)
            wing(&p, rootFront: 122, rootRear: 86, rootY: 41, tipFront: 70, tipRear: 60, tipY: 55)
            pod(&p, x: 103, y: 44, width: 23, height: 10)
            pod(&p, x: 78, y: 49, width: 19, height: 8.5)
        case .quadWidebody:
            fuselage(&p, tail: 4, nose: 197, top: 23, bottom: 42)
            fin(&p, baseFront: 48, baseRear: 20, topFront: 22, topRear: 8, baseY: 25, topY: 3)
            stabilizer(&p, x: 34, y: 30, length: 25)
            wing(&p, rootFront: 122, rootRear: 88, rootY: 40, tipFront: 72, tipRear: 62, tipY: 54)
            pod(&p, x: 104, y: 43, width: 20, height: 9)
            pod(&p, x: 80, y: 48, width: 17, height: 8)
        case .widebody:
            fuselage(&p, tail: 4, nose: 197, top: 23, bottom: 42)
            fin(&p, baseFront: 48, baseRear: 20, topFront: 22, topRear: 8, baseY: 25, topY: 3)
            stabilizer(&p, x: 34, y: 30, length: 25)
            wing(&p, rootFront: 122, rootRear: 88, rootY: 40, tipFront: 74, tipRear: 64, tipY: 54)
            pod(&p, x: 98, y: 42, width: 28, height: 13)
        case .narrowbody:
            fuselage(&p, tail: 6, nose: 196, top: 26, bottom: 40)
            fin(&p, baseFront: 46, baseRear: 20, topFront: 22, topRear: 9, baseY: 28, topY: 5)
            stabilizer(&p, x: 32, y: 31, length: 23)
            wing(&p, rootFront: 118, rootRear: 90, rootY: 38, tipFront: 80, tipRear: 71, tipY: 51)
            pod(&p, x: 100, y: 41, width: 21, height: 9.5)
        case .rearEngineJet:
            fuselage(&p, tail: 6, nose: 196, top: 28, bottom: 39)
            fin(&p, baseFront: 44, baseRear: 20, topFront: 20, topRear: 8, baseY: 30, topY: 8)
            // T-tail: the stabilizer sits on top of the fin.
            stabilizer(&p, x: 28, y: 8, length: 26)
            wing(&p, rootFront: 112, rootRear: 88, rootY: 37, tipFront: 80, tipRear: 72, tipY: 48)
            // Engine on the rear fuselage.
            pod(&p, x: 40, y: 22, width: 26, height: 9)
        case .businessJet:
            fuselage(&p, tail: 22, nose: 182, top: 29, bottom: 39, pointed: true)
            fin(&p, baseFront: 58, baseRear: 34, topFront: 34, topRear: 22, baseY: 31, topY: 10)
            stabilizer(&p, x: 40, y: 10, length: 24)
            wing(&p, rootFront: 112, rootRear: 90, rootY: 37, tipFront: 82, tipRear: 75, tipY: 47)
            // Winglet.
            p.addPath(polygon([CGPoint(x: 82, y: 47), CGPoint(x: 75, y: 47), CGPoint(x: 71, y: 40), CGPoint(x: 74, y: 40)]))
            pod(&p, x: 54, y: 24, width: 24, height: 8)
        case .turboprop:
            fuselage(&p, tail: 14, nose: 188, top: 28, bottom: 41)
            fin(&p, baseFront: 54, baseRear: 28, topFront: 30, topRear: 16, baseY: 30, topY: 6)
            stabilizer(&p, x: 36, y: 6, length: 26)
            // High wing with the engine nacelle slung under it.
            p.addRoundedRect(in: CGRect(x: 92, y: 23, width: 34, height: 5), cornerSize: CGSize(width: 2.5, height: 2.5))
            pod(&p, x: 98, y: 24, width: 34, height: 9)
            // Propeller disc, seen edge on.
            p.addRoundedRect(in: CGRect(x: 132, y: 14, width: 2.6, height: 29), cornerSize: CGSize(width: 1.3, height: 1.3))
            // Main gear fairing.
            pod(&p, x: 96, y: 39, width: 22, height: 6)
        case .pistonSingle:
            fuselage(&p, tail: 28, nose: 166, top: 30, bottom: 43, pointed: false, tailLength: 3.6)
            // Cabin and high wing.
            p.addRoundedRect(in: CGRect(x: 102, y: 23, width: 40, height: 12), cornerSize: CGSize(width: 5, height: 5))
            p.addRoundedRect(in: CGRect(x: 92, y: 20, width: 54, height: 5), cornerSize: CGSize(width: 2.5, height: 2.5))
            fin(&p, baseFront: 62, baseRear: 36, topFront: 42, topRear: 30, baseY: 33, topY: 12)
            stabilizer(&p, x: 50, y: 34, length: 20)
            // Propeller.
            p.addRoundedRect(in: CGRect(x: 166, y: 20, width: 2.6, height: 32), cornerSize: CGSize(width: 1.3, height: 1.3))
            // Fixed gear: two legs and wheels.
            p.addPath(polygon([CGPoint(x: 120, y: 42), CGPoint(x: 124, y: 42), CGPoint(x: 119, y: 52), CGPoint(x: 116, y: 52)]))
            p.addEllipse(in: CGRect(x: 113, y: 49, width: 8, height: 8))
            p.addPath(polygon([CGPoint(x: 152, y: 42), CGPoint(x: 155, y: 42), CGPoint(x: 156, y: 51), CGPoint(x: 153.5, y: 51)]))
            p.addEllipse(in: CGRect(x: 151.5, y: 49.5, width: 7, height: 7))
        case .helicopter:
            // Cabin.
            p.addEllipse(in: CGRect(x: 112, y: 24, width: 62, height: 28))
            // Tail boom, fin and tail rotor.
            p.addPath(polygon([CGPoint(x: 126, y: 30), CGPoint(x: 28, y: 27), CGPoint(x: 28, y: 32), CGPoint(x: 122, y: 44)]))
            p.addPath(polygon([CGPoint(x: 36, y: 31), CGPoint(x: 24, y: 12), CGPoint(x: 18, y: 12), CGPoint(x: 26, y: 31)]))
            p.addRoundedRect(in: CGRect(x: 19.5, y: 6, width: 2.4, height: 26), cornerSize: CGSize(width: 1.2, height: 1.2))
            // Mast and main rotor.
            p.addRect(CGRect(x: 141, y: 15, width: 4, height: 11))
            p.addRoundedRect(in: CGRect(x: 78, y: 13, width: 121, height: 2.6), cornerSize: CGSize(width: 1.3, height: 1.3))
            // Skids.
            p.addRect(CGRect(x: 126, y: 50, width: 2.4, height: 8))
            p.addRect(CGRect(x: 158, y: 50, width: 2.4, height: 8))
            p.addRoundedRect(in: CGRect(x: 114, y: 57, width: 62, height: 2.6), cornerSize: CGSize(width: 1.3, height: 1.3))
        }

        // Union the pieces: overlapping parts drawn in opposite directions
        // would otherwise cut holes in each other.
        let merged = p.paths.reduce(Path()) { $0.union($1) }
        let unit = Self.unitSize
        let scale = min(rect.width / unit.width, rect.height / unit.height)
        let offsetX = rect.minX + (rect.width - unit.width * scale) / 2
        let offsetY = rect.minY + (rect.height - unit.height * scale) / 2
        return merged.applying(CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale))
    }

    // MARK: Pieces (unit coordinates, y down, nose right)

    /// Collects sub-shapes with the same calls a Path offers.
    struct Pieces {
        var paths: [Path] = []
        mutating func addPath(_ path: Path) { paths.append(path) }
        mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize) {
            paths.append(Path(roundedRect: rect, cornerSize: cornerSize))
        }
        mutating func addEllipse(in rect: CGRect) { paths.append(Path(ellipseIn: rect)) }
        mutating func addRect(_ rect: CGRect) { paths.append(Path(rect)) }
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    private func fuselage(
        _ p: inout Pieces, tail: CGFloat, nose: CGFloat, top: CGFloat, bottom: CGFloat,
        pointed: Bool = false, tailLength: CGFloat = 2.6
    ) {
        let height = bottom - top
        let noseY = top + height * (pointed ? 0.62 : 0.6)
        let noseLength = height * (pointed ? 1.7 : 1.15)
        var body = Path()
        body.move(to: CGPoint(x: nose, y: noseY))
        body.addQuadCurve(
            to: CGPoint(x: nose - noseLength, y: top),
            control: CGPoint(x: nose - noseLength * (pointed ? 0.45 : 0.22), y: top + (pointed ? 1.5 : 0.5))
        )
        body.addLine(to: CGPoint(x: tail + height * 1.4, y: top))
        body.addLine(to: CGPoint(x: tail, y: top + height * 0.22))
        body.addLine(to: CGPoint(x: tail, y: top + height * 0.42))
        body.addLine(to: CGPoint(x: tail + height * tailLength, y: bottom))
        body.addLine(to: CGPoint(x: nose - noseLength * 0.8, y: bottom))
        body.addQuadCurve(to: CGPoint(x: nose, y: noseY), control: CGPoint(x: nose - noseLength * 0.12, y: bottom))
        body.closeSubpath()
        p.addPath(body)
    }

    private func fin(
        _ p: inout Pieces, baseFront: CGFloat, baseRear: CGFloat, topFront: CGFloat, topRear: CGFloat,
        baseY: CGFloat, topY: CGFloat
    ) {
        p.addPath(polygon([
            CGPoint(x: baseFront, y: baseY), CGPoint(x: topFront, y: topY),
            CGPoint(x: topRear, y: topY), CGPoint(x: baseRear, y: baseY),
        ]))
    }

    /// The near half of the tailplane, swept back.
    private func stabilizer(_ p: inout Pieces, x: CGFloat, y: CGFloat, length: CGFloat) {
        p.addPath(polygon([
            CGPoint(x: x, y: y), CGPoint(x: x - length * 0.75, y: y + 3.2),
            CGPoint(x: x - length, y: y + 3.2), CGPoint(x: x - length * 0.55, y: y),
        ]))
    }

    /// The near wing, swept back and drooping toward the viewer.
    private func wing(
        _ p: inout Pieces, rootFront: CGFloat, rootRear: CGFloat, rootY: CGFloat,
        tipFront: CGFloat, tipRear: CGFloat, tipY: CGFloat
    ) {
        p.addPath(polygon([
            CGPoint(x: rootFront, y: rootY), CGPoint(x: tipFront, y: tipY),
            CGPoint(x: tipRear, y: tipY), CGPoint(x: rootRear, y: rootY),
        ]))
    }

    private func pod(_ p: inout Pieces, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        p.addRoundedRect(
            in: CGRect(x: x, y: y, width: width, height: height),
            cornerSize: CGSize(width: height / 2, height: height / 2)
        )
    }
}
