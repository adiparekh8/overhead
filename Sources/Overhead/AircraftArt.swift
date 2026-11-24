import OverheadCore
import SwiftUI

/// The geometry of one aircraft shape, side-on with the nose to the right,
/// in a 200 x 64 unit box. Parts carry a role so they can be painted in an
/// airline's colors.
struct AircraftArt {
    enum Role {
        case fuselage, tail, stabilizer, wing, engine, glass, detail
    }

    static let unitSize = CGSize(width: 200, height: 64)

    /// In drawing order, back to front.
    var parts: [(role: Role, path: Path)] = []
    /// The straight part of the fuselage: where the stripe, windows and
    /// lettering go.
    var cabin = CGRect.zero
    /// A row of passenger windows.
    var windows = false
    /// An airliner-style cockpit windscreen at the nose.
    var windscreen = true
    /// A stripe along the fuselage in the accent color.
    var stripe = true
    /// Outline of a cargo door.
    var door: CGRect?
    /// Navigation light positions.
    var wingtip = CGPoint.zero
    var farWingtip: CGPoint?
    var tailLight = CGPoint.zero
    var beaconTop = CGPoint.zero
    var beaconBottom = CGPoint.zero
    /// Where a banner's tow line attaches.
    var towPoint = CGPoint.zero
    /// Where lettering goes.
    var labelRect = CGRect.zero

    private static var cache: [AircraftShape: AircraftArt] = [:]

    static func art(for shape: AircraftShape) -> AircraftArt {
        if let cached = cache[shape] { return cached }
        let made = build(shape)
        cache[shape] = made
        return made
    }

    // MARK: Building blocks

    private mutating func add(_ role: Role, _ path: Path) {
        parts.append((role, path))
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    private static func pill(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
        let radius = min(width, height) / 2
        return Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerSize: CGSize(width: radius, height: radius))
    }

    /// A tube with a rounded or pointed nose and an upswept tail cone.
    private static func tube(
        tail: CGFloat, nose: CGFloat, top: CGFloat, bottom: CGFloat,
        pointed: Bool = false, tailLength: CGFloat = 2.6
    ) -> Path {
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
        return body
    }

    /// Adds the fuselage and records the cabin area and the light positions
    /// that follow from it.
    private mutating func fuselage(
        tail: CGFloat, nose: CGFloat, top: CGFloat, bottom: CGFloat,
        pointed: Bool = false, tailLength: CGFloat = 2.6
    ) {
        add(.fuselage, Self.tube(tail: tail, nose: nose, top: top, bottom: bottom, pointed: pointed, tailLength: tailLength))
        let height = bottom - top
        let noseLength = height * (pointed ? 1.7 : 1.15)
        cabin = CGRect(
            x: tail + height * tailLength, y: top,
            width: nose - noseLength - (tail + height * tailLength), height: height
        )
        tailLight = CGPoint(x: tail, y: top + height * 0.32)
        towPoint = CGPoint(x: tail, y: top + height * 0.32)
        beaconTop = CGPoint(x: cabin.midX + 6, y: top - 0.6)
        beaconBottom = CGPoint(x: cabin.midX - 4, y: bottom + 0.6)
        labelRect = CGRect(x: cabin.minX + 2, y: top + height * 0.2, width: cabin.width - 4, height: height * 0.5)
    }

    private mutating func fin(_ baseFront: CGFloat, _ baseRear: CGFloat, _ topFront: CGFloat, _ topRear: CGFloat, baseY: CGFloat, topY: CGFloat) {
        add(.tail, Self.polygon([(baseFront, baseY), (topFront, topY), (topRear, topY), (baseRear, baseY)]))
    }

    /// The near half of the tailplane, swept back.
    private mutating func stabilizer(x: CGFloat, y: CGFloat, length: CGFloat) {
        add(.stabilizer, Self.polygon([
            (x, y), (x - length * 0.75, y + 3.2), (x - length, y + 3.2), (x - length * 0.55, y),
        ]))
    }

    /// The near wing: swept back and coming toward the viewer.
    private mutating func wing(_ rootFront: CGFloat, _ rootRear: CGFloat, rootY: CGFloat, _ tipFront: CGFloat, _ tipRear: CGFloat, tipY: CGFloat) {
        add(.wing, Self.polygon([(rootFront, rootY), (tipFront, tipY), (tipRear, tipY), (rootRear, rootY)]))
        wingtip = CGPoint(x: (tipFront + tipRear) / 2, y: tipY)
        // The far wingtip shows just above the fuselage, further back.
        farWingtip = CGPoint(x: tipRear + 4, y: cabin.minY - 2.5)
    }

    private mutating func pod(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        add(.engine, Self.pill(x, y, width, height))
        // The intake lip.
        add(.detail, Path(roundedRect: CGRect(x: x + width - 1.6, y: y + 0.8, width: 1.3, height: height - 1.6), cornerSize: CGSize(width: 0.6, height: 0.6)))
    }

    /// A propeller disc seen edge on.
    private mutating func propeller(x: CGFloat, centerY: CGFloat, diameter: CGFloat) {
        add(.detail, Self.pill(x, centerY - diameter / 2, 2.4, diameter))
        add(.detail, Self.pill(x - 1.2, centerY - 2.2, 5, 4.4))
    }

    // MARK: Shapes

    private static func build(_ shape: AircraftShape) -> AircraftArt {
        var a = AircraftArt()
        switch shape {
        case .superJumbo:
            a.fuselage(tail: 4, nose: 197, top: 17, bottom: 43)
            a.fin(54, 22, 24, 8, baseY: 19, topY: 1)
            a.stabilizer(x: 36, y: 28, length: 26)
            a.wing(124, 86, rootY: 41, 70, 60, tipY: 55)
            a.pod(104, 44, 24, 11)
            a.pod(78, 49, 20, 9)
            a.windows = true

        case .jumbo:
            a.fuselage(tail: 4, nose: 197, top: 22, bottom: 43)
            // The hump, merged into the fuselage.
            let hump = Path(roundedRect: CGRect(x: 126, y: 14, width: 62, height: 18), cornerSize: CGSize(width: 9, height: 9))
            a.parts[0].path = a.parts[0].path.union(hump)
            a.fin(50, 20, 22, 8, baseY: 24, topY: 2)
            a.stabilizer(x: 34, y: 30, length: 26)
            a.wing(122, 86, rootY: 41, 70, 60, tipY: 55)
            a.pod(103, 44, 23, 10)
            a.pod(78, 49, 19, 8.5)
            a.windows = true

        case .quadWidebody:
            a.fuselage(tail: 4, nose: 197, top: 23, bottom: 42)
            a.fin(48, 20, 22, 8, baseY: 25, topY: 3)
            a.stabilizer(x: 34, y: 30, length: 25)
            a.wing(122, 88, rootY: 40, 72, 62, tipY: 54)
            a.pod(104, 43, 20, 9)
            a.pod(80, 48, 17, 8)
            a.windows = true

        case .widebody, .cargoWidebody:
            a.fuselage(tail: 4, nose: 197, top: 23, bottom: 42)
            a.fin(48, 20, 22, 8, baseY: 25, topY: 3)
            a.stabilizer(x: 34, y: 30, length: 25)
            a.wing(122, 88, rootY: 40, 74, 64, tipY: 54)
            a.pod(98, 42, 28, 13)
            if shape == .cargoWidebody {
                a.door = CGRect(x: 138, y: 26, width: 22, height: 11)
                // Lettering goes behind the door, over the wing.
                a.labelRect = CGRect(x: 46, y: 26.5, width: 86, height: 9)
            } else {
                a.windows = true
            }

        case .narrowbody:
            a.fuselage(tail: 6, nose: 196, top: 26, bottom: 40)
            a.fin(46, 20, 22, 9, baseY: 28, topY: 5)
            a.stabilizer(x: 32, y: 31, length: 23)
            a.wing(118, 90, rootY: 38, 80, 71, tipY: 51)
            a.pod(100, 41, 21, 9.5)
            a.windows = true

        case .rearEngineJet:
            a.fuselage(tail: 6, nose: 196, top: 28, bottom: 39)
            a.fin(44, 20, 20, 8, baseY: 30, topY: 8)
            // T-tail: the stabilizer sits on top of the fin.
            a.stabilizer(x: 28, y: 8, length: 26)
            a.wing(112, 88, rootY: 37, 80, 72, tipY: 48)
            // Engine on the rear fuselage.
            a.pod(40, 22, 26, 9)
            a.windows = true

        case .largeBusinessJet:
            a.fuselage(tail: 22, nose: 182, top: 29, bottom: 39, pointed: true)
            a.fin(58, 34, 34, 22, baseY: 31, topY: 10)
            a.stabilizer(x: 40, y: 10, length: 24)
            a.wing(112, 90, rootY: 37, 82, 75, tipY: 47)
            // Winglet.
            a.add(.wing, polygon([(82, 47), (75, 47), (71, 40), (74, 40)]))
            a.pod(54, 24, 24, 8)
            a.windows = true

        case .smallBusinessJet:
            a.fuselage(tail: 40, nose: 166, top: 30, bottom: 40, pointed: true)
            a.fin(74, 52, 54, 42, baseY: 32, topY: 13)
            a.stabilizer(x: 58, y: 13, length: 22)
            // A straighter wing than the big jets.
            a.wing(112, 96, rootY: 38, 96, 90, tipY: 46)
            a.pod(66, 25, 20, 7.5)
            a.windows = true

        case .turboprop:
            a.fuselage(tail: 14, nose: 188, top: 28, bottom: 41)
            a.fin(54, 28, 30, 16, baseY: 30, topY: 6)
            a.stabilizer(x: 36, y: 6, length: 26)
            // High wing with the engine nacelle slung under it.
            a.add(.wing, Path(roundedRect: CGRect(x: 92, y: 23, width: 34, height: 5), cornerSize: CGSize(width: 2.5, height: 2.5)))
            a.add(.engine, pill(98, 24, 34, 9))
            a.propeller(x: 132, centerY: 28.5, diameter: 29)
            // Main gear fairing.
            a.add(.fuselage, pill(96, 39, 22, 6))
            a.wingtip = CGPoint(x: 96, y: 25.5)
            a.farWingtip = CGPoint(x: 122, y: 23)
            a.windows = true
            // Behind the wing, where the nacelle does not cover it.
            a.labelRect = CGRect(x: 50, y: 30.5, width: 44, height: 6)

        case .pistonSingle:
            a.fuselage(tail: 28, nose: 166, top: 30, bottom: 43, tailLength: 3.6)
            // Cabin, then the high wing above it.
            a.add(.fuselage, Path(roundedRect: CGRect(x: 102, y: 23, width: 40, height: 12), cornerSize: CGSize(width: 5, height: 5)))
            a.add(.glass, Path(roundedRect: CGRect(x: 107, y: 25.5, width: 31, height: 6.5), cornerSize: CGSize(width: 2.5, height: 2.5)))
            a.add(.wing, pill(92, 20, 54, 5))
            a.fin(62, 36, 42, 30, baseY: 33, topY: 12)
            a.stabilizer(x: 50, y: 34, length: 20)
            a.propeller(x: 166, centerY: 36, diameter: 32)
            // Fixed gear: two legs and wheels.
            a.add(.detail, polygon([(120, 42), (124, 42), (119, 52), (116, 52)]))
            a.add(.detail, Path(ellipseIn: CGRect(x: 113, y: 49, width: 8, height: 8)))
            a.add(.detail, polygon([(152, 42), (155, 42), (156, 51), (153.5, 51)]))
            a.add(.detail, Path(ellipseIn: CGRect(x: 151.5, y: 49.5, width: 7, height: 7)))
            a.windscreen = false
            a.wingtip = CGPoint(x: 96, y: 22.5)
            a.farWingtip = CGPoint(x: 142, y: 20)
            a.labelRect = CGRect(x: 58, y: 34.5, width: 60, height: 6)

        case .pistonTwin:
            a.fuselage(tail: 26, nose: 172, top: 30, bottom: 42, pointed: true, tailLength: 3.4)
            a.add(.fuselage, Path(roundedRect: CGRect(x: 100, y: 24, width: 40, height: 12), cornerSize: CGSize(width: 6, height: 6)))
            a.add(.glass, Path(roundedRect: CGRect(x: 105, y: 26.5, width: 31, height: 6), cornerSize: CGSize(width: 2.5, height: 2.5)))
            a.fin(60, 34, 40, 28, baseY: 33, topY: 12)
            a.stabilizer(x: 48, y: 33, length: 20)
            // Low wing with an engine on it, ahead of the cabin.
            a.add(.wing, pill(96, 39.5, 46, 4.5))
            a.add(.engine, pill(110, 33.5, 32, 8.5))
            a.propeller(x: 142, centerY: 37.7, diameter: 27)
            a.windscreen = false
            a.wingtip = CGPoint(x: 99, y: 41.7)
            a.farWingtip = CGPoint(x: 138, y: 39)
            a.labelRect = CGRect(x: 56, y: 34.5, width: 50, height: 5.5)

        case .helicopter:
            // Tail boom first, then the cabin over it.
            a.add(.fuselage, polygon([(126, 30), (28, 27), (28, 32), (122, 44)]))
            a.add(.fuselage, Path(ellipseIn: CGRect(x: 112, y: 24, width: 62, height: 28)))
            a.add(.glass, Path(ellipseIn: CGRect(x: 147, y: 27, width: 24, height: 17)))
            a.add(.tail, polygon([(36, 31), (24, 12), (18, 12), (26, 31)]))
            a.add(.detail, pill(19.5, 6, 2.4, 26))
            // Mast and main rotor.
            a.add(.detail, Path(CGRect(x: 141, y: 15, width: 4, height: 11)))
            a.add(.detail, pill(78, 13, 121, 2.6))
            // Skids.
            a.add(.detail, Path(CGRect(x: 126, y: 50, width: 2.4, height: 8)))
            a.add(.detail, Path(CGRect(x: 158, y: 50, width: 2.4, height: 8)))
            a.add(.detail, pill(114, 57, 62, 2.6))
            a.cabin = CGRect(x: 118, y: 26, width: 30, height: 24)
            a.windscreen = false
            a.stripe = false
            a.wingtip = CGPoint(x: 134, y: 46)
            a.farWingtip = nil
            a.tailLight = CGPoint(x: 28, y: 29.5)
            a.towPoint = CGPoint(x: 28, y: 29.5)
            a.beaconTop = CGPoint(x: 143, y: 25)
            a.beaconBottom = CGPoint(x: 143, y: 52)
            a.labelRect = CGRect(x: 44, y: 28.6, width: 70, height: 4.6)

        case .fighter:
            var body = Path()
            body.move(to: CGPoint(x: 198, y: 36))
            body.addQuadCurve(to: CGPoint(x: 142, y: 29), control: CGPoint(x: 170, y: 30))
            body.addQuadCurve(to: CGPoint(x: 110, y: 26.5), control: CGPoint(x: 128, y: 21))
            body.addLine(to: CGPoint(x: 40, y: 27.5))
            body.addLine(to: CGPoint(x: 20, y: 29))
            body.addLine(to: CGPoint(x: 20, y: 39))
            body.addLine(to: CGPoint(x: 62, y: 42))
            body.addLine(to: CGPoint(x: 132, y: 43))
            body.addQuadCurve(to: CGPoint(x: 198, y: 36), control: CGPoint(x: 172, y: 42))
            body.closeSubpath()
            a.add(.fuselage, body)
            // Bubble canopy.
            var canopy = Path()
            canopy.move(to: CGPoint(x: 142, y: 29))
            canopy.addQuadCurve(to: CGPoint(x: 112, y: 26.6), control: CGPoint(x: 128, y: 20.5))
            canopy.closeSubpath()
            a.add(.glass, canopy)
            // Engine nozzle and the intake under the nose.
            a.add(.detail, Path(roundedRect: CGRect(x: 12, y: 30, width: 9, height: 8), cornerSize: CGSize(width: 1.5, height: 1.5)))
            a.add(.detail, Path(ellipseIn: CGRect(x: 118, y: 40.5, width: 18, height: 5)))
            a.add(.tail, polygon([(64, 27.5), (36, 5), (24, 5), (34, 27.5)]))
            a.add(.wing, polygon([(120, 35), (62, 45), (50, 45), (70, 35)]))
            a.add(.stabilizer, polygon([(44, 34), (22, 40), (13, 40), (28, 34)]))
            a.cabin = CGRect(x: 40, y: 27.5, width: 70, height: 14)
            a.windscreen = false
            a.stripe = false
            a.wingtip = CGPoint(x: 56, y: 45)
            a.farWingtip = CGPoint(x: 62, y: 25.5)
            a.tailLight = CGPoint(x: 13, y: 34)
            a.towPoint = CGPoint(x: 13, y: 34)
            a.beaconTop = CGPoint(x: 96, y: 26.2)
            a.beaconBottom = CGPoint(x: 96, y: 43.2)
            a.labelRect = CGRect(x: 66, y: 29, width: 44, height: 5)

        case .militaryTransport:
            a.fuselage(tail: 6, nose: 194, top: 22, bottom: 44, tailLength: 3.3)
            a.fin(50, 22, 26, 10, baseY: 24, topY: 2)
            a.stabilizer(x: 30, y: 2, length: 30)
            // Landing gear fairing along the belly.
            a.add(.fuselage, pill(86, 40, 40, 8))
            // High wing drooping toward the viewer, engines under it.
            a.add(.wing, polygon([(128, 23), (86, 34), (74, 34), (94, 23)]))
            a.pod(102, 30, 22, 9)
            a.pod(80, 34.5, 18, 8)
            a.wingtip = CGPoint(x: 80, y: 34)
            a.farWingtip = CGPoint(x: 86, y: 19.5)
            a.stripe = false
            // Ahead of the wing.
            a.labelRect = CGRect(x: 132, y: 27, width: 44, height: 8)

        case .glider:
            a.fuselage(tail: 30, nose: 170, top: 31, bottom: 40, pointed: true, tailLength: 7)
            a.add(.glass, Path(ellipseIn: CGRect(x: 124, y: 28, width: 30, height: 9)))
            a.fin(54, 40, 44, 34, baseY: 33, topY: 12)
            a.stabilizer(x: 48, y: 12, length: 20)
            // One long, thin wing coming straight toward the viewer.
            a.add(.wing, polygon([(124, 33), (114, 58), (109, 58), (108, 33)]))
            a.add(.detail, Path(ellipseIn: CGRect(x: 116, y: 38, width: 7, height: 7)))
            a.windscreen = false
            a.wingtip = CGPoint(x: 111.5, y: 58)
            a.farWingtip = CGPoint(x: 112, y: 28.5)
            a.labelRect = CGRect(x: 62, y: 33.4, width: 44, height: 4.6)
        }
        return a
    }
}
