import Foundation

/// One airport on a route. Field names match ADSB.lol's airport objects,
/// as returned by GET /api/0/airport/{icao}.
public struct RouteAirport: Decodable, Equatable, Sendable {
    public let icao: String?
    public let iata: String?
    public let name: String?
    /// The city the airport serves: "San Francisco".
    public let location: String?
    public let lat: Double
    public let lon: Double

    public init(icao: String?, iata: String?, name: String?, location: String?, lat: Double, lon: Double) {
        self.icao = icao; self.iata = iata; self.name = name; self.location = location
        self.lat = lat; self.lon = lon
    }

    public var coordinate: Coordinate { Coordinate(latitude: lat, longitude: lon) }

    /// City name, or the airport code when the city is missing.
    public var displayName: String {
        if let city = location?.trimmingCharacters(in: .whitespaces), !city.isEmpty { return city }
        return iata ?? icao ?? name ?? "?"
    }
}

/// A route for one callsign from POST /api/0/routeset.
///
/// NOTE: the documentation gives the request body but describes the response
/// only as "string", and on 2026-11-23 the endpoint answered every request
/// with HTTP 201 and an empty body. The fields below (`callsign`, `_airports`,
/// `plausible`) are the shape this endpoint is known to have used; they have
/// not been confirmed against a live response. Anything that does not decode
/// is treated as "no route".
public struct FlightRoute: Equatable, Sendable {
    public let callsign: String
    public let airports: [RouteAirport]
    /// The API's own verdict, when it gives one.
    public let apiPlausible: Bool?

    public init(callsign: String, airports: [RouteAirport], apiPlausible: Bool? = nil) {
        self.callsign = callsign; self.airports = airports; self.apiPlausible = apiPlausible
    }

    /// Decodes a routeset response. An empty body, or anything that is not
    /// a list of routes, gives an empty list.
    public static func decodeList(_ data: Data) -> [FlightRoute] {
        guard !data.isEmpty, let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.compactMap { entry in
            guard let callsign = entry.callsign, let airports = entry.airports, airports.count >= 2 else { return nil }
            return FlightRoute(callsign: callsign, airports: airports, apiPlausible: entry.plausible)
        }
    }

    private struct Entry: Decodable {
        let callsign: String?
        let airports: [RouteAirport]?
        let plausible: Bool?

        enum CodingKeys: String, CodingKey {
            case callsign, plausible
            case airports = "_airports"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            callsign = try? c.decodeIfPresent(String.self, forKey: .callsign)
            airports = try? c.decodeIfPresent([RouteAirport].self, forKey: .airports)
            if let flag = try? c.decodeIfPresent(Bool.self, forKey: .plausible) {
                plausible = flag
            } else if let number = try? c.decodeIfPresent(Int.self, forKey: .plausible) {
                plausible = number != 0
            } else {
                plausible = nil
            }
        }
    }

    /// One leg of the route: where the aircraft is coming from and going to.
    public struct Leg: Equatable, Sendable {
        public let origin: RouteAirport
        public let destination: RouteAirport
    }

    /// The leg the aircraft is plausibly flying right now, or nil.
    ///
    /// Route data is a best guess keyed on the callsign, and callsigns are
    /// reused. A leg is accepted only when the aircraft is roughly between
    /// the two airports and, once clear of both, heading toward the
    /// destination. A wrong banner is worse than none.
    public func plausibleLeg(position: Coordinate, track: Double?) -> Leg? {
        if apiPlausible == false { return nil }
        for (origin, destination) in zip(airports, airports.dropFirst()) {
            if Self.fits(origin: origin.coordinate, destination: destination.coordinate,
                         position: position, track: track) {
                return Leg(origin: origin, destination: destination)
            }
        }
        return nil
    }

    static func fits(origin: Coordinate, destination: Coordinate, position: Coordinate, track: Double?) -> Bool {
        guard origin.isValid, destination.isValid else { return false }
        let length = Geo.groundDistanceNM(from: origin, to: destination)
        guard length >= 5 else { return false }
        let fromOrigin = Geo.groundDistanceNM(from: origin, to: position)
        let toDestination = Geo.groundDistanceNM(from: position, to: destination)

        // Flying origin -> here -> destination must not be much longer than
        // flying direct: allow 20% extra, and at least 30 nm for vectoring.
        let detour = fromOrigin + toDestination - length
        guard detour <= max(30, length * 0.2) else { return false }

        // Near either airport aircraft turn in all directions. In between,
        // the aircraft should be pointing roughly at the destination.
        if let track, fromOrigin > 30, toDestination > 30 {
            let wanted = Geo.bearingDegrees(from: position, to: destination)
            var difference = abs(wanted - track).truncatingRemainder(dividingBy: 360)
            if difference > 180 { difference = 360 - difference }
            guard difference <= 100 else { return false }
        }
        return true
    }
}

public enum BannerText {
    /// "UA512 · San Francisco → Newark"
    public static func route(callsign: Callsign, leg: FlightRoute.Leg) -> String {
        "\(callsign.flightNumber) · \(leg.origin.displayName) → \(leg.destination.displayName)"
    }

    /// What the towed banner says, or nil for no banner.
    ///
    /// - A route that fits the aircraft's position: flight number and cities.
    /// - An airline flight with no usable route: no banner.
    /// - A private flight: its callsign, or its tail number.
    public static func text(
        callsign: String?,
        tailNumber: String?,
        route: FlightRoute?,
        position: Coordinate?,
        track: Double?
    ) -> String? {
        let parsed = callsign.map(Callsign.init)
        if let parsed, let route, let position,
           let leg = route.plausibleLeg(position: position, track: track) {
            return self.route(callsign: parsed, leg: leg)
        }
        if parsed?.airlineCode != nil { return nil }
        if let raw = parsed?.raw, !raw.isEmpty { return raw }
        let tail = tailNumber?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        return tail.isEmpty ? nil : tail
    }
}
