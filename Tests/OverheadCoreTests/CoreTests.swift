import Foundation
import Testing
@testable import OverheadCore

/// A real response from GET /v2/point/37.62/-122.38/15, saved 2026-11-23.
/// 26 aircraft around San Francisco airport: 25 on the ground, one departing.
private func fixture() throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/point_sample.json")
    return try Data(contentsOf: url)
}

private let sfo = Coordinate(latitude: 37.62, longitude: -122.38)

private func close(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}

@Suite struct GeoTests {
    @Test func zeroDistance() {
        #expect(Geo.groundDistanceNM(from: sfo, to: sfo) == 0)
    }

    @Test func oneDegreeOfLatitudeIsSixtyNauticalMiles() {
        let a = Coordinate(latitude: 10, longitude: 20)
        let b = Coordinate(latitude: 11, longitude: 20)
        #expect(close(Geo.groundDistanceNM(from: a, to: b), 60.04, within: 0.05))
    }

    @Test func knownCityPair() {
        // San Francisco (SFO) to Los Angeles (LAX) is about 293 nm.
        let lax = Coordinate(latitude: 33.9425, longitude: -118.4081)
        let sfoField = Coordinate(latitude: 37.6189, longitude: -122.3750)
        #expect(close(Geo.groundDistanceNM(from: sfoField, to: lax), 293, within: 1.5))
    }

    @Test func distanceIsSymmetric() {
        let a = Coordinate(latitude: 51.5, longitude: -0.12)
        let b = Coordinate(latitude: 48.85, longitude: 2.35)
        #expect(close(Geo.groundDistanceNM(from: a, to: b), Geo.groundDistanceNM(from: b, to: a), within: 1e-9))
    }

    @Test func cardinalBearings() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        #expect(close(Geo.bearingDegrees(from: origin, to: Coordinate(latitude: 1, longitude: 0)), 0, within: 1e-6))
        #expect(close(Geo.bearingDegrees(from: origin, to: Coordinate(latitude: 0, longitude: 1)), 90, within: 1e-6))
        #expect(close(Geo.bearingDegrees(from: origin, to: Coordinate(latitude: -1, longitude: 0)), 180, within: 1e-6))
        #expect(close(Geo.bearingDegrees(from: origin, to: Coordinate(latitude: 0, longitude: -1)), 270, within: 1e-6))
    }

    @Test func slantDistance() {
        // Directly overhead at one nautical mile up.
        #expect(close(Geo.slantDistanceNM(groundNM: 0, altitudeFeet: Geo.feetPerNM), 1, within: 1e-9))
        // 3-4-5 triangle.
        #expect(close(Geo.slantDistanceNM(groundNM: 3, altitudeFeet: 4 * Geo.feetPerNM), 5, within: 1e-9))
        // On the deck, slant distance is the ground distance.
        #expect(Geo.slantDistanceNM(groundNM: 7, altitudeFeet: 0) == 7)
    }

    @Test func coarseCoordinateRoundsToTwoPlaces() {
        let c = Coordinate(latitude: 40.641766, longitude: -73.778925).coarse
        #expect(close(c.latitude, 40.64, within: 1e-9))
        #expect(close(c.longitude, -73.78, within: 1e-9))
    }

    @Test func coordinateValidity() {
        #expect(Coordinate(latitude: 37, longitude: -122).isValid)
        #expect(!Coordinate(latitude: 91, longitude: 0).isValid)
        #expect(!Coordinate(latitude: 0, longitude: 181).isValid)
        #expect(!Coordinate(latitude: .nan, longitude: 0).isValid)
    }
}

@Suite struct ParsingTests {
    @Test func decodesSavedResponse() throws {
        let response = try ADSBResponse.decode(fixture())
        #expect(response.msg == "No error")
        #expect(response.total == 26)
        #expect(response.ac.count == 26)
        #expect(response.now == 1_795_422_989_001)
    }

    @Test func airborneAircraftFields() throws {
        let response = try ADSBResponse.decode(fixture())
        let plane = try #require(response.ac.first { $0.hex == "ac3dec" })
        #expect(plane.callsign == "SWA3231")  // sent as "SWA3231 "
        #expect(plane.registration == "N8880G")
        #expect(plane.typeCode == "B38M")
        #expect(plane.altBaro == .feet(275))
        #expect(plane.altitudeFeet == 275)
        #expect(plane.altGeom == 350)
        #expect(plane.gs == 156.1)
        #expect(plane.heading == 310.32)
        #expect(plane.verticalRate == 3264)
        #expect(plane.lat == 37.713876)
        #expect(plane.lon == -122.232872)
        #expect(plane.dst == 8.973)
        #expect(plane.icaoHex == "AC3DEC")
        #expect(!plane.isOnGround)
    }

    @Test func groundAircraft() throws {
        let response = try ADSBResponse.decode(fixture())
        let plane = try #require(response.ac.first { $0.hex == "add376" })
        #expect(plane.altBaro == .ground)
        #expect(plane.isOnGround)
        #expect(plane.altitudeFeet == nil)
        // No track on this one; falls back to true_heading.
        #expect(plane.track == nil)
        #expect(plane.heading == 306.56)
        #expect(response.ac.filter(\.isOnGround).count == 25)
    }

    @Test func nonICAOAddressHasNoHexForLookup() throws {
        let response = try ADSBResponse.decode(fixture())
        let plane = try #require(response.ac.first { $0.hex == "~a7d831" })
        #expect(plane.icaoHex == nil)
        #expect(plane.callsign == nil)
        #expect(plane.typeCode == nil)
    }

    @Test func toleratesMissingNullAndOddFields() throws {
        let json = """
        {"ac": [
          {"hex": "abc123"},
          {"hex": "def456", "alt_baro": null, "alt_geom": 1200, "flight": "        ", "gs": null},
          {"hex": "0a1b2c", "alt_baro": "ground", "lat": "bad", "track": 12.5, "geom_rate": -640}
        ], "msg": "No error", "now": 1, "total": 3, "ctime": 1, "ptime": 0}
        """
        let response = try ADSBResponse.decode(Data(json.utf8))
        #expect(response.ac.count == 3)
        #expect(response.ac[0].altitudeFeet == nil)
        #expect(response.ac[0].coordinate == nil)
        // No barometric altitude: fall back to geometric.
        #expect(response.ac[1].altitudeFeet == 1200)
        #expect(response.ac[1].callsign == nil)
        #expect(response.ac[2].isOnGround)
        #expect(response.ac[2].lat == nil)
        #expect(response.ac[2].verticalRate == -640)
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try ADSBResponse.decode(Data("rate limit exceeded".utf8)) }
        #expect(throws: (any Error).self) { try ADSBResponse.decode(Data(#"{"msg": "x"}"#.utf8)) }
    }
}

@Suite struct PickerTests {
    private func plane(
        _ hex: String, lat: Double, lon: Double, alt: BaroAltitude?, seenPos: Double? = 1
    ) -> ADSBAircraft {
        ADSBAircraft(hex: hex, altBaro: alt, lat: lat, lon: lon, seenPos: seenPos)
    }

    @Test func savedResponseHasOneAirborneAircraft() throws {
        let response = try ADSBResponse.decode(fixture())
        let ranked = OverheadPicker.rank(response.ac, from: sfo, radiusNM: 15)
        #expect(ranked.count == 1)
        let overhead = try #require(ranked.first)
        #expect(overhead.aircraft.hex == "ac3dec")
        // Our own distance and bearing agree with the API's `dst` and `dir`.
        #expect(close(overhead.groundNM, 8.973, within: 0.03))
        #expect(close(overhead.bearing, 51.1, within: 0.3))
        #expect(close(overhead.slantNM, 8.973, within: 0.03))
    }

    @Test func radiusIsApplied() throws {
        let response = try ADSBResponse.decode(fixture())
        #expect(OverheadPicker.rank(response.ac, from: sfo, radiusNM: 5).isEmpty)
    }

    @Test func slantDistanceBeatsGroundDistance() {
        // A is directly overhead but at 36,000 ft (5.9 nm away in a straight line).
        // B is 3 nm away along the ground at 2,000 ft (3.0 nm away).
        let a = plane("aaaaaa", lat: 37.62, lon: -122.38, alt: .feet(36_000))
        let b = plane("bbbbbb", lat: 37.67, lon: -122.38, alt: .feet(2_000))
        let ranked = OverheadPicker.rank([a, b], from: sfo, radiusNM: 15)
        #expect(ranked.map(\.aircraft.hex) == ["bbbbbb", "aaaaaa"])
        #expect(close(ranked[0].slantNM, 3.02, within: 0.03))
        #expect(close(ranked[1].slantNM, 5.92, within: 0.03))
    }

    @Test func ignoresGroundStaleAndIncompleteAircraft() {
        let ranked = OverheadPicker.rank([
            plane("ground", lat: 37.62, lon: -122.38, alt: .ground),
            plane("noalt", lat: 37.62, lon: -122.38, alt: nil),
            plane("stale", lat: 37.62, lon: -122.38, alt: .feet(3000), seenPos: 95),
            ADSBAircraft(hex: "nopos", altBaro: .feet(3000)),
            plane("faraway", lat: 38.5, lon: -122.38, alt: .feet(3000)),
            plane("good", lat: 37.70, lon: -122.30, alt: .feet(9000)),
        ], from: sfo, radiusNM: 15)
        #expect(ranked.map(\.aircraft.hex) == ["good"])
    }

    @Test func duplicatesAreCountedOnce() {
        let a = plane("aaaaaa", lat: 37.63, lon: -122.38, alt: .feet(3000))
        #expect(OverheadPicker.rank([a, a], from: sfo, radiusNM: 15).count == 1)
    }

    @Test func nothingInRange() {
        #expect(OverheadPicker.rank([], from: sfo, radiusNM: 15).isEmpty)
    }

    @Test func requestRadiusHasMargin() {
        #expect(OverheadPicker.requestRadiusNM(for: 15) == 16)
        #expect(OverheadPicker.requestRadiusNM(for: 7.5) == 9)
        #expect(OverheadPicker.requestRadiusNM(for: 400) == 250)
    }
}

@Suite struct PollPolicyTests {
    @Test func readsRateLimitHeaders() {
        let limit = RateLimit(headers: [
            "X-RateLimit-Limit": "500, 500;w=86400",
            "X-RateLimit-Remaining": "499",
            "x-ratelimit-reset": "55411",
        ])
        #expect(limit == RateLimit(remaining: 499, resetIn: 55411))
        #expect(RateLimit(headers: ["content-type": "application/json"]) == nil)
    }

    @Test func tenSecondsWhileTheCardIsOpen() {
        let limit = RateLimit(remaining: 300, resetIn: 40_000)
        #expect(PollPolicy.delay(cardOpen: true, rateLimit: limit) == 10)
        #expect(PollPolicy.delay(cardOpen: true, rateLimit: nil) == 10)
    }

    @Test func backgroundPollingSpreadsTheQuota() {
        // A fresh day: 500 requests over 24 hours, 40 held in reserve.
        let fresh = RateLimit(remaining: 500, resetIn: 86_400)
        #expect(close(PollPolicy.delay(cardOpen: false, rateLimit: fresh), 187.8, within: 0.1))
        // A big quota never polls faster than every 10 seconds.
        let big = RateLimit(remaining: 300_000, resetIn: 86_400)
        #expect(PollPolicy.delay(cardOpen: false, rateLimit: big) == 10)
        // Unknown quota.
        #expect(PollPolicy.delay(cardOpen: false, rateLimit: nil) == 180)
    }

    @Test func stopsWhenTheQuotaIsSpent() {
        let reserveOnly = RateLimit(remaining: 30, resetIn: 5_000)
        #expect(PollPolicy.delay(cardOpen: false, rateLimit: reserveOnly) == 5_000)
        // The reserve can still be spent by opening the card.
        #expect(PollPolicy.delay(cardOpen: true, rateLimit: reserveOnly) == 10)
        let empty = RateLimit(remaining: 0, resetIn: 1_234)
        #expect(PollPolicy.delay(cardOpen: true, rateLimit: empty) == 1_234)
    }

    @Test func honorsRetryAfter() {
        #expect(PollPolicy.delay(cardOpen: true, rateLimit: nil, consecutiveFailures: 1, retryAfter: 600) == 600)
        #expect(PollPolicy.delay(cardOpen: true, rateLimit: nil, consecutiveFailures: 1, retryAfter: 2) == 10)
    }

    @Test func backsOffOnErrors() {
        let delays = (0...8).map { PollPolicy.delay(cardOpen: true, rateLimit: nil, consecutiveFailures: $0) }
        #expect(delays == [10, 20, 40, 80, 160, 320, 600, 600, 600])
        // In the background the wait never drops below the normal interval.
        #expect(PollPolicy.delay(cardOpen: false, rateLimit: nil, consecutiveFailures: 1) == 180)
        #expect(PollPolicy.delay(cardOpen: false, rateLimit: nil, consecutiveFailures: 6) == 600)
    }
}

@Suite struct FormattingTests {
    @Test func altitude() {
        #expect(Format.altitude(feet: 4212, unit: .feet) == "4,200 ft")
        #expect(Format.altitude(feet: 275, unit: .feet) == "275 ft")
        #expect(Format.altitude(feet: 36_000, unit: .meters) == "10,970 m")
    }

    @Test func speedAndDistance() {
        #expect(Format.speed(knots: 156.1, unit: .knots) == "156 kt")
        #expect(Format.speed(knots: 100, unit: .mph) == "115 mph")
        #expect(Format.distance(nm: 2.34, unit: .knots) == "2.3 nm")
        #expect(Format.distance(nm: 12.6, unit: .knots) == "13 nm")
        #expect(Format.distance(nm: 2, unit: .mph) == "2.3 mi")
    }

    @Test func compassPoints() {
        #expect(Format.compass(0) == "N")
        #expect(Format.compass(51.1) == "NE")
        #expect(Format.compass(350) == "N")
        #expect(Format.compass(225) == "SW")
        #expect(Format.compass(-90) == "W")
    }

    @Test func verticalTrend() {
        #expect(VerticalTrend(feetPerMinute: 3264) == .climbing)
        #expect(VerticalTrend(feetPerMinute: -800) == .descending)
        #expect(VerticalTrend(feetPerMinute: 64) == .level)
        #expect(VerticalTrend(feetPerMinute: nil) == .level)
    }

    @Test func aircraftNames() {
        #expect(AircraftNaming.displayName(year: "2015", manufacturer: "GULFSTREAM AEROSPACE CORP", model: "GVI (G650ER)") == "2015 Gulfstream G650ER")
        #expect(AircraftNaming.displayName(year: "", manufacturer: "CESSNA", model: "172S") == "Cessna 172S")
        #expect(AircraftNaming.displayName(year: "2019", manufacturer: "EMBRAER S A", model: "ERJ 170-200 LR") == "2019 Embraer ERJ 170-200 LR")
        #expect(AircraftNaming.displayName(year: "2020", manufacturer: "DJI", model: "MAVIC PRO") == "2020 DJI MAVIC PRO")
        #expect(AircraftNaming.displayName(year: "", manufacturer: "", model: "") == nil)
    }
}

@Suite struct RegistryRecordTests {
    private func record(owner: String, type: String) -> RegistryRecord {
        RegistryRecord(
            nNumber: "N628TS", owner: owner, registrantType: type, city: "NORTH SALT LAKE",
            state: "UT", manufacturer: "GULFSTREAM AEROSPACE CORP", model: "GVI (G650ER)", year: "2015"
        )
    }

    @Test func companyAndTrusteeOwnersAreFlagged() {
        #expect(record(owner: "FALCON LANDING LLC", type: "LLC").ownerIsCompanyOrTrustee)
        #expect(record(owner: "SOUTHWEST AIRLINES CO", type: "Corporation").ownerIsCompanyOrTrustee)
        #expect(record(owner: "TVPX AIRCRAFT SOLUTIONS INC TRUSTEE", type: "Co-owned").ownerIsCompanyOrTrustee)
        #expect(record(owner: "BANK OF UTAH TRUSTEE", type: "").ownerIsCompanyOrTrustee)
    }

    @Test func individualsAreNotFlagged() {
        #expect(!record(owner: "BENE MARY D", type: "Individual").ownerIsCompanyOrTrustee)
        // "TRUSTY" is a surname, not a trust.
        #expect(!record(owner: "TRUSTY JOHN", type: "Individual").ownerIsCompanyOrTrustee)
    }

    @Test func ownerNamesAreReadable() {
        #expect(record(owner: "FALCON LANDING LLC", type: "LLC").ownerDisplay == "Falcon Landing LLC")
        #expect(record(owner: "BANK OF UTAH TRUSTEE", type: "").ownerDisplay == "Bank of Utah Trustee")
        #expect(record(owner: "N383FR LEASING 2 INC", type: "").ownerDisplay == "N383FR Leasing 2 INC")
    }

    @Test func placeAndName() {
        let r = record(owner: "X", type: "LLC")
        #expect(r.place == "North Salt Lake, UT")
        #expect(r.aircraftName == "2015 Gulfstream G650ER")
    }

    @Test func readsADatabaseBuiltLikeBuildDB() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("overhead-test-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        let sql = """
            CREATE TABLE aircraft (mode_s_hex TEXT PRIMARY KEY, n_number TEXT NOT NULL, owner TEXT NOT NULL,
              registrant_type TEXT NOT NULL, city TEXT NOT NULL, state TEXT NOT NULL, manufacturer TEXT NOT NULL,
              model TEXT NOT NULL, year TEXT NOT NULL) WITHOUT ROWID;
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
            INSERT INTO aircraft VALUES ('A835AF','N628TS','FALCON LANDING LLC','LLC','HAWTHORNE','CA',
              'GULFSTREAM AEROSPACE CORP','GVI (G650ER)','2015');
            INSERT INTO meta VALUES ('built','2026-11-23');
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let registry = try Registry(url: url)
        let found = try #require(registry.lookup(hex: "a835af"))
        #expect(found.nNumber == "N628TS")
        #expect(found.owner == "FALCON LANDING LLC")
        #expect(found.place == "Hawthorne, CA")
        #expect(registry.lookup(hex: "FFFFFF") == nil)
        #expect(registry.lookup(hex: "") == nil)
        #expect(registry.builtDate == "2026-11-23")
    }

    @Test func missingDatabaseThrows() {
        #expect(throws: (any Error).self) {
            try Registry(url: URL(fileURLWithPath: "/nonexistent/overhead/aircraft.db"))
        }
    }
}

@Suite struct FlyoverTests {
    @Test func classifiesByTypeCode() {
        let expected: [(String, AircraftShape)] = [
            ("A388", .superJumbo), ("B748", .jumbo), ("B744", .jumbo), ("A343", .quadWidebody),
            ("B77W", .widebody), ("A359", .widebody), ("B789", .widebody), ("A310", .widebody),
            ("A319", .narrowbody), ("B38M", .narrowbody), ("A21N", .narrowbody), ("E75L", .narrowbody),
            ("B738", .narrowbody), ("BCS3", .narrowbody),
            ("CRJ9", .rearEngineJet), ("E145", .rearEngineJet), ("B712", .rearEngineJet),
            ("DH8D", .turboprop), ("AT76", .turboprop), ("C208", .turboprop), ("PC12", .turboprop), ("BE20", .turboprop),
            ("GLF6", .largeBusinessJet), ("GLEX", .largeBusinessJet), ("FA7X", .largeBusinessJet), ("CL60", .largeBusinessJet),
            ("C56X", .smallBusinessJet), ("C25B", .smallBusinessJet), ("LJ45", .smallBusinessJet), ("E55P", .smallBusinessJet),
            ("C172", .pistonSingle), ("SR22", .pistonSingle), ("P28A", .pistonSingle), ("C182", .pistonSingle),
            ("BE58", .pistonTwin), ("PA34", .pistonTwin), ("DA42", .pistonTwin), ("C310", .pistonTwin),
            ("R44", .helicopter), ("EC35", .helicopter), ("H60", .helicopter),
            ("F16", .fighter), ("F35", .fighter), ("F18S", .fighter), ("A10", .fighter),
            ("C17", .militaryTransport), ("C130", .militaryTransport), ("C30J", .militaryTransport), ("A400", .militaryTransport),
            ("GLID", .glider),
        ]
        for (code, shape) in expected {
            #expect(AircraftShape.classify(typeCode: code, category: nil) == shape, "\(code)")
        }
        // Case and padding do not matter.
        #expect(AircraftShape.classify(typeCode: "b738 ", category: nil) == .narrowbody)
        // The type code wins over the category.
        #expect(AircraftShape.classify(typeCode: "C208", category: "A1") == .turboprop)
    }

    @Test func everyShapeIsReachable() {
        let codes = ["A388", "B748", "A343", "B77W", "B738", "CRJ9", "DH8D", "GLF6", "C56X", "C172",
                     "BE58", "R44", "F16", "C17", "GLID"]
        var reached = Set(codes.map { AircraftShape.classify(typeCode: $0, category: nil) })
        reached.insert(AircraftShape.classify(typeCode: "B77L", category: nil, cargoOperator: true))
        #expect(reached == Set(AircraftShape.allCases))
        #expect(AircraftShape.allCases.count >= 14)
    }

    @Test func cargoOperatorsGetTheFreighter() {
        #expect(AircraftShape.classify(typeCode: "B77L", category: "A5", cargoOperator: true) == .cargoWidebody)
        #expect(AircraftShape.classify(typeCode: "B763", category: nil, cargoOperator: true) == .cargoWidebody)
        #expect(AircraftShape.classify(typeCode: "B77L", category: "A5", cargoOperator: false) == .widebody)
        // Only wide-bodies change: a cargo 747 is still a 747, a cargo 737 a 737.
        #expect(AircraftShape.classify(typeCode: "B748", category: nil, cargoOperator: true) == .jumbo)
        #expect(AircraftShape.classify(typeCode: "B738", category: nil, cargoOperator: true) == .narrowbody)
    }

    @Test func fallsBackToSizeCategory() {
        #expect(AircraftShape.classify(typeCode: nil, category: "A1") == .pistonSingle)
        #expect(AircraftShape.classify(typeCode: "ZZZZ", category: "A1") == .pistonSingle)
        #expect(AircraftShape.classify(typeCode: nil, category: "A2") == .smallBusinessJet)
        #expect(AircraftShape.classify(typeCode: nil, category: "A3") == .narrowbody)
        #expect(AircraftShape.classify(typeCode: "", category: "A5") == .widebody)
        #expect(AircraftShape.classify(typeCode: nil, category: "A6") == .fighter)
        #expect(AircraftShape.classify(typeCode: nil, category: "A7") == .helicopter)
        #expect(AircraftShape.classify(typeCode: nil, category: "B1") == .glider)
        #expect(AircraftShape.classify(typeCode: nil, category: nil) == .narrowbody)
    }

    @Test func biggerAircraftAreDrawnBigger() {
        #expect(AircraftShape.jumbo.displayWidth > AircraftShape.pistonSingle.displayWidth * 2)
        #expect(AircraftShape.superJumbo.displayWidth >= AircraftShape.jumbo.displayWidth)
        #expect(AircraftShape.widebody.displayWidth > AircraftShape.narrowbody.displayWidth)
        #expect(AircraftShape.narrowbody.displayWidth > AircraftShape.smallBusinessJet.displayWidth)
        #expect(AircraftShape.largeBusinessJet.displayWidth > AircraftShape.smallBusinessJet.displayWidth)
        #expect(AircraftShape.pistonTwin.displayWidth > AircraftShape.pistonSingle.displayWidth)
        // Sizes follow nominal length, strictly.
        let byLength = AircraftShape.allCases.sorted { $0.nominalLengthMeters < $1.nominalLengthMeters }
        #expect(byLength.map(\.displayWidth) == byLength.map(\.displayWidth).sorted())
    }

    @Test func fliesOnlyWhenCloseAndNotRecentlyShown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(FlyoverPolicy.shouldFly(slantNM: 2.1, rangeNM: 5, lastShown: nil, now: now))
        #expect(FlyoverPolicy.shouldFly(slantNM: 5, rangeNM: 5, lastShown: nil, now: now))
        #expect(!FlyoverPolicy.shouldFly(slantNM: 5.1, rangeNM: 5, lastShown: nil, now: now))
        // Shown ten minutes ago: not again yet.
        #expect(!FlyoverPolicy.shouldFly(slantNM: 1, rangeNM: 5, lastShown: now.addingTimeInterval(-600), now: now))
        // Shown 31 minutes ago: allowed.
        #expect(FlyoverPolicy.shouldFly(slantNM: 1, rangeNM: 5, lastShown: now.addingTimeInterval(-1860), now: now))
    }

    @Test func fasterAircraftCrossFaster() {
        #expect(FlyoverPolicy.duration(groundSpeedKnots: 480) == 6)
        #expect(FlyoverPolicy.duration(groundSpeedKnots: 240) == 10)
        #expect(FlyoverPolicy.duration(groundSpeedKnots: 90) == 12.5)
        #expect(FlyoverPolicy.duration(groundSpeedKnots: 20) == 13)
        #expect(FlyoverPolicy.duration(groundSpeedKnots: 900) == 6)
        #expect(FlyoverPolicy.duration(groundSpeedKnots: nil) == 10)
    }

    @Test func directionFollowsHeading() {
        #expect(FlyoverPolicy.fliesLeftToRight(heading: 90))
        #expect(FlyoverPolicy.fliesLeftToRight(heading: 45))
        #expect(!FlyoverPolicy.fliesLeftToRight(heading: 270))
        #expect(!FlyoverPolicy.fliesLeftToRight(heading: 312))
        #expect(FlyoverPolicy.fliesLeftToRight(heading: 0))
        #expect(FlyoverPolicy.fliesLeftToRight(heading: nil))
        #expect(!FlyoverPolicy.fliesLeftToRight(heading: -90))
    }
}

@Suite struct AirlineTests {
    @Test func tableIsBigAndConsistent() {
        #expect(Airline.all.count >= 40)
        #expect(Set(Airline.all.map(\.icao)).count == Airline.all.count)
        for airline in Airline.all {
            #expect(airline.icao.count == 3, "\(airline.icao)")
            #expect(airline.iata.count == 2, "\(airline.icao)")
            #expect(Airline.find(icao: airline.icao.lowercased()) == airline)
        }
        for code in ["UAL", "DAL", "AAL", "SWA", "ASA", "JBU", "FDX", "UPS"] {
            #expect(Airline.find(icao: code) != nil, "\(code)")
        }
        #expect(Airline.find(icao: "FDX")?.cargo == true)
        #expect(Airline.find(icao: "UAL")?.cargo == false)
        #expect(Airline.find(icao: "ZZZ") == nil)
    }

    @Test func parsesAirlineCallsigns() {
        let united = Callsign("UAL512  ")
        #expect(united.raw == "UAL512")
        #expect(united.airlineCode == "UAL")
        #expect(united.number == "512")
        #expect(united.airline?.name == "United")
        #expect(united.flightNumber == "UA512")

        #expect(Callsign("SWA3231").flightNumber == "WN3231")
        #expect(Callsign("JBU1942").flightNumber == "B61942")
        #expect(Callsign("DAL0042").flightNumber == "DL42")
        #expect(Callsign("BAW28K").flightNumber == "BA28K")
        #expect(Callsign("fdx1401").flightNumber == "FX1401")
    }

    @Test func unknownAirlinesAndPrivateCallsigns() {
        // An airline-shaped callsign we have no entry for is left alone.
        let unknown = Callsign("XYZ123")
        #expect(unknown.airlineCode == "XYZ")
        #expect(unknown.airline == nil)
        #expect(unknown.flightNumber == "XYZ123")
        // Tail numbers used as callsigns have no airline.
        for text in ["N628TS", "N172SP", "GTNEI", "", "UAL", "UALX12", "REACH", "N1"] {
            #expect(Callsign(text).airlineCode == nil, "\(text)")
            #expect(Callsign(text).flightNumber == text)
        }
    }

    @Test func privateLiveryIsStableAndVaried() {
        let a = Livery.privateAircraft(tailNumber: "N628TS")
        #expect(a == Livery.privateAircraft(tailNumber: " n628ts "))
        #expect(a.tail == a.accent)
        #expect(a.body.luminance > 0.9)
        // Known value: guards against the hash changing between releases.
        #expect(a.accent == Livery.privateAircraft(tailNumber: "N628TS").accent)
        let accents = Set(["N628TS", "N172SP", "N1KE", "N383FR", "N8880G", "N100CJ"].map {
            Livery.privateAircraft(tailNumber: $0).accent
        })
        #expect(accents.count >= 5)
    }

    @Test func colorHelpers() {
        #expect(RGB(0xFF8000) == RGB(r: 1, g: 128.0 / 255, b: 0))
        #expect(RGB(0x000000).mixed(with: .white, 0.5) == RGB(r: 0.5, g: 0.5, b: 0.5))
        let red = RGB(hue: 0, saturation: 1, lightness: 0.5)
        #expect(close(red.r, 1, within: 1e-9) && close(red.g, 0, within: 1e-9) && close(red.b, 0, within: 1e-9))
        let green = RGB(hue: 120, saturation: 1, lightness: 0.5)
        #expect(close(green.g, 1, within: 1e-9) && close(green.r, 0, within: 1e-9))
    }
}

@Suite struct FuselageLabelTests {
    private func record(_ owner: String, _ type: String) -> RegistryRecord {
        RegistryRecord(nNumber: "N628TS", owner: owner, registrantType: type, city: "", state: "",
                       manufacturer: "", model: "", year: "")
    }

    @Test func airlinesCarryNoText() {
        #expect(FuselageLabel.text(isAirline: true, record: record("UNITED AIRLINES INC", "Corporation"), tailNumber: "N37502") == nil)
    }

    @Test func companiesShowTheirName() {
        #expect(FuselageLabel.text(isAirline: false, record: record("FALCON LANDING LLC", "LLC"), tailNumber: "N628TS") == "FALCON LANDING")
        #expect(FuselageLabel.text(isAirline: false, record: record("BANK OF UTAH TRUSTEE", "Corporation"), tailNumber: "N1") == "BANK OF UTAH")
        #expect(FuselageLabel.text(isAirline: false, record: record("STATE OF CALIFORNIA", "Government"), tailNumber: "N1") == "STATE OF CALIFORNIA")
    }

    @Test func longNamesAreCutAtAWord() {
        let label = FuselageLabel.text(
            isAirline: false,
            record: record("TVPX AIRCRAFT SOLUTIONS INC TRUSTEE", "Corporation"),
            tailNumber: "N1KE"
        )
        #expect(label == "TVPX AIRCRAFT…")
        #expect((label ?? "").count <= FuselageLabel.maxLength)
        #expect(FuselageLabel.clean(owner: "SUPERCALIFRAGILISTICEXPIALIDOCIOUS HOLDINGS LLC") == "SUPERCALIFRAGILISTICE…")
    }

    @Test func individualsNeverShowTheirName() {
        #expect(FuselageLabel.text(isAirline: false, record: record("BENE MARY D", "Individual"), tailNumber: "N100") == "N100")
        // Co-owners and partnerships can be people too.
        #expect(FuselageLabel.text(isAirline: false, record: record("SMITH JOHN A", "Co-owned"), tailNumber: "N55") == "N55")
        #expect(FuselageLabel.text(isAirline: false, record: record("JONES & JONES", "Partnership"), tailNumber: "N56") == "N56")
        // Even when an individual's name contains a company-like word.
        #expect(FuselageLabel.text(isAirline: false, record: record("TRUST JOHN INC", "Individual"), tailNumber: "N57") == "N57")
        // No tail number passed: fall back to the registry's, never the name.
        #expect(FuselageLabel.text(isAirline: false, record: record("BENE MARY D", "Individual"), tailNumber: nil) == "N628TS")
    }

    @Test func noRecord() {
        #expect(FuselageLabel.text(isAirline: false, record: nil, tailNumber: "g-tnei") == "G-TNEI")
        #expect(FuselageLabel.text(isAirline: false, record: nil, tailNumber: nil) == nil)
        #expect(FuselageLabel.text(isAirline: false, record: record("", "LLC"), tailNumber: "N9") == "N9")
    }
}

@Suite struct SunTests {
    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let newYork = Coordinate(latitude: 40.7128, longitude: -74.0060)
    private let london = Coordinate(latitude: 51.5074, longitude: -0.1278)

    @Test func sunIsOverheadAtTheEquatorOnTheEquinox() {
        // 20 March 2024, about 12:07 UTC at 0 N 0 E.
        let elevation = Sun.elevation(at: Coordinate(latitude: 0, longitude: 0), date: utc(2024, 3, 20, 12, 7))
        #expect(elevation > 89)
    }

    @Test func newYorkSummerSolstice() throws {
        // Published times for 20 June 2024: sunrise 5:25 am, sunset 8:30 pm EDT.
        let times = try #require(Sun.sunriseAndSunset(at: newYork, on: utc(2024, 6, 20, 16, 0)))
        #expect(abs(times.sunrise.timeIntervalSince(utc(2024, 6, 20, 9, 25))) < 300)
        #expect(abs(times.sunset.timeIntervalSince(utc(2024, 6, 21, 0, 30))) < 300)
    }

    @Test func londonWinterSolstice() throws {
        // Published times for 21 December 2024: sunrise 8:04, sunset 15:53 GMT.
        let times = try #require(Sun.sunriseAndSunset(at: london, on: utc(2024, 12, 21, 12, 0)))
        #expect(abs(times.sunrise.timeIntervalSince(utc(2024, 12, 21, 8, 4))) < 300)
        #expect(abs(times.sunset.timeIntervalSince(utc(2024, 12, 21, 15, 53))) < 300)
    }

    @Test func polarNightAndMidnightSun() {
        let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
        #expect(Sun.sunriseAndSunset(at: tromso, on: utc(2024, 12, 21, 12, 0)) == nil)
        #expect(Sun.sunriseAndSunset(at: tromso, on: utc(2024, 6, 21, 12, 0)) == nil)
    }

    @Test func dayDuskAndNight() {
        // New York, 20 June 2024: 1 pm, just after sunset, and 1 am local.
        #expect(Sun.phase(at: newYork, date: utc(2024, 6, 20, 17, 0)) == .day)
        #expect(Sun.phase(at: newYork, date: utc(2024, 6, 21, 0, 45)) == .dusk)
        #expect(Sun.phase(at: newYork, date: utc(2024, 6, 21, 5, 0)) == .night)
        #expect(Sun.darkness(at: newYork, date: utc(2024, 6, 20, 17, 0)) == 0)
        #expect(Sun.darkness(at: newYork, date: utc(2024, 6, 21, 5, 0)) == 1)
    }

    @Test func darknessRampsThroughTwilight() {
        #expect(Sun.darkness(elevation: 30) == 0)
        #expect(Sun.darkness(elevation: 2) == 0)
        #expect(close(Sun.darkness(elevation: -2.5), 0.5, within: 1e-9))
        #expect(Sun.darkness(elevation: -7) == 1)
        #expect(Sun.darkness(elevation: -40) == 1)
        #expect(Sun.phase(darkness: 0) == .day)
        #expect(Sun.phase(darkness: 0.4) == .dusk)
        #expect(Sun.phase(darkness: 1) == .night)
    }
}

@Suite struct RouteTests {
    private let sfo = RouteAirport(icao: "KSFO", iata: "SFO", name: "San Francisco International Airport",
                                   location: "San Francisco", lat: 37.618999, lon: -122.375)
    private let ewr = RouteAirport(icao: "KEWR", iata: "EWR", name: "Newark Liberty International Airport",
                                   location: "Newark", lat: 40.692501, lon: -74.168701)
    private let ord = RouteAirport(icao: "KORD", iata: "ORD", name: "Chicago O'Hare International Airport",
                                   location: "Chicago", lat: 41.9786, lon: -87.9048)

    private var route: FlightRoute { FlightRoute(callsign: "UAL512", airports: [sfo, ewr]) }

    @Test func acceptsAnAircraftOnTheRoute() {
        // Climbing out of San Francisco, heading any direction.
        #expect(route.plausibleLeg(position: Coordinate(latitude: 37.70, longitude: -122.30), track: 290) != nil)
        // Over Nebraska, heading east.
        let leg = route.plausibleLeg(position: Coordinate(latitude: 41.0, longitude: -100.0), track: 85)
        #expect(leg?.origin == sfo)
        #expect(leg?.destination == ewr)
        // On approach to Newark from the south-west.
        #expect(route.plausibleLeg(position: Coordinate(latitude: 40.55, longitude: -74.26), track: 20) != nil)
        // No track reported: position alone decides.
        #expect(route.plausibleLeg(position: Coordinate(latitude: 41.0, longitude: -100.0), track: nil) != nil)
    }

    @Test func rejectsAnAircraftThatDoesNotFit() {
        // Over Nebraska but flying west: this is the return flight, or a reused callsign.
        #expect(route.plausibleLeg(position: Coordinate(latitude: 41.0, longitude: -100.0), track: 265) == nil)
        // Nowhere near the route: Miami.
        #expect(route.plausibleLeg(position: Coordinate(latitude: 25.79, longitude: -80.29), track: 90) == nil)
        // London.
        #expect(route.plausibleLeg(position: Coordinate(latitude: 51.47, longitude: -0.45), track: 270) == nil)
        // The API itself says the route is not plausible.
        let flagged = FlightRoute(callsign: "UAL512", airports: [sfo, ewr], apiPlausible: false)
        #expect(flagged.plausibleLeg(position: Coordinate(latitude: 41.0, longitude: -100.0), track: 85) == nil)
    }

    @Test func picksTheRightLegOfAMultiStopRoute() {
        let twoStops = FlightRoute(callsign: "UAL512", airports: [sfo, ord, ewr])
        let first = twoStops.plausibleLeg(position: Coordinate(latitude: 41.2, longitude: -105.0), track: 80)
        #expect(first?.destination == ord)
        let second = twoStops.plausibleLeg(position: Coordinate(latitude: 41.3, longitude: -80.0), track: 95)
        #expect(second?.origin == ord)
        #expect(second?.destination == ewr)
    }

    @Test func bannerText() {
        let here = Coordinate(latitude: 41.0, longitude: -100.0)
        #expect(BannerText.text(callsign: "UAL512 ", tailNumber: "N37502", route: route, position: here, track: 85)
                == "UA512 · San Francisco → Newark")
        // Airline flight, no route: no banner.
        #expect(BannerText.text(callsign: "UAL512", tailNumber: "N37502", route: nil, position: here, track: 85) == nil)
        // Airline flight, route that does not fit: no banner rather than a wrong one.
        #expect(BannerText.text(callsign: "UAL512", tailNumber: "N37502", route: route, position: here, track: 265) == nil)
        // Private flights show their callsign, or failing that the tail number.
        #expect(BannerText.text(callsign: "N628TS", tailNumber: "N628TS", route: nil, position: here, track: 85) == "N628TS")
        #expect(BannerText.text(callsign: nil, tailNumber: "n172sp", route: nil, position: here, track: nil) == "N172SP")
        #expect(BannerText.text(callsign: "  ", tailNumber: nil, route: nil, position: nil, track: nil) == nil)
    }

    @Test func airportWithoutACityFallsBackToItsCode() {
        let bare = RouteAirport(icao: "KXYZ", iata: "XYZ", name: nil, location: " ", lat: 1, lon: 1)
        #expect(bare.displayName == "XYZ")
        #expect(sfo.displayName == "San Francisco")
    }

    @Test func emptyOrOddResponsesGiveNoRoutes() {
        // What the endpoint returned on 2026-11-23: HTTP 201 with an empty body.
        #expect(FlightRoute.decodeList(Data()).isEmpty)
        #expect(FlightRoute.decodeList(Data("null".utf8)).isEmpty)
        #expect(FlightRoute.decodeList(Data("[]".utf8)).isEmpty)
        #expect(FlightRoute.decodeList(Data("rate limit exceeded".utf8)).isEmpty)
        #expect(FlightRoute.decodeList(Data(#"[{"callsign": "UAL512", "_airports": []}]"#.utf8)).isEmpty)
    }

    @Test func decodesTheAssumedResponseShape() {
        // Not captured live (the endpoint returned nothing): a response in the
        // shape the client expects, with airport objects exactly as
        // GET /api/0/airport/KSFO returns them.
        let json = """
        [{"callsign": "UAL512", "plausible": true, "airport_codes": "KSFO-KEWR", "_airports": [
          {"alt_feet": 13.0, "alt_meters": 3.96, "countryiso2": "US", "iata": "SFO", "icao": "KSFO",
           "lat": 37.618999, "location": "San Francisco", "lon": -122.375, "name": "San Francisco International Airport"},
          {"alt_feet": 18.0, "alt_meters": 5.49, "countryiso2": "US", "iata": "EWR", "icao": "KEWR",
           "lat": 40.692501, "location": "Newark", "lon": -74.168701, "name": "Newark Liberty International Airport"}
        ]}, {"callsign": "N628TS", "_airports": null}]
        """
        let routes = FlightRoute.decodeList(Data(json.utf8))
        #expect(routes.count == 1)
        #expect(routes.first?.callsign == "UAL512")
        #expect(routes.first?.airports == [sfo, ewr])
        #expect(routes.first?.apiPlausible == true)
    }
}

@Suite struct FlyoverGateTests {
    @Test func quietHoursSameDay() {
        let lunch = QuietHours(start: 12 * 60, end: 13 * 60)
        #expect(lunch.contains(minuteOfDay: 12 * 60))
        #expect(lunch.contains(minuteOfDay: 12 * 60 + 59))
        #expect(!lunch.contains(minuteOfDay: 13 * 60))
        #expect(!lunch.contains(minuteOfDay: 11 * 60 + 59))
    }

    @Test func quietHoursPastMidnight() {
        let night = QuietHours(start: 22 * 60, end: 7 * 60)
        #expect(night.contains(minuteOfDay: 23 * 60))
        #expect(night.contains(minuteOfDay: 0))
        #expect(night.contains(minuteOfDay: 6 * 60 + 59))
        #expect(!night.contains(minuteOfDay: 7 * 60))
        #expect(!night.contains(minuteOfDay: 12 * 60))
        #expect(night.contains(minuteOfDay: 22 * 60))
        // An empty range never matches.
        #expect(!QuietHours(start: 480, end: 480).contains(minuteOfDay: 480))
    }

    @Test func minuteOfDayFromADate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 22, minute: 15))!
        #expect(QuietHours.minuteOfDay(for: date, calendar: calendar) == 22 * 60 + 15)
    }

    @Test func blocksInPriorityOrder() {
        let clear = FlyoverConditions(minuteOfDay: 12 * 60, focusOn: false, fullScreen: false, screenMirrored: false)
        var rules = FlyoverRules()
        #expect(rules.block(clear) == nil)

        #expect(rules.block(FlyoverConditions(minuteOfDay: 720, focusOn: true, fullScreen: false, screenMirrored: false)) == .focus)
        #expect(rules.block(FlyoverConditions(minuteOfDay: 720, focusOn: false, fullScreen: true, screenMirrored: false)) == .fullScreen)
        #expect(rules.block(FlyoverConditions(minuteOfDay: 720, focusOn: false, fullScreen: false, screenMirrored: true)) == .screenMirrored)
        // Focus state unknown: do not block on a guess.
        #expect(rules.block(FlyoverConditions(minuteOfDay: 720, focusOn: nil, fullScreen: false, screenMirrored: false)) == nil)

        rules.quietHoursEnabled = true
        #expect(rules.block(FlyoverConditions(minuteOfDay: 23 * 60, focusOn: true, fullScreen: true, screenMirrored: true)) == .quietHours)
        #expect(rules.block(clear) == nil)

        rules.paused = true
        #expect(rules.block(clear) == .paused)
    }

    @Test func eachCheckCanBeSwitchedOff() {
        var rules = FlyoverRules()
        rules.respectFocus = false
        rules.respectFullScreen = false
        rules.respectMirroring = false
        #expect(rules.block(FlyoverConditions(minuteOfDay: 0, focusOn: true, fullScreen: true, screenMirrored: true)) == nil)
    }

    @Test func detectsAFullScreenWindow() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
        let full = FullScreenDetector.Window(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let normal = FullScreenDetector.Window(ownerPID: 42, layer: 0, bounds: CGRect(x: 100, y: 80, width: 900, height: 700))
        let menuBarHeight = FullScreenDetector.Window(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1512, height: 949))
        let overlay = FullScreenDetector.Window(ownerPID: 42, layer: 25, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let onSecond = FullScreenDetector.Window(ownerPID: 42, layer: 0, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080))

        #expect(FullScreenDetector.isFullScreen(windows: [normal, full], frontmostPID: 42, screens: screens))
        #expect(FullScreenDetector.isFullScreen(windows: [onSecond], frontmostPID: 42, screens: screens))
        // A maximized window below the menu bar is not full screen.
        #expect(!FullScreenDetector.isFullScreen(windows: [normal, menuBarHeight], frontmostPID: 42, screens: screens))
        // Another app's full-screen window does not count.
        #expect(!FullScreenDetector.isFullScreen(windows: [full], frontmostPID: 7, screens: screens))
        // Overlays (not layer 0) do not count.
        #expect(!FullScreenDetector.isFullScreen(windows: [overlay], frontmostPID: 42, screens: screens))
        #expect(!FullScreenDetector.isFullScreen(windows: [], frontmostPID: 42, screens: screens))
    }
}
