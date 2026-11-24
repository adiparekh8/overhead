import Foundation

/// Where the sun is, from the date and a location. No network, no system
/// appearance setting: just astronomy (the low-precision formulas from the
/// Astronomical Almanac, good to a few hundredths of a degree).
public enum Sun {
    public enum Phase: Equatable, Sendable {
        case day, dusk, night
    }

    /// The sun's height above the horizon in degrees. Negative after sunset.
    public static func elevation(at place: Coordinate, date: Date) -> Double {
        let rad = Double.pi / 180
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let n = julianDay - 2_451_545.0

        let meanLongitude = normalize(280.460 + 0.9856474 * n)
        let meanAnomaly = normalize(357.528 + 0.9856003 * n) * rad
        let eclipticLongitude = (meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly)) * rad
        let obliquity = (23.439 - 0.0000004 * n) * rad

        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))

        let greenwichSiderealHours = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
        let localSidereal = (greenwichSiderealHours * 15 + place.longitude) * rad
        let hourAngle = localSidereal - rightAscension

        let latitude = place.latitude * rad
        let sine = sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)
        return asin(min(1, max(-1, sine))) / rad
    }

    private static func normalize(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The sun's upper edge touches the horizon at this elevation
    /// (refraction plus the sun's radius).
    public static let horizonElevation = -0.833

    /// How dark the sky is, 0 (full day) to 1 (night). It starts rising when
    /// the sun is 2 degrees up and reaches 1 at 7 degrees below the horizon,
    /// just past the end of civil twilight.
    public static func darkness(elevation: Double) -> Double {
        min(1, max(0, (2 - elevation) / 9))
    }

    public static func darkness(at place: Coordinate, date: Date) -> Double {
        darkness(elevation: elevation(at: place, date: date))
    }

    public static func phase(darkness: Double) -> Phase {
        if darkness <= 0 { return .day }
        if darkness >= 1 { return .night }
        return .dusk
    }

    public static func phase(at place: Coordinate, date: Date) -> Phase {
        phase(darkness: darkness(at: place, date: date))
    }

    /// Sunrise and sunset nearest to `date` (the ones either side of that
    /// day's solar noon). Nil where the sun does not rise or does not set.
    public static func sunriseAndSunset(at place: Coordinate, on date: Date) -> (sunrise: Date, sunset: Date)? {
        // Solar noon in UTC is 12:00 shifted by four minutes per degree of longitude.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // Use the local solar day that contains `date`.
        let solarOffset = place.longitude / 15 * 3600
        let localDayStart = utc.startOfDay(for: date.addingTimeInterval(solarOffset))
        let noon = localDayStart.addingTimeInterval(12 * 3600 - solarOffset)

        func height(_ offset: TimeInterval) -> Double {
            elevation(at: place, date: noon.addingTimeInterval(offset)) - horizonElevation
        }
        guard height(0) > 0, height(-12 * 3600) < 0, height(12 * 3600) < 0 else { return nil }

        // Bisect for the crossing between `below` (sun down) and `above` (sun up).
        func crossing(below: TimeInterval, above: TimeInterval) -> Date {
            var low = below, high = above
            for _ in 0..<40 {
                let middle = (low + high) / 2
                if height(middle) < 0 { low = middle } else { high = middle }
            }
            return noon.addingTimeInterval((low + high) / 2)
        }
        return (crossing(below: -12 * 3600, above: 0), crossing(below: 12 * 3600, above: 0))
    }
}
