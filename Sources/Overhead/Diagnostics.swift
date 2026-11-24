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
        if CommandLine.arguments.contains("--flyover-only") {
            // Just the flyover, with the card closed: for measuring its cost.
            try? await Task.sleep(for: .seconds(6))
            AppModel.shared.playPreview(FlyoverPreview(shape: .narrowbody, paint: "UAL", sky: .night, leftToRight: true, banner: true))
            print("self-test: flyover started, flying = \(FlyoverController.shared.isFlying)")
            try? await Task.sleep(for: .seconds(12))
            print("self-test: flyover done, flying = \(FlyoverController.shared.isFlying)")
            return
        }
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
        print("self-test: focus access = \(SystemState.focusAccess), focus on = \(String(describing: SystemState.focusOn)), full screen = \(SystemState.isFullScreen), mirrored = \(SystemState.isMirrored)")
        print("self-test: sky darkness here = \(AppModel.shared.skyDarkness), block = \(String(describing: AppModel.shared.flyoverRules.block(SystemState.conditions())))")
        AppModel.shared.playPreview(FlyoverPreview(shape: .narrowbody, paint: "UAL", sky: .night, leftToRight: true, banner: true))
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

            // Flyover art. Day sky, dusk and night backdrops.
            let daySky = LinearGradient(colors: [Color(red: 0.36, green: 0.6, blue: 0.9), Color(red: 0.72, green: 0.84, blue: 0.95)], startPoint: .top, endPoint: .bottom)
            let duskSky = LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.36), Color(red: 0.82, green: 0.47, blue: 0.36)], startPoint: .top, endPoint: .bottom)
            let nightSky = LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.08), Color(red: 0.07, green: 0.09, blue: 0.17)], startPoint: .top, endPoint: .bottom)

            func scene(_ shape: AircraftShape, paint: String, sky: FlyoverPreview.Sky = .day,
                       east: Bool = true, banner: Bool = false, time: Double = 0.4) -> FlyoverSceneView {
                let preview = FlyoverPreview(shape: shape, paint: paint, sky: sky, leftToRight: east, banner: banner)
                return FlyoverSceneView(info: preview.info(automaticDarkness: 0), time: time)
            }
            func grid(_ scenes: [FlyoverSceneView], columns: Int, cell: CGSize) -> some View {
                let rows = stride(from: 0, to: scenes.count, by: columns).map { Array(scenes[$0..<min($0 + columns, scenes.count)]) }
                return VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                                item.frame(width: cell.width, height: cell.height)
                            }
                        }
                    }
                }
                .padding(10)
            }

            // 1. Every shape, private company paint, so the lettering shows.
            let shapesA = Array(AircraftShape.allCases.prefix(8))
            let shapesB = Array(AircraftShape.allCases.dropFirst(8))
            write(grid(shapesA.map { scene($0, paint: "company") }, columns: 2, cell: CGSize(width: 400, height: 190)).background(daySky),
                  scale: 1.5, to: folder.appendingPathComponent("shapes-1.png"))
            write(grid(shapesB.map { scene($0, paint: "company") }, columns: 2, cell: CGSize(width: 400, height: 190)).background(daySky),
                  scale: 1.5, to: folder.appendingPathComponent("shapes-2.png"))

            // 2. Airline paint on the narrow-body, plus freighters.
            let liveries = ["UAL", "DAL", "AAL", "SWA", "ASA", "JBU", "NKS", "FFT", "HAL", "ACA", "BAW", "DLH", "KLM", "RYR", "UAE", "QFA"]
            var painted = liveries.map { scene(.narrowbody, paint: $0) }
            painted.append(scene(.cargoWidebody, paint: "FDX"))
            painted.append(scene(.cargoWidebody, paint: "UPS"))
            painted.append(scene(.pistonSingle, paint: "individual"))
            painted.append(scene(.largeBusinessJet, paint: "individual"))
            write(grid(painted, columns: 4, cell: CGSize(width: 310, height: 160)).background(daySky),
                  scale: 1.3, to: folder.appendingPathComponent("airlines.png"))

            // 3. Banners: eastbound, westbound, and three moments of the ripple.
            write(grid([
                scene(.narrowbody, paint: "UAL", banner: true, time: 0.0),
                scene(.narrowbody, paint: "UAL", banner: true, time: 0.2),
                scene(.narrowbody, paint: "UAL", banner: true, time: 0.4),
                scene(.widebody, paint: "BAW", east: false, banner: true, time: 0.3),
                scene(.largeBusinessJet, paint: "company", banner: true, time: 0.1),
                scene(.pistonSingle, paint: "individual", east: false, banner: true, time: 0.5),
            ], columns: 1, cell: CGSize(width: 640, height: 175)).background(daySky),
                  scale: 1.3, to: folder.appendingPathComponent("banners.png"))

            // 4. Dusk and night, with lights. Two instants so both the beacon
            //    (first column) and the strobes (second column) are caught lit.
            write(grid([
                scene(.narrowbody, paint: "DAL", sky: .dusk, banner: true, time: 0.05),
                scene(.largeBusinessJet, paint: "company", sky: .dusk, east: false, time: 0.72),
            ], columns: 1, cell: CGSize(width: 640, height: 175)).background(duskSky),
                  scale: 1.3, to: folder.appendingPathComponent("dusk.png"))
            write(grid([
                scene(.narrowbody, paint: "UAL", sky: .night, banner: true, time: 0.05),
                scene(.widebody, paint: "UAE", sky: .night, east: false, banner: true, time: 0.72),
                scene(.largeBusinessJet, paint: "company", sky: .night, time: 0.05),
                scene(.helicopter, paint: "individual", sky: .night, east: false, time: 0.72),
                scene(.pistonSingle, paint: "individual", sky: .night, time: 0.72),
            ], columns: 1, cell: CGSize(width: 640, height: 175)).background(nightSky),
                  scale: 1.3, to: folder.appendingPathComponent("night.png"))

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
