// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

final class VariableProvider {
    static let shared = VariableProvider()

    private var cache: [String: Variable?] = [:]
    private var currentECM: String?
    private let db = DatabaseManager.shared

    private init() {}

    func getRtVariableNames(ecm: String) -> [String] {
        return getRtVariableNames(ecm: ecm, type: nil)
    }

    func getScalarRtVariableNames(ecm: String) -> [String] {
        return getRtVariableNames(ecm: ecm, type: .scalar)
    }

    func getBitfieldRtVariableNames(ecm: String) -> [String] {
        return getRtVariableNames(ecm: ecm, type: .bitfield)
    }

    private func getRtVariableNames(ecm: String, type: Variable.DataType?) -> [String] {
        var query = """
            SELECT names.origname FROM names, rtoffsets, eeprom
            WHERE eeprom.name = '\(ecm)'
            AND rtoffsets.category = eeprom.category
            AND names.varname = rtoffsets.varname
            AND rtoffsets.secret = 0
            AND names.secret = 0
            """
        if let type = type {
            query += " AND UPPER(rtoffsets.type) = '\(type.rawValue)'"
        }
        query += " ORDER BY UPPER(names.origname)"
        return db.queryStrings(query)
    }

    func getRtVariable(ecm: String, name: String) -> Variable? {
        if let ecm_ = currentECM, ecm_ != ecm {
            cache.removeAll()
        }
        currentECM = ecm

        let key = "rt#\(name)"
        if let cached = cache[key] {
            return cached
        }

        let query = """
            SELECT rtoffsets.*, names.*, eeprom.type as ecm_type
            FROM rtoffsets, eeprom, names
            WHERE eeprom.name = '\(ecm)' AND names.origname = '\(name)'
            AND rtoffsets.category = eeprom.category
            AND names.varname = rtoffsets.varname
            AND names.secret = 0
            AND rtoffsets.secret = 0
            """
        let result = convert(db.queryFirst(query), source: .runtimeData)
        cache[key] = result
        return result
    }

    func getEEPROMVariable(ecm: String, name: String) -> Variable? {
        if let ecm_ = currentECM, ecm_ != ecm {
            cache.removeAll()
        }
        currentECM = ecm

        let key = "ee#\(name)"
        if let cached = cache[key] {
            return cached
        }

        let query = """
            SELECT eeoffsets.*, names.*, eeprom.type as ecm_type
            FROM eeoffsets, eeprom, names
            WHERE eeprom.name = '\(ecm)' AND names.varname = '\(name)'
            AND eeoffsets.category = eeprom.category
            AND eeoffsets.varname = names.varname
            """
        let result = convert(db.queryFirst(query), source: .eeprom)
        cache[key] = result
        return result
    }

    func getNearestEEPROMVariable(ecm: String, offset: Int) -> Variable? {
        let query = """
            SELECT eeoffsets.*, names.*, eeprom.type as ecm_type
            FROM eeoffsets, eeprom, names
            WHERE eeprom.name = '\(ecm)' AND offset <= \(offset)
            AND eeoffsets.category = eeprom.category
            AND eeoffsets.varname = names.varname
            ORDER BY offset DESC LIMIT 1
            """
        return convert(db.queryFirst(query), source: .eeprom)
    }

    func getName(varname: String) -> String? {
        if varname.range(of: #"^(.+)\[(\d+).*\]$"#, options: .regularExpression) != nil {
            if let bracketStart = varname.firstIndex(of: "["),
               let comma = varname.firstIndex(of: ",") ?? varname.firstIndex(of: "]") {
                let nameStr = String(varname[varname.startIndex..<bracketStart])
                let bitStr = String(varname[varname.index(after: bracketStart)..<comma])
                if let bit = Int(bitStr) {
                    return getName(varname: nameStr, bit: bit)
                }
            }
        }
        let query = "SELECT name FROM names WHERE varname = '\(varname)' LIMIT 1"
        return db.queryStrings(query).first
    }

    func getName(varname: String, bit: Int) -> String? {
        guard bit >= 0, bit <= 7 else { return nil }
        let query = "SELECT bitname\(bit + 1) FROM bits WHERE varname = '\(varname)' LIMIT 1"
        return db.queryStrings(query).first
    }

    private func convert(_ row: [String: Any]?, source: DataSource) -> Variable? {
        guard let row = row else { return nil }
        let v = Variable()

        v.id = (row["uniqueid"] as? Int) ?? 0
        if let typeStr = row["ecm_type"] as? String {
            v.ecmType = ECMType.getType(typeStr)
        }
        v.name = (row["origname"] as? String) ?? (row["varname"] as? String) ?? ""
        if let typeStr = row["type"] as? String {
            v.type = Variable.DataType(rawValue: typeStr.uppercased()) ?? .scalar
        }
        v.size = (row["size"] as? Int) ?? 0
        if source == .eeprom {
            v.width = (row["elemsize"] as? Int) ?? 1
            v.cols = (row["cols"] as? Int) ?? 0
            v.rows = (row["rows"] as? Int) ?? 0
        } else {
            v.width = v.size
        }
        v.offset = (row["offset"] as? Int) ?? 0
        v.scale = (row["scale"] as? Double) ?? ((row["scale"] as? Int).map { Double($0) } ?? 0)
        v.translate = (row["translate"] as? Double) ?? ((row["translate"] as? Int).map { Double($0) } ?? 0)
        v.format = row["format"] as? String
        v.label = (row["name"] as? String) ?? ""
        v.remarks = (row["remark"] as? String) ?? ""
        v.variableDescription = (row["description"] as? String) ?? ""
        if let unitStr = row["units"] as? String {
            v.unit = unitStr
            v.symbol = Units.getSymbol(unitStr)
        }

        if source == .runtimeData {
            v.low = (row["low"] as? Double) ?? ((row["low"] as? Int).map { Double($0) } ?? 0)
            v.high = (row["high"] as? Double) ?? ((row["high"] as? Int).map { Double($0) } ?? 0)
            v.ulow = (row["ulow"] as? Int) ?? 0
            v.uhigh = (row["uhigh"] as? Int) ?? 0
        }

        v.initialize()
        return v
    }
}
