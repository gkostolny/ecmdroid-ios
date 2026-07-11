// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

final class BitSetProvider {
    static let shared = BitSetProvider()

    private var cache: [String: ECMBitSet?] = [:]
    private var currentECM: String?
    private let db = DatabaseManager.shared

    private init() {}

    func getBitSet(ecmID: String, name: String, source: DataSource) -> ECMBitSet? {
        if let ecm = currentECM, ecm != ecmID {
            cache.removeAll()
        }
        currentECM = ecmID

        if let cached = cache[name] {
            return cached
        }

        let offsetTable = (source == .eeprom) ? "eeoffsets" : "rtoffsets"
        var query = """
            SELECT * FROM \(offsetTable) AS offsets, bits, eeprom
            WHERE offsets.varname = '\(name)'
            AND bits.varname = offsets.varname
            AND eeprom.name = '\(ecmID)'
            AND offsets.category = eeprom.category
            """
        if source == .runtimeData {
            query += " AND offsets.secret = 0"
        }

        guard let row = db.queryFirst(query) else {
            cache[name] = nil
            return nil
        }

        let setname = (row["varname"] as? String) ?? name
        let label = (row["name"] as? String) ?? ""
        let offset = (row["offset"] as? Int) ?? 0
        let typeStr = (row["type"] as? String) ?? ""

        let bitset = ECMBitSet(name: setname, label: label, offset: offset)

        for i in 1...8 {
            let bitname = row["bitname\(i)"] as? String
            let bitdesc = row["bit\(i)"] as? String
            let dtc = row["dtc\(i)"] as? String

            let nameEmpty = (bitname ?? "").isEmpty
            let descEmpty = (bitdesc ?? "").isEmpty

            if nameEmpty && descEmpty {
                continue
            }

            let bit = Bit()
            bit.name = nameEmpty ? "\(setname).\(i)" : (bitname ?? "")
            bit.bitNr = i - 1
            bit.byteNr = (row["byte"] as? Int) ?? 0
            bit.offset = offset
            bit.type = ECMType.getType(typeStr)
            bit.remark = bitdesc ?? ""
            bit.code = dtc ?? ""
            bitset.add(bit)
        }

        cache[name] = bitset
        return bitset
    }
}
