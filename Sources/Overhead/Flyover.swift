import AppKit
import OverheadCore
import SwiftUI

extension FlyoverInfo {
    /// Builds the flyover for a real aircraft.
    init(_ item: OverheadAircraft, route: FlightRoute?, darkness: Double) {
        let aircraft = item.aircraft
        let airline = aircraft.callsign.map(Callsign.init)?.airline
        let tail = item.record?.nNumber ?? aircraft.registration

        shape = AircraftShape.classify(
            typeCode: aircraft.typeCode, category: aircraft.category, cargoOperator: airline?.cargo ?? false
        )
        livery = Livery.choose(airline: airline, shape: shape, tailNumber: item.tailNumber)
        label = FuselageLabel.text(isAirline: airline != nil, record: item.record, tailNumber: tail)
        banner = BannerText.text(
            callsign: aircraft.callsign, tailNumber: tail, route: route,
            position: aircraft.coordinate, track: aircraft.heading
        )
        // Don't say the tail number twice when the banner already carries it.
        if banner == item.tailNumber {
            title = item.typeLine
            subtitle = ""
        } else {
            title = item.tailNumber
            subtitle = item.typeLine
        }
        leftToRight = FlyoverPolicy.fliesLeftToRight(heading: aircraft.heading)
        duration = FlyoverPolicy.duration(groundSpeedKnots: aircraft.gs)
        trend = VerticalTrend(feetPerMinute: aircraft.verticalRate)
        let isJet = ![AircraftShape.pistonSingle, .pistonTwin, .helicopter, .turboprop, .glider].contains(shape)
        contrail = isJet && item.nearby.altitudeFeet >= 26_000
        self.darkness = darkness
    }
}

/// What the preview controls in Settings can ask for.
struct FlyoverPreview: Equatable {
    enum Sky: String, CaseIterable {
        case automatic, day, dusk, night
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    var shape: AircraftShape = .largeBusinessJet
    /// "company", "individual", or an airline's ICAO code.
    var paint = "company"
    var sky: Sky = .automatic
    var leftToRight = true
    var banner = true

    static let sampleType: [AircraftShape: (code: String, name: String, tail: String)] = [
        .superJumbo: ("A388", "Airbus A380-800", "N380XX"),
        .jumbo: ("B748", "Boeing 747-8", "N863GT"),
        .quadWidebody: ("A343", "Airbus A340-300", "N340XX"),
        .widebody: ("B77W", "Boeing 777-300ER", "N2749U"),
        .cargoWidebody: ("B77L", "Boeing 777F", "N885FD"),
        .narrowbody: ("B38M", "2021 Boeing 737-8", "N8880G"),
        .rearEngineJet: ("CRJ7", "Bombardier CRJ-700", "N548CA"),
        .turboprop: ("DH8D", "De Havilland Dash 8-400", "N435QX"),
        .largeBusinessJet: ("GLF6", "2015 Gulfstream G650ER", "N628TS"),
        .smallBusinessJet: ("C25B", "Cessna Citation CJ3", "N525CJ"),
        .pistonSingle: ("C172", "2003 Cessna 172S", "N172SP"),
        .pistonTwin: ("BE58", "Beechcraft Baron 58", "N58BE"),
        .helicopter: ("R44", "Robinson R44 II", "N44PD"),
        .fighter: ("F16", "General Dynamics F-16C", "AF87"),
        .militaryTransport: ("C17", "Boeing C-17A Globemaster III", "RCH871"),
        .glider: ("GLID", "Schleicher ASK 21", "N21GL"),
    ]

    func info(automaticDarkness: Double) -> FlyoverInfo {
        let sample = Self.sampleType[shape] ?? ("", shape.rawValue, "N12345")
        let airline = Airline.find(icao: paint)
        let darkness: Double
        switch sky {
        case .automatic: darkness = automaticDarkness
        case .day: darkness = 0
        case .dusk: darkness = 0.5
        case .night: darkness = 1
        }

        let livery: Livery
        let label: String?
        var bannerText: String?
        if let airline {
            livery = airline.livery
            label = nil
            bannerText = "\(airline.iata)512 · San Francisco → Newark"
        } else {
            livery = Livery.choose(airline: nil, shape: shape, tailNumber: sample.tail)
            let owner = paint == "company" ? "FALCON LANDING LLC" : "BENE MARY D"
            let record = RegistryRecord(
                nNumber: sample.tail, owner: owner, registrantType: paint == "company" ? "LLC" : "Individual",
                city: "", state: "", manufacturer: "", model: "", year: ""
            )
            label = FuselageLabel.text(isAirline: false, record: record, tailNumber: sample.tail)
            bannerText = sample.tail
        }
        if !banner { bannerText = nil }
        let tailShown = bannerText == sample.tail
        return FlyoverInfo(
            shape: shape, livery: livery, label: label,
            title: tailShown ? sample.name : sample.tail, subtitle: tailShown ? "" : sample.name,
            banner: bannerText, leftToRight: leftToRight, duration: 10, trend: .level,
            contrail: false, darkness: darkness
        )
    }
}

/// Moves the scene from one edge of the strip to the other. The timeline
/// only exists while a flyover is on screen, so nothing is drawn (and no
/// CPU is used) the rest of the time.
private struct FlyoverStrip: View {
    let info: FlyoverInfo
    let reduceMotion: Bool
    let started = Date()
    @State private var opacity: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let layout = FlyoverLayout(info)
            if reduceMotion {
                // No movement: fade in at the top of the screen, then out.
                FlyoverSceneView(info: info, time: 0)
                    .offset(x: (geometry.size.width - layout.size.width) / 2, y: 4)
                    .opacity(opacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6)) { opacity = 1 }
                        withAnimation(.easeInOut(duration: 0.6).delay(max(1, info.duration - 1.2))) { opacity = 0 }
                    }
            } else {
                // 60 frames a second is plenty, also on a 120 Hz display.
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(started)
                    let progress = min(1, max(0, elapsed / info.duration))
                    let from = info.leftToRight ? -layout.size.width : geometry.size.width
                    let to = info.leftToRight ? geometry.size.width : -layout.size.width
                    FlyoverSceneView(info: info, time: elapsed)
                        .offset(x: from + (to - from) * progress, y: 4)
                }
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

        let height = FlyoverLayout(info).size.height + 12
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
            // Removing the content stops the timeline and all drawing.
            self.panel?.orderOut(nil)
            self.panel?.contentView = nil
            self.isFlying = false
        }
        return true
    }
}
