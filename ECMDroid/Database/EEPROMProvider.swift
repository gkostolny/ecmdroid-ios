// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

final class EEPROMProvider {
    static let shared = EEPROMProvider()

    private let db = DatabaseManager.shared

    private init() {}

    func getEEPROM(name: String) -> EEPROM? {
        let ecmName: String
        if name.count > 5 {
            ecmName = String(name.prefix(5))
        } else {
            ecmName = name
        }

        let query = """
            SELECT xsize, type, page, pages.size as pgsize
            FROM eeprom, pages
            WHERE pages.category = eeprom.category
            AND name = '\(ecmName)'
            ORDER BY page
            """
        let rows = db.query(query)
        guard !rows.isEmpty else { return nil }

        let eeprom = EEPROM(id: ecmName)
        var pc = 0

        for row in rows {
            if eeprom.data.isEmpty {
                let xsize = (row["xsize"] as? Int) ?? 0
                eeprom.xsize = xsize
                if let typeStr = row["type"] as? String {
                    eeprom.type = ECMType.getType(typeStr)
                }
                eeprom.data = [UInt8](repeating: 0, count: xsize)
            }

            let pnr = (row["page"] as? Int) ?? 0
            let sz = (row["pgsize"] as? Int) ?? 0
            let page = EEPROM.Page(nr: pnr, length: sz)
            page.parent = eeprom

            if pnr == 0 {
                page.start = eeprom.data.count - page.length
            } else {
                page.start = pc
                pc += page.length
            }

            eeprom.pages.append(page)
        }

        return eeprom
    }

    func getECMIDs(forSize size: Int) -> [String] {
        let query = "SELECT name FROM eeprom WHERE size = \(size) OR xsize = \(size) ORDER BY name"
        return db.queryStrings(query)
    }
}
