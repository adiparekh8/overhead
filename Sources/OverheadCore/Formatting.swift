import Foundation

public enum AltitudeUnit: String, CaseIterable, Sendable {
    case feet, meters
    public var label: String { self == .feet ? "ft" : "m" }
}

public enum SpeedUnit: String, CaseIterable, Sendable {
    case knots, mph
    public var label: String { self == .knots ? "kt" : "mph" }
    /// Distances follow the speed unit: nautical miles with knots, miles with mph.
    public var distanceLabel: String { self == .knots ? "nm" : "mi" }
}

public enum Format {
    private static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
    }

    /// "4,200" — rounded to the nearest 25 ft or 10 m.
    public static func altitudeValue(feet: Double, unit: AltitudeUnit) -> String {
        switch unit {
        case .feet: return grouped((feet / 25).rounded() * 25)
        case .meters: return grouped((feet * Geo.metersPerFoot / 10).rounded() * 10)
        }
    }

    public static func altitude(feet: Double, unit: AltitudeUnit) -> String {
        "\(altitudeValue(feet: feet, unit: unit)) \(unit.label)"
    }

    public static func speedValue(knots: Double, unit: SpeedUnit) -> String {
        grouped(unit == .knots ? knots : knots * Geo.milesPerNM)
    }

    public static func speed(knots: Double, unit: SpeedUnit) -> String {
        "\(speedValue(knots: knots, unit: unit)) \(unit.label)"
    }

    /// One decimal place below 10, none above.
    public static func distanceValue(nm: Double, unit: SpeedUnit) -> String {
        let value = unit == .knots ? nm : nm * Geo.milesPerNM
        return value < 9.95 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }

    public static func distance(nm: Double, unit: SpeedUnit) -> String {
        "\(distanceValue(nm: nm, unit: unit)) \(unit.distanceLabel)"
    }

    /// "NW", "S" and so on for a bearing in degrees.
    public static func compass(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return names[Int((normalized / 45).rounded()) % 8]
    }
}

public enum VerticalTrend: Equatable, Sendable {
    case climbing, descending, level

    /// Below 150 ft/min counts as level flight.
    public init(feetPerMinute: Double?) {
        guard let rate = feetPerMinute else { self = .level; return }
        if rate > 150 { self = .climbing } else if rate < -150 { self = .descending } else { self = .level }
    }
}

public enum AircraftNaming {
    private static let dropWords: Set<String> = [
        "CORP", "CORP.", "CORPORATION", "INC", "INC.", "CO", "CO.", "COMPANY", "LLC",
        "LTD", "LTD.", "AEROSPACE", "AIRCRAFT", "AVIATION", "AVN.", "IND", "INDUSTRIES",
        "INTERNATIONAL", "GMBH", "SA", "THE",
    ]

    /// "GULFSTREAM AEROSPACE CORP" becomes "Gulfstream".
    public static func manufacturer(_ raw: String) -> String {
        let words = raw.split(separator: " ").map(String.init)
        var kept = words.filter { !dropWords.contains($0.uppercased()) }
        // "EMBRAER S A"
        while kept.count > 1, let last = kept.last, last.count == 1 { kept.removeLast() }
        if kept.isEmpty { kept = words }
        return kept.map { word in
            // Keep short all-caps names such as DJI or ATR as they are.
            word.count <= 3 ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// "GVI (G650ER)" becomes "G650ER": the FAA puts the marketing name in brackets.
    public static func model(_ raw: String) -> String {
        if let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close {
            let inner = raw[raw.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty { return inner }
        }
        return raw.trimmingCharacters(in: .whitespaces)
    }

    /// "2015 Gulfstream G650ER". Nil when the registry has neither a
    /// manufacturer nor a model.
    public static func displayName(year: String, manufacturer: String, model: String) -> String? {
        let parts = [
            year.count == 4 && Int(year) != nil ? year : "",
            Self.manufacturer(manufacturer),
            Self.model(model),
        ].filter { !$0.isEmpty }
        return manufacturer.isEmpty && model.isEmpty ? nil : parts.joined(separator: " ")
    }
}
