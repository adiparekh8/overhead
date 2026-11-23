import Foundation

/// An airborne aircraft with its position relative to the observer.
public struct NearbyAircraft: Identifiable, Equatable, Sendable {
    public let aircraft: ADSBAircraft
    /// Distance along the ground, nautical miles.
    public let groundNM: Double
    /// True bearing from the observer to the aircraft, degrees.
    public let bearing: Double
    /// Altitude in feet (as reported, above sea level).
    public let altitudeFeet: Double
    /// Straight-line distance, nautical miles.
    public let slantNM: Double

    public var id: String { aircraft.hex }
}

public enum OverheadPicker {
    /// Positions older than this many seconds are ignored.
    public static let maxPositionAge = 60.0

    /// Airborne aircraft within `radiusNM` of `observer`, closest first by
    /// straight-line (slant) distance. The first element is "overhead".
    ///
    /// Left out: aircraft on the ground, aircraft with no position or no
    /// altitude, and positions that are stale.
    public static func rank(
        _ aircraft: [ADSBAircraft],
        from observer: Coordinate,
        radiusNM: Double
    ) -> [NearbyAircraft] {
        var seen = Set<String>()
        var result: [NearbyAircraft] = []
        for plane in aircraft {
            guard !plane.isOnGround,
                  let altitude = plane.altitudeFeet,
                  let position = plane.coordinate,
                  (plane.seenPos ?? 0) <= maxPositionAge,
                  seen.insert(plane.hex).inserted
            else { continue }
            let ground = Geo.groundDistanceNM(from: observer, to: position)
            guard ground <= radiusNM else { continue }
            result.append(NearbyAircraft(
                aircraft: plane,
                groundNM: ground,
                bearing: Geo.bearingDegrees(from: observer, to: position),
                altitudeFeet: altitude,
                slantNM: Geo.slantDistanceNM(groundNM: ground, altitudeFeet: altitude)
            ))
        }
        return result.sorted {
            $0.slantNM != $1.slantNM ? $0.slantNM < $1.slantNM : $0.aircraft.hex < $1.aircraft.hex
        }
    }

    /// Radius to ask the API for. The request uses a rounded location (see
    /// `Coordinate.coarse`), so ask for slightly more and trim locally.
    public static func requestRadiusNM(for radiusNM: Double) -> Int {
        min(250, max(1, Int(radiusNM.rounded(.up)) + 1))
    }
}
