import Foundation
import SQLite3

/// One row of the FAA registry, as written by build_db.py.
public struct RegistryRecord: Equatable, Sendable {
    public var nNumber: String
    public var owner: String
    public var registrantType: String
    public var city: String
    public var state: String
    public var manufacturer: String
    public var model: String
    public var year: String

    public init(
        nNumber: String, owner: String, registrantType: String, city: String,
        state: String, manufacturer: String, model: String, year: String
    ) {
        self.nNumber = nNumber; self.owner = owner; self.registrantType = registrantType
        self.city = city; self.state = state; self.manufacturer = manufacturer
        self.model = model; self.year = year
    }

    public var aircraftName: String? {
        AircraftNaming.displayName(year: year, manufacturer: manufacturer, model: model)
    }

    /// The FAA stores names in capitals. "FALCON LANDING LLC" becomes
    /// "Falcon Landing LLC".
    public var ownerDisplay: String {
        let keepUpper: Set<String> = [
            "LLC", "INC", "LP", "LLP", "LTD", "CO", "NA", "USA", "US", "II", "III", "IV", "PLC", "DBA",
        ]
        let small: Set<String> = ["OF", "AND", "THE", "FOR"]
        return owner.split(separator: " ").enumerated().map { index, part -> String in
            let word = String(part)
            if keepUpper.contains(word) || word.contains(where: \.isNumber) { return word }
            if index > 0, small.contains(word) { return word.lowercased() }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// "Hawthorne, CA"
    public var place: String {
        let prettyCity = city.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return [prettyCity, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// True when the registered owner is a company or a trustee, in which
    /// case it may not be the person who uses the aircraft.
    public var ownerIsCompanyOrTrustee: Bool {
        if ["LLC", "Corporation", "Non-citizen corporation"].contains(registrantType) {
            return true
        }
        let words = Set(owner.uppercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !words.isDisjoint(with: ["TRUSTEE", "TRUST", "LLC", "INC", "CORP"])
    }
}

/// Read-only access to aircraft.db.
public final class Registry {
    public enum RegistryError: Error { case cannotOpen(String) }

    private var db: OpaquePointer?
    private var statement: OpaquePointer?

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Overhead/aircraft.db")
    }

    public init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw RegistryError.cannotOpen(message)
        }
        let sql = """
            SELECT n_number, owner, registrant_type, city, state, manufacturer, model, year
            FROM aircraft WHERE mode_s_hex = ?
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw RegistryError.cannotOpen(message)
        }
    }

    deinit {
        sqlite3_finalize(statement)
        sqlite3_close(db)
    }

    /// Looks up an aircraft by ICAO hex code. Case does not matter.
    public func lookup(hex: String) -> RegistryRecord? {
        guard let statement else { return nil }
        let key = hex.trimmingCharacters(in: .whitespaces).uppercased()
        guard !key.isEmpty else { return nil }
        sqlite3_reset(statement)
        // SQLITE_TRANSIENT: SQLite copies the string before this call returns.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        func column(_ index: Int32) -> String {
            sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
        }
        let record = RegistryRecord(
            nNumber: column(0), owner: column(1), registrantType: column(2), city: column(3),
            state: column(4), manufacturer: column(5), model: column(6), year: column(7)
        )
        sqlite3_reset(statement)
        return record
    }

    /// The date build_db.py was run, as "2026-11-23".
    public var builtDate: String? {
        var query: OpaquePointer?
        defer { sqlite3_finalize(query) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'built'", -1, &query, nil) == SQLITE_OK,
              sqlite3_step(query) == SQLITE_ROW,
              let text = sqlite3_column_text(query, 0) else { return nil }
        return String(cString: text)
    }
}
