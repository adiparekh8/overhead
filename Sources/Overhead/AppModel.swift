import AppKit
import Observation
import OverheadCore
import ServiceManagement
import os

private let log = Logger(subsystem: "dev.overhead.Overhead", category: "poll")

/// The aircraft currently closest to the user, with its FAA record if any.
struct OverheadAircraft: Equatable, Identifiable {
    var nearby: NearbyAircraft
    var record: RegistryRecord?

    var id: String { nearby.id }
    var aircraft: ADSBAircraft { nearby.aircraft }

    /// Big title: the tail number.
    var tailNumber: String {
        record?.nNumber ?? aircraft.registration ?? aircraft.callsign ?? aircraft.hex.uppercased()
    }

    /// "2015 Gulfstream G650ER", or the ICAO type code when there is no FAA record.
    var typeLine: String {
        record?.aircraftName ?? aircraft.typeCode ?? "Unknown aircraft type"
    }

    /// Short name for the menu bar, e.g. "GLF6".
    var shortName: String {
        aircraft.typeCode ?? record.map { AircraftNaming.model($0.model) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? aircraft.callsign ?? tailNumber
    }
}

@MainActor
@Observable
final class AppModel {
    enum FetchState: Equatable {
        case idle
        case ok
        case failed(String)
        case quotaReached
    }

    // MARK: Settings (stored in UserDefaults)

    var radiusNM: Double { didSet { save(radiusNM, "radiusNM"); settingsChanged() } }
    var altitudeUnit: AltitudeUnit { didSet { save(altitudeUnit.rawValue, "altitudeUnit"); refreshMenuText() } }
    var speedUnit: SpeedUnit { didSet { save(speedUnit.rawValue, "speedUnit") } }
    var useManualLocation: Bool { didSet { save(useManualLocation, "useManualLocation"); settingsChanged() } }
    var manualLatitude: String { didSet { save(manualLatitude, "manualLatitude"); settingsChanged() } }
    var manualLongitude: String { didSet { save(manualLongitude, "manualLongitude"); settingsChanged() } }
    /// Fly a silhouette across the top of the screen when an aircraft comes close.
    var flyoverEnabled: Bool { didSet { save(flyoverEnabled, "flyoverEnabled") } }
    /// How close (straight-line, nautical miles) counts as flying over.
    var flyoverRangeNM: Double { didSet { save(flyoverRangeNM, "flyoverRangeNM") } }
    var flyoversPaused: Bool { didSet { save(flyoversPaused, "flyoversPaused"); if !flyoversPaused { flyoverBlock = nil } } }
    var quietHoursEnabled: Bool { didSet { save(quietHoursEnabled, "quietHoursEnabled") } }
    /// Minutes after midnight.
    var quietStartMinutes: Int { didSet { save(quietStartMinutes, "quietStartMinutes") } }
    var quietEndMinutes: Int { didSet { save(quietEndMinutes, "quietEndMinutes") } }
    var respectFocus: Bool { didSet { save(respectFocus, "respectFocus") } }
    var respectFullScreen: Bool { didSet { save(respectFullScreen, "respectFullScreen") } }
    var respectMirroring: Bool { didSet { save(respectMirroring, "respectMirroring") } }
    var launchAtLogin = false
    var launchAtLoginError: String?

    // MARK: State shown in the UI

    private(set) var nearby: [NearbyAircraft] = []
    private(set) var overhead: OverheadAircraft?
    private(set) var fetchState: FetchState = .idle
    private(set) var lastUpdate: Date?
    private(set) var locationStatus: LocationProvider.Status = .waiting
    private(set) var deviceLocation: Coordinate?
    private(set) var registryAvailable = false
    private(set) var registryBuiltDate: String?

    // Menu bar item. Animated by hand, because SwiftUI does not animate
    // menu bar labels.
    private(set) var menuText = ""
    private(set) var menuHeading: Double = 0
    private(set) var menuContentOpacity: Double = 1
    private(set) var menuHasAircraft = false
    /// Why the most recent flyover was held back, if it was.
    private(set) var flyoverBlock: FlyoverBlock?
    private(set) var focusAccess: SystemState.FocusAccess = .notAsked
    /// True while the card is actually on screen.
    private(set) var cardOpen = false

    // MARK: Private

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let client = ADSBClient()
    @ObservationIgnored private let location = LocationProvider()
    @ObservationIgnored private let routes = RouteClient()
    @ObservationIgnored private var registry: Registry?
    @ObservationIgnored private var registryModified: Date?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var menuAnimation: Task<Void, Never>?
    @ObservationIgnored private var isFetching = false
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var isLive = false
    @ObservationIgnored private var lastFetchStarted: Date?
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var refreshSoon = false
    @ObservationIgnored private var flyoverShown: [String: Date] = [:]
    @ObservationIgnored private var lastAircraft: [ADSBAircraft] = []
    @ObservationIgnored private var retryAfter: TimeInterval?
    @ObservationIgnored private var rateLimit: (limit: RateLimit, at: Date)?

    init() {
        let d = UserDefaults.standard
        radiusNM = d.object(forKey: "radiusNM") as? Double ?? 15
        altitudeUnit = AltitudeUnit(rawValue: d.string(forKey: "altitudeUnit") ?? "") ?? .feet
        speedUnit = SpeedUnit(rawValue: d.string(forKey: "speedUnit") ?? "") ?? .knots
        useManualLocation = d.bool(forKey: "useManualLocation")
        manualLatitude = d.string(forKey: "manualLatitude") ?? ""
        manualLongitude = d.string(forKey: "manualLongitude") ?? ""
        flyoverEnabled = d.object(forKey: "flyoverEnabled") as? Bool ?? true
        flyoverRangeNM = d.object(forKey: "flyoverRangeNM") as? Double ?? 5
        flyoversPaused = d.bool(forKey: "flyoversPaused")
        quietHoursEnabled = d.bool(forKey: "quietHoursEnabled")
        quietStartMinutes = d.object(forKey: "quietStartMinutes") as? Int ?? 22 * 60
        quietEndMinutes = d.object(forKey: "quietEndMinutes") as? Int ?? 7 * 60
        respectFocus = d.object(forKey: "respectFocus") as? Bool ?? true
        respectFullScreen = d.object(forKey: "respectFullScreen") as? Bool ?? true
        respectMirroring = d.object(forKey: "respectMirroring") as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: Lifecycle

    /// Starts location updates and polling. Not called for snapshots or tests.
    func start() {
        guard !isLive else { return }
        isLive = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        openRegistryIfNeeded()
        refreshFocusAccess()

        location.onChange = { [weak self] in
            Task { @MainActor in self?.locationChanged() }
        }
        location.start()

        // Stop polling while the Mac sleeps; pick up again on wake.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isAsleep = true
                self?.loopTask?.cancel()
            }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isAsleep = false
                self?.reschedule()
            }
        }
        reschedule()
    }

    func setCardOpen(_ open: Bool) {
        guard open != cardOpen else { return }
        cardOpen = open
        log.notice("card \(open ? "opened" : "closed", privacy: .public)")
        if open { openRegistryIfNeeded() }
        reschedule()
    }

    // MARK: Location

    var manualCoordinate: Coordinate? {
        guard let lat = Double(manualLatitude.trimmingCharacters(in: .whitespaces)),
              let lon = Double(manualLongitude.trimmingCharacters(in: .whitespaces)) else { return nil }
        let c = Coordinate(latitude: lat, longitude: lon)
        return c.isValid ? c : nil
    }

    /// The manual location when it is switched on, otherwise the Mac's
    /// location, otherwise the manual one as a fallback.
    var effectiveLocation: Coordinate? {
        if useManualLocation, let manual = manualCoordinate { return manual }
        return deviceLocation ?? manualCoordinate
    }

    var isUsingManualLocation: Bool {
        manualCoordinate != nil && (useManualLocation || deviceLocation == nil)
    }

    private func locationChanged() {
        let hadLocation = effectiveLocation != nil
        locationStatus = location.status
        deviceLocation = location.coordinate
        if !hadLocation, effectiveLocation != nil {
            reschedule()
        } else if effectiveLocation == nil {
            clearAircraft()
        }
    }

    private func settingsChanged() {
        guard isLive else { return }
        // Show the change at once using what we already have, then fetch
        // again soon (still no sooner than the minimum interval).
        if let here = effectiveLocation {
            apply(lastAircraft, here: here)
        } else {
            clearAircraft()
        }
        refreshSoon = true
        reschedule()
    }

    // MARK: Polling

    private func currentRateLimit(now: Date = Date()) -> RateLimit? {
        guard let rateLimit else { return nil }
        let elapsed = now.timeIntervalSince(rateLimit.at)
        // The window has rolled over; we no longer know the quota.
        guard elapsed < rateLimit.limit.resetIn else { return nil }
        return RateLimit(remaining: rateLimit.limit.remaining, resetIn: rateLimit.limit.resetIn - elapsed)
    }

    private func secondsUntilNextFetch() -> TimeInterval {
        guard let last = lastFetchStarted else { return 0 }
        let delay = PollPolicy.delay(
            cardOpen: cardOpen || refreshSoon,
            rateLimit: currentRateLimit(),
            consecutiveFailures: consecutiveFailures,
            retryAfter: retryAfter
        )
        return max(0, delay - Date().timeIntervalSince(last))
    }

    /// (Re)starts the wait for the next poll. Safe to call at any time: a
    /// request already in flight is left alone, and requests are never
    /// closer together than `PollPolicy.activeInterval`.
    private func reschedule() {
        guard isLive, !isFetching else { return }
        loopTask?.cancel()
        guard !isAsleep, effectiveLocation != nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = self.secondsUntilNextFetch()
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    if Task.isCancelled { return }
                    // The situation may have changed while waiting.
                    if self.secondsUntilNextFetch() > 0.5 { continue }
                }
                guard !self.isAsleep, self.effectiveLocation != nil else { return }
                await self.fetchOnce()
            }
        }
    }

    private func fetchOnce() async {
        guard let here = effectiveLocation else { return }
        isFetching = true
        refreshSoon = false
        lastFetchStarted = Date()
        defer { isFetching = false }
        do {
            let result = try await client.aircraft(
                near: here.coarse,
                radiusNM: OverheadPicker.requestRadiusNM(for: radiusNM)
            )
            consecutiveFailures = 0
            retryAfter = nil
            if let limit = result.rateLimit { rateLimit = (limit, Date()) }
            lastUpdate = Date()
            fetchState = .ok
            lastAircraft = result.response.ac
            log.notice("fetched \(result.response.ac.count) aircraft; quota left \(result.rateLimit?.remaining ?? -1); card open \(self.cardOpen); next in \(Int(self.secondsUntilNextFetch()))s")
            apply(lastAircraft, here: effectiveLocation ?? here)
        } catch is CancellationError {
            return
        } catch let failure as ADSBClient.Failure {
            consecutiveFailures += 1
            log.notice("fetch failed: \(failure.message, privacy: .public)")
            if case .rateLimited(let retry) = failure {
                retryAfter = retry ?? 900
                fetchState = .quotaReached
            } else {
                retryAfter = nil
                fetchState = .failed(failure.message)
            }
            dropStaleAircraft()
        } catch {
            consecutiveFailures += 1
            fetchState = .failed(error.localizedDescription)
            dropStaleAircraft()
        }
    }

    /// Old positions are worse than none: after five minutes without a
    /// successful update, stop showing them.
    private func dropStaleAircraft() {
        if let lastUpdate, Date().timeIntervalSince(lastUpdate) < 300 { return }
        clearAircraft()
    }

    private func clearAircraft() {
        lastAircraft = []
        nearby = []
        setOverhead(nil)
    }

    private func apply(_ aircraft: [ADSBAircraft], here: Coordinate) {
        let ranked = OverheadPicker.rank(aircraft, from: here, radiusNM: radiusNM)
        nearby = ranked
        guard let first = ranked.first else {
            setOverhead(nil)
            return
        }
        openRegistryIfNeeded()
        let record = first.aircraft.icaoHex.flatMap { registry?.lookup(hex: $0) }
        let item = OverheadAircraft(nearby: first, record: record)
        setOverhead(item)
        flyIfClose(item)
    }

    // MARK: Flyover

    var flyoverRules: FlyoverRules {
        var rules = FlyoverRules()
        rules.paused = flyoversPaused
        rules.quietHoursEnabled = quietHoursEnabled
        rules.quietHours = QuietHours(start: quietStartMinutes, end: quietEndMinutes)
        rules.respectFocus = respectFocus
        rules.respectFullScreen = respectFullScreen
        rules.respectMirroring = respectMirroring
        return rules
    }

    /// How dark the sky is at the user's location right now (0 day, 1 night).
    var skyDarkness: Double {
        guard let here = effectiveLocation else { return 0 }
        return Sun.darkness(at: here, date: Date())
    }

    private func flyIfClose(_ item: OverheadAircraft) {
        guard isLive, flyoverEnabled else { return }
        let now = Date()
        guard FlyoverPolicy.shouldFly(
            slantNM: item.nearby.slantNM,
            rangeNM: flyoverRangeNM,
            lastShown: flyoverShown[item.id],
            now: now
        ) else { return }

        // Held back? The menu bar item and the card carry on as usual.
        if let block = flyoverRules.block(SystemState.conditions(now: now)) {
            if flyoverBlock != block { log.notice("flyover held: \(block.rawValue, privacy: .public)") }
            flyoverBlock = block
            return
        }
        flyoverBlock = nil
        guard !FlyoverController.shared.isFlying else { return }

        flyoverShown[item.id] = now
        flyoverShown = flyoverShown.filter { now.timeIntervalSince($0.value) < FlyoverPolicy.repeatInterval }
        let darkness = skyDarkness
        Task { [weak self] in
            guard let self else { return }
            var route: FlightRoute?
            if let callsign = item.aircraft.callsign, let position = item.aircraft.coordinate {
                route = await self.routes.route(callsign: callsign, position: position)
            }
            let info = FlyoverInfo(item, route: route, darkness: darkness)
            if FlyoverController.shared.fly(info) {
                log.notice("flyover: \(item.tailNumber, privacy: .public) as \(info.shape.rawValue, privacy: .public), banner \(info.banner == nil ? "no" : "yes", privacy: .public)")
            } else {
                self.flyoverShown[item.id] = nil
            }
        }
    }

    /// Plays a flyover now, whatever the quiet rules say.
    func playPreview(_ preview: FlyoverPreview) {
        FlyoverController.shared.fly(preview.info(automaticDarkness: skyDarkness))
    }

    func refreshFocusAccess() {
        focusAccess = SystemState.focusAccess
    }

    func requestFocusAccess() {
        Task {
            focusAccess = await SystemState.requestFocusAccess()
        }
    }

    // MARK: FAA registry

    /// Opens aircraft.db, or reopens it when build_db.py has replaced it.
    private func openRegistryIfNeeded() {
        let url = Registry.defaultURL
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard let modified else {
            registry = nil
            registryModified = nil
            registryAvailable = false
            registryBuiltDate = nil
            return
        }
        if registry != nil, modified == registryModified { return }
        registry = try? Registry(url: url)
        registryModified = modified
        registryAvailable = registry != nil
        registryBuiltDate = registry?.builtDate
    }

    // MARK: Menu bar item

    private func menuText(for item: OverheadAircraft) -> String {
        "\(item.shortName) · \(Format.altitude(feet: item.nearby.altitudeFeet, unit: altitudeUnit))"
    }

    private func refreshMenuText() {
        if let overhead { menuText = menuText(for: overhead) }
    }

    private func setOverhead(_ new: OverheadAircraft?) {
        let old = overhead
        overhead = new
        let takeover = old?.id != new?.id
        let heading = new?.aircraft.heading ?? menuHeading
        let text = new.map(menuText(for:)) ?? ""

        guard isLive, takeover || abs(shortestTurn(from: menuHeading, to: heading)) > 0.5 else {
            menuText = text
            menuHasAircraft = new != nil
            if !isLive { menuHeading = heading }
            return
        }
        animateMenu(text: text, heading: heading, hasAircraft: new != nil, takeover: takeover)
    }

    private func shortestTurn(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    /// A takeover fades the old aircraft out, swaps the text, then fades
    /// the new one in while the plane turns to its heading. The same
    /// aircraft changing course just turns.
    private func animateMenu(text: String, heading: Double, hasAircraft: Bool, takeover: Bool) {
        menuAnimation?.cancel()
        menuAnimation = Task { [weak self] in
            guard let self else { return }
            let frame = Duration.milliseconds(16)
            func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }

            if takeover {
                let startOpacity = self.menuContentOpacity
                for step in 1...10 {
                    try? await Task.sleep(for: frame)
                    if Task.isCancelled { return }
                    self.menuContentOpacity = startOpacity * (1 - ease(Double(step) / 10))
                }
                self.menuText = text
                self.menuHasAircraft = hasAircraft
            } else {
                self.menuText = text
            }

            let startHeading = self.menuHeading
            let turn = self.shortestTurn(from: startHeading, to: heading)
            let startOpacity = self.menuContentOpacity
            for step in 1...22 {
                try? await Task.sleep(for: frame)
                if Task.isCancelled { return }
                let t = ease(Double(step) / 22)
                self.menuHeading = startHeading + turn * t
                self.menuContentOpacity = startOpacity + (1 - startOpacity) * t
            }
            self.menuHeading = (heading.truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
            self.menuContentOpacity = 1
        }
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Sample data (for `--snapshot`)

    func loadSample(_ aircraft: [ADSBAircraft], here: Coordinate, record: RegistryRecord?) {
        deviceLocation = here
        locationStatus = .authorized
        registryAvailable = true
        lastUpdate = Date()
        fetchState = .ok
        let ranked = OverheadPicker.rank(aircraft, from: here, radiusNM: radiusNM)
        nearby = ranked
        if let first = ranked.first {
            setOverhead(OverheadAircraft(nearby: first, record: record))
        }
    }
}
