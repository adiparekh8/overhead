import OverheadCore
import SwiftUI

/// A north-up scope: the user at the center, nearby aircraft as dots, the
/// overhead one highlighted, and a slow sweep.
struct RadarView: View {
    let aircraft: [NearbyAircraft]
    let highlightedID: String?
    let radiusNM: Double
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let sweepPeriod = 5.0

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let seconds = timeline.date.timeIntervalSinceReferenceDate
                    scope(sweep: seconds.truncatingRemainder(dividingBy: sweepPeriod) / sweepPeriod * 360)
                }
            } else {
                scope(sweep: nil)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Radar")
        .accessibilityValue("\(aircraft.count) aircraft within range")
    }

    private func scope(sweep: Double?) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1
            let circle = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
            ))

            context.fill(circle, with: .color(.white.opacity(0.04)))

            // Sweep: a fading wedge trailing the leading edge.
            if let sweep {
                var layer = context
                layer.clip(to: circle)
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .degrees(sweep - 90))
                let wedge = Path { path in
                    path.move(to: .zero)
                    path.addArc(center: .zero, radius: radius, startAngle: .degrees(-70), endAngle: .zero, clockwise: false)
                    path.closeSubpath()
                }
                layer.fill(wedge, with: .conicGradient(
                    Gradient(stops: [
                        .init(color: .accentColor.opacity(0), location: 0),
                        .init(color: .accentColor.opacity(0), location: 290.0 / 360),
                        .init(color: .accentColor.opacity(0.28), location: 1),
                    ]),
                    center: .zero
                ))
                var edge = Path()
                edge.move(to: .zero)
                edge.addLine(to: CGPoint(x: radius, y: 0))
                layer.stroke(edge, with: .color(.accentColor.opacity(0.55)), lineWidth: 1)
            }

            // Range rings and cross hairs.
            for fraction in [1.0 / 3, 2.0 / 3, 1.0] {
                let r = radius * fraction
                let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                context.stroke(ring, with: .color(.white.opacity(fraction == 1 ? 0.22 : 0.1)), lineWidth: 1)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - radius, y: center.y))
            cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: center.y - radius))
            cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            context.stroke(cross, with: .color(.white.opacity(0.06)), lineWidth: 1)

            // Aircraft. Each dot is brightest just after the sweep passes it.
            for plane in aircraft.reversed() {
                let distance = min(1, plane.groundNM / max(radiusNM, 0.1))
                let angle = plane.bearing * .pi / 180
                let point = CGPoint(
                    x: center.x + sin(angle) * radius * distance,
                    y: center.y - cos(angle) * radius * distance
                )
                let isHighlighted = plane.id == highlightedID
                var glow = 1.0
                if let sweep {
                    let since = (sweep - plane.bearing).truncatingRemainder(dividingBy: 360)
                    let behind = (since + 360).truncatingRemainder(dividingBy: 360) / 360
                    glow = 1 - 0.55 * behind
                }

                if isHighlighted {
                    let halo = Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
                    context.fill(halo, with: .color(.accentColor.opacity(0.22 * glow)))
                    context.stroke(halo, with: .color(.accentColor.opacity(0.5 * glow)), lineWidth: 1)
                    // A short tick showing where it is going.
                    if let heading = plane.aircraft.heading {
                        let h = heading * .pi / 180
                        var tick = Path()
                        tick.move(to: point)
                        tick.addLine(to: CGPoint(x: point.x + sin(h) * 16, y: point.y - cos(h) * 16))
                        context.stroke(tick, with: .color(.accentColor.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                    let dot = Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                    context.fill(dot, with: .color(.accentColor))
                } else {
                    let dot = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
                    context.fill(dot, with: .color(.white.opacity(0.3 + 0.55 * glow)))
                }
            }

            // The user.
            let me = Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
            context.fill(me, with: .color(.white))
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)),
                with: .color(.white.opacity(0.35)), lineWidth: 1
            )

            context.draw(
                Text("N").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.45)),
                at: CGPoint(x: center.x, y: center.y - radius + 9)
            )
        }
    }
}
