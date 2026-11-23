import Foundation

public struct Coordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    /// Rounded to two decimal places (about 1 km). Used for the API request
    /// so the exact location never leaves the Mac.
    public var coarse: Coordinate {
        Coordinate(
            latitude: (latitude * 100).rounded() / 100,
            longitude: (longitude * 100).rounded() / 100
        )
    }
}

public enum Geo {
    /// Mean Earth radius in nautical miles.
    public static let earthRadiusNM = 3440.065
    public static let feetPerNM = 6076.11549
    public static let metersPerFoot = 0.3048
    public static let kmPerNM = 1.852
    public static let milesPerNM = 1.15077945

    /// Great-circle distance along the ground, in nautical miles (haversine).
    public static func groundDistanceNM(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusNM * asin(min(1, sqrt(h)))
    }

    /// Initial true bearing from `a` to `b`, in degrees clockwise from north (0..<360).
    public static func bearingDegrees(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Straight-line distance to an aircraft, combining ground distance and
    /// altitude, in nautical miles. At these ranges the Earth's curvature is
    /// negligible, so this is a right triangle.
    public static func slantDistanceNM(groundNM: Double, altitudeFeet: Double) -> Double {
        let up = altitudeFeet / feetPerNM
        return (groundNM * groundNM + up * up).squareRoot()
    }
}
