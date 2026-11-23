import Foundation

/// The envelope of every ADSB.lol `/v2/*` response.
/// Field names follow https://api.adsb.lol/docs (schema `V2Response_Model`).
public struct ADSBResponse: Decodable, Equatable, Sendable {
    public let ac: [ADSBAircraft]
    public let msg: String?
    public let total: Int?
    /// Time the data was generated, Unix milliseconds.
    public let now: Double?

    public static func decode(_ data: Data) throws -> ADSBResponse {
        try JSONDecoder().decode(ADSBResponse.self, from: data)
    }
}

/// `alt_baro` is a number of feet, or the string "ground".
public enum BaroAltitude: Equatable, Sendable {
    case feet(Double)
    case ground
}

/// One aircraft (schema `V2Response_AcItem`). Only `hex` is guaranteed; every
/// other field is absent or null when the aircraft does not report it.
public struct ADSBAircraft: Decodable, Equatable, Identifiable, Sendable {
    /// 24-bit ICAO address as sent. A leading `~` marks a non-ICAO address.
    public let hex: String
    /// Source of the position, e.g. `adsb_icao`, `mlat`, `tisb_icao`.
    public let type: String?
    /// Callsign, right-padded with spaces by the API.
    public let flight: String?
    /// Registration from the API's aircraft database.
    public let r: String?
    /// ICAO type code, e.g. `B738`.
    public let t: String?
    public let altBaro: BaroAltitude?
    /// Geometric altitude in feet.
    public let altGeom: Double?
    /// Ground speed in knots.
    public let gs: Double?
    /// True track over ground in degrees.
    public let track: Double?
    public let trueHeading: Double?
    public let magHeading: Double?
    /// Feet per minute.
    public let baroRate: Double?
    public let geomRate: Double?
    public let lat: Double?
    public let lon: Double?
    /// Seconds since the last position update.
    public let seenPos: Double?
    /// Distance from the query point in nautical miles (point queries only).
    public let dst: Double?
    /// True direction from the query point in degrees (point queries only).
    public let dir: Double?
    /// Emitter category, A0-D7.
    public let category: String?

    public var id: String { hex }

    enum CodingKeys: String, CodingKey {
        case hex, type, flight, r, t, gs, track, lat, lon, dst, dir, category
        case altBaro = "alt_baro"
        case altGeom = "alt_geom"
        case trueHeading = "true_heading"
        case magHeading = "mag_heading"
        case baroRate = "baro_rate"
        case geomRate = "geom_rate"
        case seenPos = "seen_pos"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hex = try c.decode(String.self, forKey: .hex)

        // Be lenient about everything else: a field with an unexpected type
        // is treated as missing rather than failing the whole response.
        func string(_ key: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        func number(_ key: CodingKeys) -> Double? {
            guard let value = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil,
                  value.isFinite else { return nil }
            return value
        }

        type = string(.type)
        flight = string(.flight)
        r = string(.r)
        t = string(.t)
        category = string(.category)
        altGeom = number(.altGeom)
        gs = number(.gs)
        track = number(.track)
        trueHeading = number(.trueHeading)
        magHeading = number(.magHeading)
        baroRate = number(.baroRate)
        geomRate = number(.geomRate)
        lat = number(.lat)
        lon = number(.lon)
        seenPos = number(.seenPos)
        dst = number(.dst)
        dir = number(.dir)

        if let feet = number(.altBaro) {
            altBaro = .feet(feet)
        } else if let text = string(.altBaro), text.lowercased() == "ground" {
            altBaro = .ground
        } else {
            altBaro = nil
        }
    }

    public init(
        hex: String, type: String? = nil, flight: String? = nil, r: String? = nil,
        t: String? = nil, altBaro: BaroAltitude? = nil, altGeom: Double? = nil,
        gs: Double? = nil, track: Double? = nil, trueHeading: Double? = nil,
        magHeading: Double? = nil, baroRate: Double? = nil, geomRate: Double? = nil,
        lat: Double? = nil, lon: Double? = nil, seenPos: Double? = nil,
        dst: Double? = nil, dir: Double? = nil, category: String? = nil
    ) {
        self.hex = hex; self.type = type; self.flight = flight; self.r = r; self.t = t
        self.altBaro = altBaro; self.altGeom = altGeom; self.gs = gs; self.track = track
        self.trueHeading = trueHeading; self.magHeading = magHeading
        self.baroRate = baroRate; self.geomRate = geomRate; self.lat = lat; self.lon = lon
        self.seenPos = seenPos; self.dst = dst; self.dir = dir; self.category = category
    }
}

extension ADSBAircraft {
    public var isOnGround: Bool { altBaro == .ground }

    /// Altitude in feet: barometric when reported, otherwise geometric.
    /// Nil on the ground or when the aircraft reports no altitude.
    public var altitudeFeet: Double? {
        switch altBaro {
        case .feet(let feet): return feet
        case .ground: return nil
        case nil: return altGeom
        }
    }

    public var coordinate: Coordinate? {
        guard let lat, let lon else { return nil }
        let c = Coordinate(latitude: lat, longitude: lon)
        return c.isValid ? c : nil
    }

    /// Direction the aircraft is moving, degrees clockwise from true north.
    public var heading: Double? { track ?? trueHeading ?? magHeading }

    /// Feet per minute; positive is climbing.
    public var verticalRate: Double? { baroRate ?? geomRate }

    public var callsign: String? {
        guard let trimmed = flight?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    public var registration: String? {
        guard let trimmed = r?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    public var typeCode: String? {
        guard let trimmed = t?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// The ICAO hex code in the form the FAA registry uses (uppercase), or
    /// nil when the address is not a real ICAO one (`~` prefix).
    public var icaoHex: String? {
        let trimmed = hex.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("~") else { return nil }
        return trimmed.uppercased()
    }
}
