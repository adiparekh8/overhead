import AppKit
import OverheadCore
import SwiftUI

/// Everything needed to animate one aircraft across the screen.
struct FlyoverInfo: Equatable {
    var shape: AircraftShape
    /// "N628TS"
    var title: String
    /// "2015 Gulfstream G650ER"
    var subtitle: String
    var leftToRight: Bool
    var duration: TimeInterval
    var trend: VerticalTrend
    /// High-altitude jets leave a contrail.
    var contrail: Bool

    init(_ item: OverheadAircraft) {
        let aircraft = item.aircraft
        shape = AircraftShape.classify(typeCode: aircraft.typeCode, category: aircraft.category)
        title = item.tailNumber
        subtitle = item.typeLine
        leftToRight = FlyoverPolicy.fliesLeftToRight(heading: aircraft.heading)
        duration = FlyoverPolicy.duration(groundSpeedKnots: aircraft.gs)
        trend = VerticalTrend(feetPerMinute: aircraft.verticalRate)
        let isJet = ![AircraftShape.pistonSingle, .helicopter, .turboprop].contains(shape)
        contrail = isJet && item.nearby.altitudeFeet >= 26_000
    }

    init(shape: AircraftShape, title: String, subtitle: String, leftToRight: Bool,
         duration: TimeInterval, trend: VerticalTrend, contrail: Bool) {
        self.shape = shape; self.title = title; self.subtitle = subtitle
        self.leftToRight = leftToRight; self.duration = duration; self.trend = trend
        self.contrail = contrail
    }
}

/// The aircraft with its caption, as it appears on screen. Faces the
/// direction of travel.
struct FlyoverAircraftView: View {
    let info: FlyoverInfo

    static let contrailLength: CGFloat = 170

    var planeWidth: CGFloat { AircraftSilhouette.displayWidth(for: info.shape) }
    var planeHeight: CGFloat { planeWidth * AircraftSilhouette.unitSize.height / AircraftSilhouette.unitSize.width }
    var totalWidth: CGFloat { planeWidth + (info.contrail ? Self.contrailLength : 0) }

    var body: some View {
        // Drawn nose-right, then mirrored for westbound aircraft.
        HStack(spacing: -6) {
            if info.contrail {
                LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.75)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: Self.contrailLength, height: 2.5)
                .clipShape(Capsule())
                .blur(radius: 0.6)
                .offset(y: planeHeight * 0.06)
            }
            AircraftSilhouette(shape: info.shape)
                .fill(.white)
                .frame(width: planeWidth, height: planeHeight)
                // Nose up in a climb, down in a descent.
                .rotationEffect(.degrees(info.trend == .climbing ? -5 : info.trend == .descending ? 4 : 0))
                // The caption hangs centered under the aircraft, and may be wider than it.
                .overlay(alignment: .bottom) {
                    caption
                        .scaleEffect(x: info.leftToRight ? 1 : -1, y: 1)
                        .offset(y: Self.captionHeight + 5)
                }
        }
        .scaleEffect(x: info.leftToRight ? 1 : -1, y: 1)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .frame(width: totalWidth, height: planeHeight + Self.captionHeight + 5, alignment: .top)
    }

    static let captionHeight: CGFloat = 22

    private var caption: some View {
        HStack(spacing: 6) {
            Text(info.title)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
            Text(info.subtitle)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.8)
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .frame(height: Self.captionHeight)
        .background(.black.opacity(0.55), in: Capsule())
    }
}

/// Moves the aircraft from one edge of the strip to the other.
private struct FlyoverStrip: View {
    let info: FlyoverInfo
    let reduceMotion: Bool
    @State private var progress: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let plane = FlyoverAircraftView(info: info)
            // Room for a caption wider than the aircraft.
            let margin: CGFloat = 170
            let from = info.leftToRight ? -plane.totalWidth - margin : geometry.size.width + margin
            let to = info.leftToRight ? geometry.size.width + margin : -plane.totalWidth - margin
            let still = (geometry.size.width - plane.totalWidth) / 2
            plane
                .offset(x: reduceMotion ? still : from + (to - from) * progress, y: 16)
                .opacity(reduceMotion ? opacity : 1)
        }
        .onAppear {
            if reduceMotion {
                // No movement: fade in at the top of the screen, then out.
                withAnimation(.easeInOut(duration: 0.6)) { opacity = 1 }
                withAnimation(.easeInOut(duration: 0.6).delay(max(1, info.duration - 1.2))) { opacity = 0 }
            } else {
                withAnimation(.linear(duration: info.duration)) { progress = 1 }
            }
        }
    }
}

/// Shows the flyover in a transparent, click-through window across the top
/// of the main screen, just below the menu bar.
@MainActor
final class FlyoverController {
    static let shared = FlyoverController()

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private(set) var isFlying = false

    /// Starts a flyover. Ignored while another one is on screen.
    @discardableResult
    func fly(_ info: FlyoverInfo) -> Bool {
        guard !isFlying, let screen = NSScreen.screens.first else { return false }
        isFlying = true

        let height: CGFloat = 130
        let visible = screen.visibleFrame
        let frame = NSRect(x: screen.frame.minX, y: visible.maxY - height, width: screen.frame.width, height: height)

        let panel = self.panel ?? {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            // Clicks pass straight through to whatever is underneath.
            panel.ignoresMouseEvents = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            return panel
        }()
        self.panel = panel
        panel.setFrame(frame, display: false)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.contentView = NSHostingView(rootView: FlyoverStrip(info: info, reduceMotion: reduceMotion))
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(info.duration + 0.4))
            guard let self, !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            self.panel?.contentView = nil
            self.isFlying = false
        }
        return true
    }
}
