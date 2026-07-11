// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import SQLite3

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?

    private init() {}

    func open() -> Bool {
        guard db == nil else { return true }

        guard let dbPath = Bundle.main.path(forResource: "ecmdroid", ofType: "db") else {
            print("DatabaseManager: ecmdroid.db not found in bundle")
            return false
        }

        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("DatabaseManager: Failed to open database: \(errorMessage)")
            db = nil
            return false
        }
        return true
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
        }
        self.db = nil
    }

    var errorMessage: String {
        if let db = db {
            return String(cString: sqlite3_errmsg(db))
        }
        return "Database not open"
    }

    func query(_ sql: String) -> [[String: Any]] {
        guard let db = db else { return [] }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("DatabaseManager: Query prepare failed: \(errorMessage)\nSQL: \(sql)")
            return []
        }

        var results: [[String: Any]] = []
        let colCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<colCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                let type = sqlite3_column_type(stmt, i)
                switch type {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(stmt, i) {
                        row[name] = String(cString: text)
                    } else {
                        row[name] = ""
                    }
                case SQLITE_NULL:
                    row[name] = NSNull()
                default:
                    row[name] = NSNull()
                }
            }
            results.append(row)
        }

        sqlite3_finalize(stmt)
        return results
    }

    func queryFirst(_ sql: String) -> [String: Any]? {
        return query(sql).first
    }

    func queryStrings(_ sql: String) -> [String] {
        guard let db = db else { return [] }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: text))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    func queryInt(_ sql: String) -> Int? {
        guard let db = db else { return nil }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }

        var result: Int?
        if sqlite3_step(stmt) == SQLITE_ROW {
            result = Int(sqlite3_column_int64(stmt, 0))
        }
        sqlite3_finalize(stmt)
        return result
    }
}
