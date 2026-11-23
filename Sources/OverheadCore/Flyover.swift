import Foundation

/// The airframe shapes Overhead can draw. Every aircraft is mapped to the
/// closest one.
public enum AircraftShape: String, CaseIterable, Sendable {
    case superJumbo     // Airbus A380: full double deck, four engines
    case jumbo          // Boeing 747: hump, four engines
    case quadWidebody   // A340 and other four-engine wide-bodies
    case widebody       // 777, 787, A330, A350
    case narrowbody     // 737, A320 family, E-Jets
    case rearEngineJet  // CRJ, ERJ-145, MD-80, 717: engines at the tail, T-tail
    case businessJet
    case turboprop
    case pistonSingle
    case helicopter

    /// Picks a shape from the ICAO type code (`t` in the API, e.g. "B738"),
    /// falling back to the ADS-B emitter category (`category`, e.g. "A3").
    public static func classify(typeCode: String?, category: String?) -> AircraftShape {
        let code = (typeCode ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        let cat = (category ?? "").trimmingCharacters(in: .whitespaces).uppercased()

        if !code.isEmpty {
            if helicopters.contains(code) { return .helicopter }
            for (prefixes, shape) in rules where prefixes.contains(where: code.hasPrefix) {
                return shape
            }
        }

        switch cat {
        case "A7": return .helicopter
        case "A1", "B1", "B4": return .pistonSingle
        case "A2": return .businessJet
        case "A5": return .widebody
        case "A3", "A4": return .narrowbody
        default: break
        }
        // An unknown code starting with these is almost always a light piston.
        if ["C1", "C2", "P28", "PA", "SR2", "DA", "BE3", "M20", "RV"].contains(where: code.hasPrefix) {
            return .pistonSingle
        }
        return .narrowbody
    }

    private static let helicopters: Set<String> = [
        "R22", "R44", "R66", "EC20", "EC25", "EC30", "EC35", "EC45", "EC55", "EC75", "AS32",
        "AS50", "AS55", "AS65", "A109", "A119", "A139", "A169", "A189", "B06", "B407", "B412",
        "B429", "B430", "B505", "B47G", "H60", "H47", "H64", "H500", "MD52", "MD60", "S76",
        "S92", "UH1", "V22", "G2CA",
    ]

    /// Checked in order; the first matching prefix wins.
    private static let rules: [([String], AircraftShape)] = [
        (["A38"], .superJumbo),
        (["B74", "BLCF"], .jumbo),
        (["A34", "IL96", "A124", "C5M"], .quadWidebody),
        (["A306", "A30B", "A310", "A3ST", "A33", "A35", "B76", "B77", "B78", "MD11", "DC10", "L101", "K35", "KC10"], .widebody),
        (["CRJ", "E135", "E145", "E45X", "E35L", "F70", "F100", "B712", "B717", "MD8", "MD9", "DC9"], .rearEngineJet),
        (["A19", "A20", "A21", "A318", "A319", "A32", "B73", "B37", "B38", "B39", "B75", "B72", "BCS",
          "E17", "E19", "E29", "E75", "SU95", "C919"], .narrowbody),
        (["GLF", "GLEX", "GL5", "GL7", "G150", "G200", "G280", "GA5", "GA6", "GA7", "GA8", "CL30", "CL35",
          "CL60", "C25", "C50", "C51", "C52", "C55", "C56", "C65", "C68", "C70", "C75", "LJ", "F2TH",
          "F900", "FA", "E50P", "E55P", "E545", "E550", "H25", "HA4", "HDJT", "PC24", "BE40", "PRM1",
          "SF50", "EA50", "ASTR", "WW24"], .businessJet),
        (["AT4", "AT7", "DH8", "DHC", "B190", "BE20", "BE30", "B350", "BE9", "PC12", "PC6", "C208",
          "SF34", "TBM", "P46T", "E120", "SW4", "D328", "JS", "L410", "C130", "C30J", "AT8T", "P180"], .turboprop),
        (["C1", "C2", "C3", "C4", "C82", "P28", "P32", "PA", "SR2", "DA2", "DA4", "DV20", "BE3", "BE5",
          "M20", "RV", "AA5", "GLAS", "COL", "S22T", "DR40"], .pistonSingle),
    ]
}

/// Rules for the animation of an aircraft flying across the screen.
public enum FlyoverPolicy {
    /// The same aircraft is not shown again within this many seconds.
    public static let repeatInterval: TimeInterval = 30 * 60

    /// True when a flyover should be shown for the overhead aircraft.
    public static func shouldFly(
        slantNM: Double,
        rangeNM: Double,
        lastShown: Date?,
        now: Date = Date()
    ) -> Bool {
        guard slantNM <= rangeNM else { return false }
        if let lastShown, now.timeIntervalSince(lastShown) < repeatInterval { return false }
        return true
    }

    /// Seconds to cross the screen: faster aircraft cross faster.
    /// 480 kt takes 6 s, 240 kt takes 10 s, anything slow takes 13 s.
    public static func duration(groundSpeedKnots: Double?) -> TimeInterval {
        guard let speed = groundSpeedKnots, speed.isFinite else { return 10 }
        return min(13, max(6, 14 - speed / 60))
    }

    /// Eastbound aircraft cross left to right, westbound right to left.
    /// Due north and due south (and unknown) go left to right.
    public static func fliesLeftToRight(heading: Double?) -> Bool {
        guard let heading else { return true }
        let normalized = (heading.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return normalized <= 180
    }
}
