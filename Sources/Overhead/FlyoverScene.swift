import AppKit
import OverheadCore
import SwiftUI

/// Everything needed to draw one aircraft flying across the screen.
struct FlyoverInfo: Equatable {
    var shape: AircraftShape
    var livery: Livery
    /// Lettering along the fuselage (private aircraft only).
    var label: String?
    /// Caption under the aircraft: "N628TS".
    var title: String
    /// "2015 Gulfstream G650ER"
    var subtitle: String
    /// Text on the towed banner, or nil for no banner.
    var banner: String?
    var leftToRight: Bool
    var duration: TimeInterval
    var trend: VerticalTrend
    /// High-altitude jets leave a contrail (when they tow no banner).
    var contrail: Bool
    /// 0 is full day, 1 is night.
    var darkness: Double
}

extension RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

/// Sizes and positions for one flyover, worked out once.
struct FlyoverLayout {
    static let pad: CGFloat = 16
    static let captionHeight: CGFloat = 22
    static let bannerHeight: CGFloat = 24
    static let ropeLength: CGFloat = 46
    static let bridle: CGFloat = 11
    static let bannerFont = NSFont.systemFont(ofSize: 12.5, weight: .bold)
    static let contrailLength: CGFloat = 180

    let planeWidth: CGFloat
    let planeHeight: CGFloat
    let scale: CGFloat
    /// Each banner character with its advance width.
    let glyphs: [(character: Character, width: CGFloat)]
    let bannerLength: CGFloat
    let trailWidth: CGFloat
    let size: CGSize
    /// Top-left of the aircraft's box inside the scene.
    let planeOrigin: CGPoint

    init(_ info: FlyoverInfo) {
        planeWidth = CGFloat(info.shape.displayWidth)
        scale = planeWidth / AircraftArt.unitSize.width
        planeHeight = AircraftArt.unitSize.height * scale

        if let banner = info.banner, !banner.isEmpty {
            glyphs = banner.map { character in
                let width = NSAttributedString(string: String(character), attributes: [.font: Self.bannerFont]).size().width
                return (character, ceil(width * 10) / 10)
            }
            bannerLength = glyphs.reduce(0) { $0 + $1.width } + 26
            trailWidth = Self.ropeLength + Self.bridle + bannerLength + 8
        } else {
            glyphs = []
            bannerLength = 0
            trailWidth = info.contrail ? Self.contrailLength : 0
        }
        size = CGSize(
            width: planeWidth + trailWidth + Self.pad * 2,
            height: max(planeHeight, Self.bannerHeight + 24) + Self.pad * 2 + Self.captionHeight + 6
        )
        planeOrigin = CGPoint(
            x: info.leftToRight ? size.width - Self.pad - planeWidth : Self.pad,
            y: Self.pad
        )
    }

    var planeCenter: CGPoint {
        CGPoint(x: planeOrigin.x + planeWidth / 2, y: planeOrigin.y + planeHeight / 2)
    }
}

/// The aircraft, its lights, its banner and its caption at one instant.
/// A pure function of `info` and `time`, so a frame can be drawn on demand.
struct FlyoverSceneView: View {
    let info: FlyoverInfo
    /// Seconds since the flyover started.
    let time: Double

    var body: some View {
        let layout = FlyoverLayout(info)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                FlyoverPainter(info: info, layout: layout, time: time).draw(in: &context)
            }
            .frame(width: layout.size.width, height: layout.size.height)

            caption
                .position(
                    x: layout.planeCenter.x,
                    y: layout.planeOrigin.y + layout.planeHeight + 6 + FlyoverLayout.captionHeight / 2
                )
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Text(info.title)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
            if !info.subtitle.isEmpty {
                Text(info.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.8)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .frame(height: FlyoverLayout.captionHeight)
        .background(.black.opacity(0.55), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

struct FlyoverPainter {
    let info: FlyoverInfo
    let layout: FlyoverLayout
    let time: Double

    private var art: AircraftArt { AircraftArt.art(for: info.shape) }
    private var dark: Double { min(1, max(0, info.darkness)) }
    private static let nightBody = RGB(0x0B0E15)

    /// A paint color as it looks in the current light.
    private func lit(_ rgb: RGB) -> Color {
        rgb.mixed(with: Self.nightBody, dark * 0.9).color
    }

    /// Maps unit coordinates to the scene, mirrored for westbound aircraft
    /// and tilted nose-up in a climb, nose-down in a descent.
    private var transform: CGAffineTransform {
        let s = layout.scale
        let base: CGAffineTransform = info.leftToRight
            ? CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: layout.planeOrigin.x, ty: layout.planeOrigin.y)
            : CGAffineTransform(a: -s, b: 0, c: 0, d: s, tx: layout.planeOrigin.x + layout.planeWidth, ty: layout.planeOrigin.y)
        let degrees: Double = info.trend == .climbing ? -4.5 : info.trend == .descending ? 3.5 : 0
        guard degrees != 0 else { return base }
        let angle = (info.leftToRight ? degrees : -degrees) * .pi / 180
        let c = layout.planeCenter
        let tilt = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).translatedBy(x: -c.x, y: -c.y)
        return base.concatenating(tilt)
    }

    private var tiltAngle: Double {
        let degrees: Double = info.trend == .climbing ? -4.5 : info.trend == .descending ? 3.5 : 0
        return (info.leftToRight ? degrees : -degrees) * .pi / 180
    }

    func draw(in context: inout GraphicsContext) {
        let m = transform
        let tow = art.towPoint.applying(m)

        if info.banner != nil {
            drawBanner(in: &context, tow: tow)
        } else if info.contrail {
            drawContrail(in: &context, tow: tow)
        }
        drawAircraft(in: &context, m: m)
        if dark > 0.02 {
            drawLights(in: &context, m: m)
        }
    }

    // MARK: Aircraft

    private func drawAircraft(in context: inout GraphicsContext, m: CGAffineTransform) {
        let art = self.art
        let livery = info.livery
        let wingColor = livery.body.mixed(with: RGB(0x9AA1AB), 0.6)
        let glass = RGB(0x24303F).mixed(with: RGB(0xFFE2A0), dark * 0.45)
        let outline = Color.black.opacity(0.32 * (1 - dark))
        let rim = Color.white.opacity(0.13 * dark)

        // A soft shadow under everything lifts the aircraft off the wallpaper.
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1.5))
        shadowed.drawLayer { layer in
            for part in art.parts {
                layer.fill(part.path.applying(m), with: .color(.black.opacity(0.9)))
            }
        }

        let firstFuselage = art.parts.first { $0.role == .fuselage }?.path
        var decorated = false
        func decorate(_ context: inout GraphicsContext) {
            guard !decorated, let firstFuselage else { return }
            decorated = true
            drawDecorations(in: &context, clip: firstFuselage.applying(m), m: m)
        }

        for part in art.parts {
            // Lettering, stripe and windows sit on the fuselage, under
            // the wing and engines.
            if part.role == .wing || part.role == .engine || part.role == .detail { decorate(&context) }
            let path = part.path.applying(m)
            let fill: Color
            switch part.role {
            case .fuselage: fill = lit(livery.body)
            case .tail: fill = lit(livery.tail)
            case .stabilizer, .wing: fill = lit(wingColor)
            case .engine: fill = lit(livery.engine)
            case .glass: fill = glass.mixed(with: Self.nightBody, dark * 0.35).color
            case .detail: fill = lit(RGB(0x2A2E35))
            }
            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(outline), lineWidth: 0.75)
            if dark > 0 { context.stroke(path, with: .color(rim), lineWidth: 0.6) }
        }
        decorate(&context)
    }

    private func drawDecorations(in context: inout GraphicsContext, clip: Path, m: CGAffineTransform) {
        let art = self.art
        let cabin = art.cabin
        let height = cabin.height

        context.drawLayer { layer in
            layer.clip(to: clip)

            // Shading on the belly.
            let belly = Path(CGRect(x: -20, y: cabin.minY + height * 0.68, width: 240, height: height))
            layer.fill(belly.applying(m), with: .color(.black.opacity(0.08)))

            if art.stripe {
                let stripe = Path(CGRect(x: -20, y: cabin.minY + height * 0.6, width: 240, height: max(1.1, height * 0.09)))
                layer.fill(stripe.applying(m), with: .color(lit(info.livery.accent)))
            }

            if art.windows, info.label == nil {
                // Dark by day, lit from inside at night.
                let day = RGB(0x2B3442)
                let color = day.mixed(with: RGB(0xFFD98A), dark).color.opacity(0.85)
                let rows: [CGFloat] = info.shape == .superJumbo ? [0.22, 0.44] : [0.34]
                var row = Path()
                for fraction in rows {
                    var x = cabin.minX + 5
                    while x < cabin.maxX - 1 {
                        row.addRoundedRect(
                            in: CGRect(x: x, y: cabin.minY + height * fraction - 0.85, width: 1.5, height: 1.7),
                            cornerSize: CGSize(width: 0.5, height: 0.5)
                        )
                        x += 3.4
                    }
                }
                layer.fill(row.applying(m), with: .color(color))
            }

            if art.windscreen {
                var screen = Path()
                screen.addLines([
                    CGPoint(x: cabin.maxX + height * 0.28, y: cabin.minY + height * 0.2),
                    CGPoint(x: cabin.maxX + height * 0.72, y: cabin.minY + height * 0.4),
                    CGPoint(x: cabin.maxX + height * 0.66, y: cabin.minY + height * 0.5),
                    CGPoint(x: cabin.maxX + height * 0.22, y: cabin.minY + height * 0.48),
                ])
                screen.closeSubpath()
                let glass = RGB(0x24303F).mixed(with: RGB(0xFFE2A0), dark * 0.45)
                layer.fill(screen.applying(m), with: .color(glass.color))
            }

            if let door = art.door {
                layer.stroke(
                    Path(roundedRect: door, cornerSize: CGSize(width: 1, height: 1)).applying(m),
                    with: .color(.black.opacity(0.28 * (1 - dark) + 0.05)), lineWidth: 0.8
                )
            }
        }

        if let label = info.label, !label.isEmpty {
            drawLabel(label, in: &context, m: m)
        }
    }

    /// Lettering along the fuselage. Shrinks to fit; if it would be too
    /// small to read it is left off (the caption below still names the aircraft).
    private func drawLabel(_ label: String, in context: inout GraphicsContext, m: CGAffineTransform) {
        let rect = art.labelRect
        let available = rect.width * layout.scale
        var size = min(10.5, rect.height * layout.scale * 0.95)
        let minimum: CGFloat = 4.6
        func width(_ text: String, _ size: CGFloat) -> CGFloat {
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            return NSAttributedString(string: text, attributes: [.font: font, .kern: size * 0.08]).size().width
        }
        var text = label
        while width(text, size) > available, size > minimum { size -= 0.4 }
        // Still too long at the smallest size: drop letters from the end.
        while width(text, size) > available, text.count > 4 {
            text = String(text.dropLast(text.hasSuffix("…") ? 2 : 1)) + "…"
        }
        guard size >= minimum, width(text, size) <= available + 0.5 else { return }

        let center = CGPoint(x: rect.midX, y: rect.midY).applying(m)
        let ink = info.livery.body.luminance > 0.55 ? RGB(0x2A2F38) : RGB(0xF2F4F7)
        var local = context
        local.translateBy(x: center.x, y: center.y)
        local.rotate(by: .radians(tiltAngle))
        local.draw(
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .kerning(size * 0.08)
                .foregroundStyle(ink.mixed(with: RGB(0x8E96A3), dark * 0.7).color),
            at: .zero, anchor: .center
        )
    }

    // MARK: Lights

    private func glow(_ context: inout GraphicsContext, at point: CGPoint, color: Color, radius: CGFloat, strength: Double) {
        guard strength > 0.01 else { return }
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: radius * 0.9))
            layer.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color.opacity(0.95 * strength))
            )
        }
        let core = max(1, radius * 0.28)
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)),
            with: .color(Color.white.opacity(0.9 * strength))
        )
    }

    /// Navigation lights as seen from the side. Flying left to right the
    /// viewer sees the aircraft's right side, so the near wingtip is green
    /// and the far one red; flying right to left it is the other way round.
    /// White on the tail, a red beacon flashing once a second, and white
    /// strobes that double-flash about once a second.
    private func drawLights(in context: inout GraphicsContext, m: CGAffineTransform) {
        let art = self.art
        let red = Color(red: 1, green: 0.16, blue: 0.14)
        let green = Color(red: 0.12, green: 1, blue: 0.4)
        let near = info.leftToRight ? green : red
        let far = info.leftToRight ? red : green
        let unit = max(3.2, 3.6 * layout.scale)

        if let farTip = art.farWingtip {
            glow(&context, at: farTip.applying(m), color: far, radius: unit * 0.8, strength: 0.55 * dark)
        }
        glow(&context, at: art.wingtip.applying(m), color: near, radius: unit * 1.15, strength: dark)
        glow(&context, at: art.tailLight.applying(m), color: .white, radius: unit * 0.9, strength: 0.8 * dark)

        let beaconPhase = time.truncatingRemainder(dividingBy: 1.0)
        if beaconPhase < 0.14 {
            glow(&context, at: art.beaconTop.applying(m), color: red, radius: unit * 1.5, strength: dark)
            glow(&context, at: art.beaconBottom.applying(m), color: red, radius: unit * 1.5, strength: dark)
        }

        let strobePhase = (time + 0.35).truncatingRemainder(dividingBy: 1.05)
        if strobePhase < 0.05 || (strobePhase >= 0.14 && strobePhase < 0.19) {
            glow(&context, at: art.wingtip.applying(m), color: .white, radius: unit * 2.3, strength: dark)
            glow(&context, at: art.tailLight.applying(m), color: .white, radius: unit * 1.8, strength: dark)
        }
    }

    // MARK: Contrail

    private func drawContrail(in context: inout GraphicsContext, tow: CGPoint) {
        let direction: CGFloat = info.leftToRight ? -1 : 1
        let length = FlyoverLayout.contrailLength
        let start = CGPoint(x: tow.x + direction * 2, y: tow.y + 4 * layout.scale)
        let end = CGPoint(x: start.x + direction * length, y: start.y)
        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.2))
            layer.stroke(
                line,
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.8 - 0.45 * dark), .white.opacity(0)]),
                    startPoint: start, endPoint: end
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
        }
    }

    // MARK: Banner

    /// A banner towed on a line, like aerial advertising. It ripples, with
    /// more flutter toward the free end, and bobs a little behind the tail.
    private func drawBanner(in context: inout GraphicsContext, tow: CGPoint) {
        // Banner runs away from the direction of travel.
        let direction: CGFloat = info.leftToRight ? -1 : 1
        let height = FlyoverLayout.bannerHeight
        let length = layout.bannerLength
        let accent = info.livery.accent.luminance > 0.92 ? info.livery.tail : info.livery.accent

        // The banner lags: the line stretches and the banner bobs slowly.
        let stretch = 3 * sin(time * 2.1)
        let apex = CGPoint(
            x: tow.x + direction * (FlyoverLayout.ropeLength + stretch),
            y: tow.y + 10 + 2.2 * sin(time * 2.6 + 0.8)
        )
        let poleX = apex.x + direction * FlyoverLayout.bridle
        let centerY = apex.y

        func ripple(_ u: CGFloat) -> CGFloat {
            let amplitude = 0.5 + 3.4 * pow(max(0, u) / max(1, length), 1.2)
            return amplitude * sin(2 * .pi * u / 95 - 2 * .pi * 1.25 * time)
        }
        func slope(_ u: CGFloat) -> CGFloat {
            (ripple(u + 0.5) - ripple(u - 0.5)) * direction
        }

        // Tow line, sagging slightly, then the bridle to both ends of the pole.
        var rope = Path()
        rope.move(to: tow)
        rope.addQuadCurve(to: apex, control: CGPoint(x: (tow.x + apex.x) / 2, y: max(tow.y, apex.y) + 6))
        rope.move(to: CGPoint(x: poleX, y: centerY - height / 2 + ripple(0)))
        rope.addLine(to: apex)
        rope.addLine(to: CGPoint(x: poleX, y: centerY + height / 2 + ripple(0)))
        let ropeColor = Color(white: dark > 0.5 ? 0.75 : 0.2).opacity(0.75)
        context.stroke(rope, with: .color(ropeColor), lineWidth: 1)

        // The cloth.
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        var u: CGFloat = 0
        while u <= length {
            let x = poleX + direction * u
            let y = centerY + ripple(u)
            top.append(CGPoint(x: x, y: y - height / 2))
            bottom.append(CGPoint(x: x, y: y + height / 2))
            u += 4
        }
        var cloth = Path()
        cloth.addLines(top + bottom.reversed())
        cloth.closeSubpath()

        if dark > 0.05 {
            // Glows softly at night.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 8))
                layer.fill(cloth, with: .color(Color(red: 1, green: 0.92, blue: 0.7).opacity(0.5 * dark)))
            }
        }
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.3), radius: 2.5, x: 0, y: 1.5))
        // The cloth stays light through dusk and turns dark only as night
        // falls, so the lettering never passes through grey-on-grey.
        let nightfall = min(1, max(0, (dark - 0.6) / 0.3))
        let clothColor = RGB(0xFBFAF6).mixed(with: RGB(0x1A2030), nightfall * 0.88)
        shadowed.fill(cloth, with: .color(clothColor.color.opacity(0.97)))

        // Edges in the airline's color.
        var edges = Path()
        edges.addLines(top)
        edges.move(to: bottom[0])
        edges.addLines(bottom)
        let edgeColor = accent.mixed(with: .white, dark * 0.25).color
        context.stroke(edges, with: .color(edgeColor), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))

        // The weighted pole at the leading edge.
        var pole = Path()
        pole.move(to: top[0])
        pole.addLine(to: bottom[0])
        context.stroke(pole, with: .color(edgeColor), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

        // Letters ride the ripple one by one, always reading left to right.
        var cursor = info.leftToRight ? poleX - length + 14 : poleX + 12
        let ink = clothColor.luminance > 0.5 ? RGB(0x14171C) : RGB(0xFFF1C9)
        for glyph in layout.glyphs {
            let x = cursor + glyph.width / 2
            cursor += glyph.width
            guard glyph.character != " " else { continue }
            let along = abs(x - poleX)
            var local = context
            local.translateBy(x: x, y: centerY + ripple(along))
            local.rotate(by: .radians(atan(Double(slope(along)))))
            local.draw(
                Text(String(glyph.character))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(ink.color),
                at: .zero, anchor: .center
            )
        }
    }
}
