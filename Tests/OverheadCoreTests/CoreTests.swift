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
        #expect(AircraftShape.classify(typeCode: "A388", category: "A5") == .superJumbo)
        #expect(AircraftShape.classify(typeCode: "B748", category: "A5") == .jumbo)
        #expect(AircraftShape.classify(typeCode: "A343", category: "A5") == .quadWidebody)
        #expect(AircraftShape.classify(typeCode: "B77W", category: "A5") == .widebody)
        #expect(AircraftShape.classify(typeCode: "A359", category: nil) == .widebody)
        #expect(AircraftShape.classify(typeCode: "A310", category: nil) == .widebody)
        #expect(AircraftShape.classify(typeCode: "A319", category: nil) == .narrowbody)
        #expect(AircraftShape.classify(typeCode: "B38M", category: "A3") == .narrowbody)
        #expect(AircraftShape.classify(typeCode: "A21N", category: "A3") == .narrowbody)
        #expect(AircraftShape.classify(typeCode: "E75L", category: "A3") == .narrowbody)
        #expect(AircraftShape.classify(typeCode: "CRJ9", category: "A3") == .rearEngineJet)
        #expect(AircraftShape.classify(typeCode: "E145", category: nil) == .rearEngineJet)
        #expect(AircraftShape.classify(typeCode: "GLF6", category: "A2") == .businessJet)
        #expect(AircraftShape.classify(typeCode: "C56X", category: nil) == .businessJet)
        #expect(AircraftShape.classify(typeCode: "C25B", category: nil) == .businessJet)
        #expect(AircraftShape.classify(typeCode: "DH8D", category: "A3") == .turboprop)
        #expect(AircraftShape.classify(typeCode: "C208", category: "A1") == .turboprop)
        #expect(AircraftShape.classify(typeCode: "PC12", category: nil) == .turboprop)
        #expect(AircraftShape.classify(typeCode: "C172", category: "A1") == .pistonSingle)
        #expect(AircraftShape.classify(typeCode: "SR22", category: nil) == .pistonSingle)
        #expect(AircraftShape.classify(typeCode: "P28A", category: nil) == .pistonSingle)
        #expect(AircraftShape.classify(typeCode: "R44", category: "A7") == .helicopter)
        #expect(AircraftShape.classify(typeCode: "EC35", category: nil) == .helicopter)
        #expect(AircraftShape.classify(typeCode: "b738 ", category: nil) == .narrowbody)
    }

    @Test func fallsBackToCategory() {
        #expect(AircraftShape.classify(typeCode: nil, category: "A7") == .helicopter)
        #expect(AircraftShape.classify(typeCode: "ZZZZ", category: "A1") == .pistonSingle)
        #expect(AircraftShape.classify(typeCode: nil, category: "A2") == .businessJet)
        #expect(AircraftShape.classify(typeCode: "", category: "A5") == .widebody)
        #expect(AircraftShape.classify(typeCode: nil, category: nil) == .narrowbody)
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
