import AppKit
import OverheadCore
import SwiftUI

/// Command-line helpers for checking the app without the menu bar.
///
///     Overhead --check LAT LON [RADIUS_NM]   one API request, printed as text
///     Overhead --snapshot DIR                draw the card and menu bar item to PNG files
enum Diagnostics {
    static func check(_ arguments: [String]) -> Never {
        guard arguments.count >= 2, let lat = Double(arguments[0]), let lon = Double(arguments[1]),
              Coordinate(latitude: lat, longitude: lon).isValid else {
            print("usage: Overhead --check LAT LON [RADIUS_NM]")
            exit(2)
        }
        let here = Coordinate(latitude: lat, longitude: lon)
        let radius = arguments.count > 2 ? Double(arguments[2]) ?? 15 : 15

        Task {
            do {
                let result = try await ADSBClient().aircraft(
                    near: here.coarse, radiusNM: OverheadPicker.requestRadiusNM(for: radius)
                )
                let ranked = OverheadPicker.rank(result.response.ac, from: here, radiusNM: radius)
                print("\(result.response.ac.count) aircraft returned, \(ranked.count) airborne within \(Int(radius)) nm")
                if let limit = result.rateLimit {
                    print("quota: \(limit.remaining) requests left, resets in \(Int(limit.resetIn / 60)) min")
                }
                let registry = try? Registry(url: Registry.defaultURL)
                if registry == nil { print("aircraft.db not found: run build_db.py") }
                for (index, plane) in ranked.prefix(4).enumerated() {
                    let a = plane.aircraft
                    let record = a.icaoHex.flatMap { registry?.lookup(hex: $0) }
                    let name = record?.nNumber ?? a.registration ?? a.callsign ?? a.hex
                    print(String(
                        format: "%@ %@  %@  %@  slant %.1f nm  ground %.1f nm  bearing %.0f°",
                        index == 0 ? "OVERHEAD" : "        ", name, a.typeCode ?? "----",
                        Format.altitude(feet: plane.altitudeFeet, unit: .feet),
                        plane.slantNM, plane.groundNM, plane.bearing
                    ))
                    if index == 0 {
                        if let record {
                            print("         \(record.aircraftName ?? "")")
                            print("         owner: \(record.ownerDisplay) (\(record.registrantType), \(record.place))")
                        } else {
                            print("         Not in the FAA registry")
                        }
                    }
                }
                exit(0)
            } catch let failure as ADSBClient.Failure {
                print("failed: \(failure.message)")
                exit(1)
            } catch {
                print("failed: \(error)")
                exit(1)
            }
        }
        dispatchMain()
    }

    @MainActor
    private static func write(_ view: some View, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else {
            print("could not render \(url.lastPathComponent)")
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }

    /// Opens the real card from the menu bar, saves a picture of it, then
    /// closes it again. Used to check the running app without clicking.
    @MainActor
    static func selfTest(saveTo directory: String) async {
        func button(in view: NSView?) -> NSStatusBarButton? {
            guard let view else { return nil }
            if let found = view as? NSStatusBarButton { return found }
            return view.subviews.lazy.compactMap { button(in: $0) }.first
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        try? await Task.sleep(for: .seconds(4))
        guard let statusButton = NSApp.windows.lazy.compactMap({ button(in: $0.contentView) }).first else {
            print("self-test: no menu bar item found")
            return
        }
        print("self-test: menu bar item is \(Int(statusButton.frame.width)) pt wide")
        statusButton.performClick(nil)
        try? await Task.sleep(for: .seconds(2))

        let cards = NSApp.windows.filter { $0.isVisible && $0.contentView.map { button(in: $0) == nil } == true }
        print("self-test: card open = \(AppModel.shared.cardOpen), visible windows = \(cards.count)")
        if let view = cards.first?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("live-card.png")
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
            print("self-test: wrote \(url.path) (\(Int(view.bounds.width)) x \(Int(view.bounds.height)) pt)")
        }
        AppModel.shared.previewFlyover()
        try? await Task.sleep(for: .seconds(1))
        let overlay = NSApp.windows.first { $0.ignoresMouseEvents && $0.isVisible }
        print("self-test: flyover window visible = \(overlay != nil), frame = \(overlay?.frame ?? .zero), flying = \(FlyoverController.shared.isFlying)")
        try? await Task.sleep(for: .seconds(14))
        print("self-test: after flyover, flying = \(FlyoverController.shared.isFlying), window visible = \(NSApp.windows.contains { $0.ignoresMouseEvents && $0.isVisible })")
        statusButton.performClick(nil)
        try? await Task.sleep(for: .seconds(2))
        print("self-test: after closing, card open = \(AppModel.shared.cardOpen)")
    }

    static func snapshot(to directory: String) -> Never {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let here = Coordinate(latitude: 37.62, longitude: -122.38)
            let sample: [ADSBAircraft] = [
                ADSBAircraft(hex: "a835af", flight: "N628TS  ", r: "N628TS", t: "GLF6", altBaro: .feet(4200),
                             gs: 248, track: 312, baroRate: 1850, lat: 37.645, lon: -122.352, seenPos: 1),
                ADSBAircraft(hex: "ac3dec", flight: "SWA3231 ", r: "N8880G", t: "B38M", altBaro: .feet(9300),
                             gs: 286, track: 120, baroRate: -900, lat: 37.70, lon: -122.47, seenPos: 1),
                ADSBAircraft(hex: "a1b2c3", flight: "UAL512  ", r: "N37502", t: "B39M", altBaro: .feet(14250),
                             gs: 331, track: 200, lat: 37.52, lon: -122.26, seenPos: 1),
                ADSBAircraft(hex: "4ca87c", flight: "EIN147  ", r: "EI-LRA", t: "A21N", altBaro: .feet(21000),
                             gs: 402, track: 60, lat: 37.78, lon: -122.19, seenPos: 1),
                ADSBAircraft(hex: "a0f0f0", r: "N172SP", t: "C172", altBaro: .feet(2500),
                             gs: 98, track: 280, lat: 37.50, lon: -122.50, seenPos: 1),
            ]
            let record = RegistryRecord(
                nNumber: "N628TS", owner: "FALCON LANDING LLC", registrantType: "LLC", city: "HAWTHORNE",
                state: "CA", manufacturer: "GULFSTREAM AEROSPACE CORP", model: "GVI (G650ER)", year: "2015"
            )

            let full = AppModel()
            full.loadSample(sample, here: here, record: record)
            let backdrop = LinearGradient(
                colors: [Color(red: 0.13, green: 0.14, blue: 0.17), Color(red: 0.07, green: 0.08, blue: 0.1)],
                startPoint: .top, endPoint: .bottom
            )
            write(CardView(model: full, animated: false).background(backdrop),
                  scale: 2, to: folder.appendingPathComponent("card.png"))

            let noMatch = AppModel()
            noMatch.loadSample(Array(sample[3...]), here: here, record: nil)
            write(CardView(model: noMatch, animated: false).background(backdrop),
                  scale: 2, to: folder.appendingPathComponent("card-no-match.png"))

            let empty = AppModel()
            empty.loadSample([], here: here, record: nil)
            write(CardView(model: empty, animated: false).background(backdrop),
                  scale: 2, to: folder.appendingPathComponent("card-empty.png"))

            // Every silhouette, as it appears in a flyover, on a sky and on a dark backdrop.
            let names: [(AircraftShape, String, String)] = [
                (.superJumbo, "A6-EVN", "Airbus A380-800"), (.jumbo, "N863GT", "Boeing 747-8F"),
                (.quadWidebody, "D-AIGZ", "Airbus A340-300"), (.widebody, "N2749U", "Boeing 777-300ER"),
                (.narrowbody, "N8880G", "2021 Boeing 737-8"), (.rearEngineJet, "N548CA", "Bombardier CRJ-700"),
                (.businessJet, "N628TS", "2015 Gulfstream G650ER"), (.turboprop, "N435QX", "De Havilland Dash 8-400"),
                (.pistonSingle, "N172SP", "2003 Cessna 172S"), (.helicopter, "N44PD", "Robinson R44 II"),
            ]
            let sheet = VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, entry in
                    FlyoverAircraftView(info: FlyoverInfo(
                        shape: entry.0, title: entry.1, subtitle: entry.2, leftToRight: index % 4 != 3,
                        duration: 9, trend: index == 4 ? .climbing : .level, contrail: index == 3 || index == 6
                    ))
                    .frame(width: 440, alignment: .center)
                }
            }
            .padding(20)
            write(HStack(spacing: 0) {
                sheet.background(LinearGradient(colors: [Color(red: 0.36, green: 0.6, blue: 0.9), Color(red: 0.7, green: 0.83, blue: 0.95)], startPoint: .top, endPoint: .bottom))
                sheet.background(Color(white: 0.12))
            }, scale: 1.5, to: folder.appendingPathComponent("flyover.png"))

            // The menu bar item at a few headings, on light and dark bars.
            let items = VStack(alignment: .leading, spacing: 6) {
                ForEach([0.0, 45, 90, 135, 180, 270, 312], id: \.self) { heading in
                    Image(nsImage: MenuBarRenderer.image(
                        heading: heading, text: "GLF6 · 4,200 ft", contentOpacity: 1, dim: false
                    ))
                    .renderingMode(.template)
                }
                Image(nsImage: MenuBarRenderer.image(heading: 45, text: "", contentOpacity: 1, dim: true))
                    .renderingMode(.template)
            }
            .padding(10)
            write(HStack(spacing: 0) {
                items.foregroundStyle(.white).background(Color(white: 0.15))
                items.foregroundStyle(.black).background(Color(white: 0.92))
            }, scale: 3, to: folder.appendingPathComponent("menubar.png"))
            exit(0)
        }
    }
}
