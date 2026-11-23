import Foundation
import OverheadCore

/// Talks to the ADSB.lol v2 API. One GET per call, nothing else.
/// Docs: https://api.adsb.lol/docs
struct ADSBClient {
    struct Result {
        let response: ADSBResponse
        let rateLimit: RateLimit?
    }

    enum Failure: Error {
        /// HTTP 429. `retryAfter` comes from the `Retry-After` header.
        case rateLimited(retryAfter: TimeInterval?)
        case http(Int)
        case network(String)
        case badResponse

        var message: String {
            switch self {
            case .rateLimited: return "ADSB.lol request limit reached"
            case .http(let code): return "ADSB.lol returned an error (\(code))"
            case .network(let text): return text
            case .badResponse: return "ADSB.lol sent an unreadable response"
            }
        }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["User-Agent": "Overhead/1.0 (macOS menu bar app)"]
        return URLSession(configuration: config)
    }()

    /// GET /v2/point/{lat}/{lon}/{radius}: aircraft within `radiusNM`
    /// nautical miles of a point. The radius must be a whole number, 0-250.
    func aircraft(near point: Coordinate, radiusNM: Int) async throws -> Result {
        let path = String(format: "/v2/point/%.2f/%.2f/%d", point.latitude, point.longitude, radiusNM)
        guard let url = URL(string: "https://api.adsb.lol" + path) else { throw Failure.badResponse }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Failure.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }

        if http.statusCode == 429 {
            let retry = headers.first { $0.key.lowercased() == "retry-after" }
                .flatMap { TimeInterval($0.value.trimmingCharacters(in: .whitespaces)) }
            throw Failure.rateLimited(retryAfter: retry)
        }
        guard http.statusCode == 200 else { throw Failure.http(http.statusCode) }
        guard let decoded = try? ADSBResponse.decode(data) else { throw Failure.badResponse }
        return Result(response: decoded, rateLimit: RateLimit(headers: headers))
    }
}
