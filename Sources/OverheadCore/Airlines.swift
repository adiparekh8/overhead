import Foundation

/// A color as red, green and blue from 0 to 1.
public struct RGB: Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// `RGB(0x0B2F7A)`
    public init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    public static let white = RGB(0xFFFFFF)

    /// Blends toward `other` by `amount` (0 keeps this color, 1 gives `other`).
    public func mixed(with other: RGB, _ amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// Perceived brightness, 0 to 1.
    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// From hue (degrees), saturation and lightness (0 to 1).
    public init(hue: Double, saturation: Double, lightness: Double) {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch Int(h) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        r = r1 + m; g = g1 + m; b = b1 + m
    }
}

/// The colors an aircraft is painted in. Colors only: no logos or wordmarks.
public struct Livery: Equatable, Sendable {
    /// Fuselage.
    public var body: RGB
    /// Vertical tail.
    public var tail: RGB
    /// Engine nacelles.
    public var engine: RGB
    /// A stripe along the fuselage, and the edge of the towed banner.
    public var accent: RGB

    public init(body: RGB, tail: RGB, engine: RGB, accent: RGB) {
        self.body = body; self.tail = tail; self.engine = engine; self.accent = accent
    }

    /// Flat grey, for military aircraft that are not flying for an airline.
    public static let military = Livery(
        body: RGB(0x8E969F), tail: RGB(0x79818B), engine: RGB(0x6E757E), accent: RGB(0x5E656D)
    )

    /// Chooses the paint: the airline's colors when the callsign belongs to
    /// a known airline, grey for military shapes, otherwise the private
    /// scheme for that tail number.
    public static func choose(airline: Airline?, shape: AircraftShape, tailNumber: String) -> Livery {
        if let airline { return airline.livery }
        if shape == .fighter || shape == .militaryTransport { return .military }
        return .privateAircraft(tailNumber: tailNumber)
    }

    /// White and grey with one accent color taken from a hash of the tail
    /// number, so the same aircraft always looks the same.
    public static func privateAircraft(tailNumber: String) -> Livery {
        let key = tailNumber.trimmingCharacters(in: .whitespaces).uppercased()
        // FNV-1a: stable across launches, unlike Swift's own hashing.
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        let accent = RGB(hue: Double(hash % 360), saturation: 0.62, lightness: 0.44)
        return Livery(body: RGB(0xF4F5F7), tail: accent, engine: RGB(0xB9BEC6), accent: accent)
    }
}

public struct Airline: Equatable, Sendable {
    /// Three-letter ICAO code, the start of the callsign: "UAL".
    public let icao: String
    /// Two-character IATA code used in flight numbers: "UA".
    public let iata: String
    public let name: String
    public let livery: Livery
    /// Flies freight only.
    public let cargo: Bool

    /// Looks an airline up by its ICAO code.
    public static func find(icao: String) -> Airline? {
        byICAO[icao.uppercased()]
    }

    private static let byICAO: [String: Airline] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.icao, $0) }
    )

    private static func make(
        _ icao: String, _ iata: String, _ name: String,
        body: UInt32, tail: UInt32, engine: UInt32, accent: UInt32, cargo: Bool = false
    ) -> Airline {
        Airline(
            icao: icao, iata: iata, name: name,
            livery: Livery(body: RGB(body), tail: RGB(tail), engine: RGB(engine), accent: RGB(accent)),
            cargo: cargo
        )
    }

    /// Approximations of each airline's current paint scheme.
    public static let all: [Airline] = [
        // United States
        make("UAL", "UA", "United", body: 0xFFFFFF, tail: 0x0B2F7A, engine: 0x0B2F7A, accent: 0x6CACE4),
        make("DAL", "DL", "Delta", body: 0xFFFFFF, tail: 0xC01933, engine: 0x0B2A5B, accent: 0x0B2A5B),
        make("AAL", "AA", "American", body: 0xC9CDD2, tail: 0x0A3161, engine: 0xC9CDD2, accent: 0xC8102E),
        make("SWA", "WN", "Southwest", body: 0x304CB2, tail: 0x304CB2, engine: 0x304CB2, accent: 0xFFBF27),
        make("ASA", "AS", "Alaska", body: 0xFFFFFF, tail: 0x01426A, engine: 0xFFFFFF, accent: 0x6FBF44),
        make("JBU", "B6", "JetBlue", body: 0xFFFFFF, tail: 0x003876, engine: 0x003876, accent: 0x0090D1),
        make("NKS", "NK", "Spirit", body: 0xFFEC00, tail: 0xFFEC00, engine: 0xFFEC00, accent: 0x1A1A1A),
        make("FFT", "F9", "Frontier", body: 0xFFFFFF, tail: 0x046A38, engine: 0x046A38, accent: 0x046A38),
        make("HAL", "HA", "Hawaiian", body: 0xFFFFFF, tail: 0x4B2A85, engine: 0x4B2A85, accent: 0xD6006E),
        make("AAY", "G4", "Allegiant", body: 0xFFFFFF, tail: 0x02569B, engine: 0x02569B, accent: 0xFBB034),
        make("SCX", "SY", "Sun Country", body: 0xFFFFFF, tail: 0x003C71, engine: 0x003C71, accent: 0xF58025),
        make("MXY", "MX", "Breeze", body: 0xFFFFFF, tail: 0x1B4F9C, engine: 0x8CC8F0, accent: 0x8CC8F0),
        make("SKW", "OO", "SkyWest", body: 0xFFFFFF, tail: 0x1F3D7A, engine: 0xD0D4DA, accent: 0x8A93A3),
        make("RPA", "YX", "Republic", body: 0xFFFFFF, tail: 0x23395D, engine: 0xD0D4DA, accent: 0x8A93A3),
        make("ENY", "MQ", "Envoy", body: 0xC9CDD2, tail: 0x0A3161, engine: 0xC9CDD2, accent: 0xC8102E),
        make("JIA", "OH", "PSA", body: 0xC9CDD2, tail: 0x0A3161, engine: 0xC9CDD2, accent: 0xC8102E),
        make("EDV", "9E", "Endeavor", body: 0xFFFFFF, tail: 0xC01933, engine: 0x0B2A5B, accent: 0x0B2A5B),
        make("EJA", "1I", "NetJets", body: 0xFFFFFF, tail: 0x1B1B1B, engine: 0xD0D4DA, accent: 0x9E8B5A),
        // Cargo
        make("FDX", "FX", "FedEx", body: 0xFFFFFF, tail: 0x4D148C, engine: 0xFFFFFF, accent: 0xFF6600, cargo: true),
        make("UPS", "5X", "UPS", body: 0xFFFFFF, tail: 0x351C15, engine: 0x351C15, accent: 0xFFB500, cargo: true),
        make("GTI", "5Y", "Atlas Air", body: 0xFFFFFF, tail: 0x0B2A5B, engine: 0xFFFFFF, accent: 0xD4A017, cargo: true),
        make("CKS", "K4", "Kalitta Air", body: 0xFFFFFF, tail: 0xB22222, engine: 0xFFFFFF, accent: 0xD4A017, cargo: true),
        make("CLX", "CV", "Cargolux", body: 0xFFFFFF, tail: 0xC8102E, engine: 0xFFFFFF, accent: 0x00A3E0, cargo: true),
        // Canada, Mexico, Latin America
        make("ACA", "AC", "Air Canada", body: 0xFFFFFF, tail: 0x111111, engine: 0x111111, accent: 0xD22630),
        make("WJA", "WS", "WestJet", body: 0xFFFFFF, tail: 0x0B3D5B, engine: 0x00A5B5, accent: 0x00A5B5),
        make("AMX", "AM", "Aeromexico", body: 0xE6E8EB, tail: 0x0B2343, engine: 0xE6E8EB, accent: 0xC8102E),
        make("VOI", "Y4", "Volaris", body: 0xFFFFFF, tail: 0x1A1A1A, engine: 0x1A1A1A, accent: 0xA0228D),
        make("AVA", "AV", "Avianca", body: 0xFFFFFF, tail: 0xDA291C, engine: 0xDA291C, accent: 0xDA291C),
        make("LAN", "LA", "LATAM", body: 0xFFFFFF, tail: 0x1B0088, engine: 0x1B0088, accent: 0xE4002B),
        make("CMP", "CM", "Copa", body: 0xFFFFFF, tail: 0x003A70, engine: 0x003A70, accent: 0xC9A227),
        // Europe
        make("BAW", "BA", "British Airways", body: 0xFFFFFF, tail: 0x075AAA, engine: 0x0B2F6B, accent: 0xC8102E),
        make("DLH", "LH", "Lufthansa", body: 0xFFFFFF, tail: 0x05164D, engine: 0xFFFFFF, accent: 0x05164D),
        make("AFR", "AF", "Air France", body: 0xFFFFFF, tail: 0x002157, engine: 0xFFFFFF, accent: 0xED1C24),
        make("KLM", "KL", "KLM", body: 0x00A1E4, tail: 0x00A1E4, engine: 0xFFFFFF, accent: 0x003145),
        make("RYR", "FR", "Ryanair", body: 0xFFFFFF, tail: 0x073590, engine: 0x073590, accent: 0xF1C933),
        make("EZY", "U2", "easyJet", body: 0xFFFFFF, tail: 0xFF6600, engine: 0xFF6600, accent: 0xFF6600),
        make("VIR", "VS", "Virgin Atlantic", body: 0xFFFFFF, tail: 0xE10A0A, engine: 0xE10A0A, accent: 0x5B2A86),
        make("IBE", "IB", "Iberia", body: 0xFFFFFF, tail: 0xD7192D, engine: 0xFFFFFF, accent: 0xFCD116),
        make("SWR", "LX", "Swiss", body: 0xFFFFFF, tail: 0xE2001A, engine: 0xFFFFFF, accent: 0xE2001A),
        make("SAS", "SK", "SAS", body: 0xE9EAEC, tail: 0x000080, engine: 0xE9EAEC, accent: 0x000080),
        make("TAP", "TP", "TAP Air Portugal", body: 0xFFFFFF, tail: 0xD5002B, engine: 0xFFFFFF, accent: 0x6CBE45),
        make("THY", "TK", "Turkish", body: 0xFFFFFF, tail: 0xC8102E, engine: 0xFFFFFF, accent: 0xC8102E),
        make("EIN", "EI", "Aer Lingus", body: 0xFFFFFF, tail: 0x006272, engine: 0x006272, accent: 0x84BD00),
        make("ICE", "FI", "Icelandair", body: 0xFFFFFF, tail: 0x003A7D, engine: 0x003A7D, accent: 0xFFC72C),
        make("FIN", "AY", "Finnair", body: 0xFFFFFF, tail: 0x0B1560, engine: 0xFFFFFF, accent: 0x0B1560),
        // Middle East, Asia, Pacific
        make("UAE", "EK", "Emirates", body: 0xFFFFFF, tail: 0xD71920, engine: 0xFFFFFF, accent: 0xC5A56A),
        make("QTR", "QR", "Qatar Airways", body: 0xD9D9D6, tail: 0x5C0632, engine: 0xD9D9D6, accent: 0x5C0632),
        make("ETD", "EY", "Etihad", body: 0xD9CBA8, tail: 0xBD8B13, engine: 0xD9CBA8, accent: 0xBD8B13),
        make("JAL", "JL", "Japan Airlines", body: 0xFFFFFF, tail: 0xCC0000, engine: 0xFFFFFF, accent: 0xCC0000),
        make("ANA", "NH", "ANA", body: 0xFFFFFF, tail: 0x13448F, engine: 0xFFFFFF, accent: 0x6DB7E6),
        make("KAL", "KE", "Korean Air", body: 0x8CC8E8, tail: 0x8CC8E8, engine: 0x8CC8E8, accent: 0xC8102E),
        make("CPA", "CX", "Cathay Pacific", body: 0xFFFFFF, tail: 0x005D63, engine: 0xFFFFFF, accent: 0x005D63),
        make("SIA", "SQ", "Singapore Airlines", body: 0xFFFFFF, tail: 0x1D2A5C, engine: 0xFFFFFF, accent: 0xF5A800),
        make("QFA", "QF", "Qantas", body: 0xFFFFFF, tail: 0xE0001B, engine: 0xFFFFFF, accent: 0xE0001B),
        make("ANZ", "NZ", "Air New Zealand", body: 0xFFFFFF, tail: 0x111111, engine: 0xFFFFFF, accent: 0x111111),
    ]
}

/// A callsign split into its airline and flight number.
public struct Callsign: Equatable, Sendable {
    /// As sent by the aircraft, trimmed: "UAL512".
    public let raw: String
    /// The three-letter ICAO airline code, if the callsign has that form.
    public let airlineCode: String?
    /// The part after the airline code: "512".
    public let number: String?

    /// Airline callsigns are three letters followed by a flight number that
    /// starts with a digit ("UAL512", "BAW28K"). Anything else, such as a
    /// tail number used as a callsign, has no airline.
    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        raw = trimmed
        let letters = trimmed.prefix(3)
        let rest = trimmed.dropFirst(3)
        if letters.count == 3, letters.allSatisfy({ $0.isASCII && $0.isLetter }),
           let first = rest.first, first.isNumber, rest.count <= 5,
           rest.allSatisfy({ $0.isASCII && ($0.isNumber || $0.isLetter) }) {
            airlineCode = String(letters)
            number = String(rest)
        } else {
            airlineCode = nil
            number = nil
        }
    }

    public var airline: Airline? {
        airlineCode.flatMap(Airline.find(icao:))
    }

    /// The flight number as passengers see it: "UAL512" becomes "UA512".
    /// Callsigns from airlines not in the table are returned unchanged.
    public var flightNumber: String {
        guard let airline, let number else { return raw }
        let digits = number.drop { $0 == "0" }
        return airline.iata + (digits.isEmpty ? "0" : String(digits))
    }
}

/// What, if anything, is written along the fuselage.
public enum FuselageLabel {
    public static let maxLength = 22

    private static let suffixes: Set<String> = [
        "LLC", "L.L.C.", "INC", "INC.", "CORP", "CORP.", "CORPORATION", "CO", "CO.", "COMPANY",
        "LTD", "LTD.", "LP", "LLP", "TRUSTEE", "TRUSTEES", "NA", "N.A.", "DBA",
    ]

    /// - An airline aircraft carries no text: its colors identify it.
    /// - A company, LLC, trust or government owner is written out, without
    ///   its legal suffix and cut at a word boundary.
    /// - Anything else, including every individual owner, shows the tail
    ///   number. A person's name is never written on the aircraft.
    public static func text(isAirline: Bool, record: RegistryRecord?, tailNumber: String?) -> String? {
        if isAirline { return nil }
        let tail = tailNumber?.trimmingCharacters(in: .whitespaces).uppercased()
        let fallback = (tail?.isEmpty ?? true) ? nil : tail
        guard let record else { return fallback }
        let showsOwner = record.ownerIsCompanyOrTrustee || record.registrantType == "Government"
        guard showsOwner, record.registrantType != "Individual" else { return fallback ?? record.nNumber }
        let cleaned = clean(owner: record.owner)
        return cleaned.isEmpty ? (fallback ?? record.nNumber) : cleaned
    }

    /// "FALCON LANDING LLC" becomes "FALCON LANDING"; long names end in "…".
    static func clean(owner: String) -> String {
        var words = owner.uppercased().split(separator: " ").map(String.init)
        while let last = words.last, suffixes.contains(last), words.count > 1 { words.removeLast() }
        var result = ""
        for word in words {
            let candidate = result.isEmpty ? word : result + " " + word
            if candidate.count > maxLength {
                if result.isEmpty { return String(word.prefix(maxLength - 1)) + "…" }
                return result + "…"
            }
            result = candidate
        }
        return result
    }
}
