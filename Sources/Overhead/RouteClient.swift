import Foundation
import OverheadCore

/// Looks up a flight's route with ADSB.lol's routeset endpoint.
///
///     POST https://api.adsb.lol/api/0/routeset
///     {"planes": [{"callsign": "UAL512", "lat": 37.7, "lng": -122.3}]}
///
/// The docs mark this path as free (not counted against the request quota).
/// Results, including "no route", are cached per callsign.
@MainActor
final class RouteClient {
    private struct Entry {
        let route: FlightRoute?
        let fetched: Date
    }

    private var cache: [String: Entry] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.httpAdditionalHeaders = ["User-Agent": "Overhead/1.0 (macOS menu bar app)"]
        return URLSession(configuration: config)
    }()

    /// A found route is kept for six hours, a miss for thirty minutes.
    private func isFresh(_ entry: Entry) -> Bool {
        Date().timeIntervalSince(entry.fetched) < (entry.route == nil ? 30 * 60 : 6 * 3600)
    }

    /// The route for an airline callsign, or nil. Never throws: any failure
    /// means "no route", and so no banner.
    func route(callsign: String, position: Coordinate) async -> FlightRoute? {
        let key = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard Callsign(key).airlineCode != nil else { return nil }
        if let entry = cache[key], isFresh(entry) { return entry.route }

        let found = await fetch(callsign: key, position: position)
        cache[key] = Entry(route: found, fetched: Date())
        cache = cache.filter { isFresh($0.value) }
        return found
    }

    private func fetch(callsign: String, position: Coordinate) async -> FlightRoute? {
        guard let url = URL(string: "https://api.adsb.lol/api/0/routeset") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let coarse = position.coarse
        let body: [String: Any] = ["planes": [["callsign": callsign, "lat": coarse.latitude, "lng": coarse.longitude]]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return FlightRoute.decodeList(data).first { $0.callsign.uppercased() == callsign }
    }
}
