import Foundation

/// The airframe shapes Overhead can draw. Every aircraft is mapped to the
/// closest one.
public enum AircraftShape: String, CaseIterable, Sendable {
    case superJumbo         // Airbus A380: full double deck, four engines
    case jumbo              // Boeing 747: hump, four engines
    case quadWidebody       // A340 and other four-engine low-wing jets
    case widebody           // 777, 787, A330, A350
    case cargoWidebody      // a wide-body freighter: no windows, cargo door
    case narrowbody         // 737, A320 family, E-Jets
    case rearEngineJet      // regional jets: CRJ, ERJ-145, also MD-80, 717
    case turboprop          // twin turboprop: Dash 8, ATR, King Air
    case largeBusinessJet   // Gulfstream, Global, Falcon
    case smallBusinessJet   // Citation, Learjet, Phenom
    case pistonSingle       // Cessna 172, Cirrus SR22, Piper Cherokee
    case pistonTwin         // Baron, Seneca, DA42
    case helicopter
    case fighter
    case militaryTransport  // C-17, C-130, A400M: high wing, T-tail
    case glider             // gliders and light sport aircraft

    /// Picks a shape from the ICAO type code (`t` in the API, e.g. "B738"),
    /// falling back to the ADS-B emitter category (`category`, e.g. "A3"),
    /// which is a size class. A wide-body flown by a cargo airline becomes
    /// the freighter shape.
    public static func classify(
        typeCode: String?,
        category: String?,
        cargoOperator: Bool = false
    ) -> AircraftShape {
        let shape = baseShape(typeCode: typeCode, category: category)
        return shape == .widebody && cargoOperator ? .cargoWidebody : shape
    }

    private static func baseShape(typeCode: String?, category: String?) -> AircraftShape {
        let code = (typeCode ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        let cat = (category ?? "").trimmingCharacters(in: .whitespaces).uppercased()

        if !code.isEmpty {
            if let exact = exactCodes[code] { return exact }
            for (prefixes, shape) in prefixRules where prefixes.contains(where: code.hasPrefix) {
                return shape
            }
        }

        // Fallback by size category (ADS-B emitter category).
        switch cat {
        case "A1": return .pistonSingle       // light, under 15,500 lb
        case "A2": return .smallBusinessJet   // small, 15,500 to 75,000 lb
        case "A3", "A4": return .narrowbody   // large; high-vortex large
        case "A5": return .widebody           // heavy, over 300,000 lb
        case "A6": return .fighter            // high performance
        case "A7": return .helicopter         // rotorcraft
        case "B1", "B4": return .glider       // glider; ultralight
        case "B6": return .pistonSingle       // unmanned
        default: return .narrowbody
        }
    }

    /// Type codes matched exactly. Checked before the prefix rules, because
    /// several of these would otherwise be caught by a broader prefix.
    private static let exactCodes: [String: AircraftShape] = {
        var table: [String: AircraftShape] = [:]
        func add(_ shape: AircraftShape, _ codes: [String]) {
            for code in codes { table[code] = shape }
        }
        add(.helicopter, [
            "R22", "R44", "R66", "EC20", "EC25", "EC30", "EC35", "EC45", "EC55", "EC75", "AS32",
            "AS50", "AS55", "AS65", "A109", "A119", "A139", "A169", "A189", "B06", "B407", "B412",
            "B429", "B430", "B505", "B47G", "H60", "H47", "H64", "H500", "MD52", "MD60", "S76",
            "S92", "UH1", "V22", "G2CA", "GYRO",
        ])
        add(.fighter, [
            "F16", "F18", "F18H", "F18S", "F15", "F22", "F35", "F14", "F4", "F5", "A10", "T38",
            "EUFI", "RFAL", "HAWK", "M2K", "TOR", "L39", "SU27", "MG29", "F117", "A4", "AV8B",
        ])
        add(.militaryTransport, [
            "C17", "C5M", "C130", "C30J", "A400", "IL76", "C27J", "C295", "CN35", "C160", "AN12",
            "C141", "A124", "C2",
        ])
        add(.pistonTwin, [
            "BE58", "BE55", "BE76", "BE95", "BE50", "BE60", "PA34", "PA44", "PA31", "PA23", "PA30",
            "PA60", "C310", "C340", "C402", "C414", "C421", "C303", "C337", "DA42", "DA62", "P68",
            "AC50", "AEST",
        ])
        add(.glider, ["GLID", "ULAC", "DG1T", "DUOD", "ARCP", "LS8", "AS21", "PIVI", "SIRA", "BALL"])
        return table
    }()

    /// Checked in order; the first matching prefix wins.
    private static let prefixRules: [([String], AircraftShape)] = [
        (["A38"], .superJumbo),
        (["B74", "BLCF"], .jumbo),
        (["A34", "IL96", "K35", "B70", "DC8", "E3"], .quadWidebody),
        (["A306", "A30B", "A310", "A3ST", "A33", "A35", "B76", "B77", "B78", "MD11", "DC10", "L101", "KC10"], .widebody),
        (["CRJ", "E135", "E145", "E45X", "E35L", "F70", "F100", "B712", "B717", "B72", "MD8", "MD9", "DC9"], .rearEngineJet),
        (["A19", "A20", "A21", "A318", "A319", "A32", "B73", "B37", "B38", "B39", "B75", "BCS",
          "E17", "E19", "E29", "E75", "SU95", "C919", "P8"], .narrowbody),
        (["GLF", "GLEX", "GL5", "GL7", "GA5", "GA6", "GA7", "GA8", "CL60", "CL30", "CL35", "C700",
          "C750", "C68", "F2TH", "F900", "FA", "E545", "E550", "G280"], .largeBusinessJet),
        (["C25", "C50", "C51", "C52", "C55", "C56", "C65", "LJ", "E50P", "E55P", "H25", "HA4", "HDJT",
          "PC24", "BE40", "PRM1", "SF50", "EA50", "ASTR", "WW24", "G150", "G200"], .smallBusinessJet),
        (["AT4", "AT7", "DH8", "DHC", "B190", "BE20", "BE30", "B350", "BE9", "PC12", "PC6", "C208",
          "SF34", "TBM", "P46T", "E120", "SW4", "D328", "JS", "L410", "AT8T", "P180"], .turboprop),
        (["C1", "C2", "C3", "C4", "C82", "P28", "P32", "PA", "SR2", "DA2", "DA4", "DV20", "BE3", "BE5",
          "M20", "RV", "AA5", "GLAS", "COL", "S22T", "DR40"], .pistonSingle),
    ]

    /// A typical length for the shape, in meters. Used only to size the drawing.
    public var nominalLengthMeters: Double {
        switch self {
        case .superJumbo: return 73
        case .jumbo: return 72
        case .quadWidebody: return 68
        case .widebody: return 64
        case .cargoWidebody: return 62
        case .militaryTransport: return 52
        case .narrowbody: return 38
        case .rearEngineJet: return 32
        case .largeBusinessJet: return 29
        case .turboprop: return 28
        case .fighter: return 17
        case .smallBusinessJet: return 14
        case .helicopter: return 12
        case .pistonTwin: return 9.5
        case .pistonSingle: return 8
        case .glider: return 7.5
        }
    }

    /// Width on screen, in points. Bigger aircraft are drawn bigger, but on
    /// a square-root scale: true scale would make a Cessna a 30-point speck
    /// next to an A380.
    public var displayWidth: Double {
        let fraction = (nominalLengthMeters - 7) / (73 - 7)
        return (100 + 240 * max(0, fraction).squareRoot()).rounded()
    }
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
