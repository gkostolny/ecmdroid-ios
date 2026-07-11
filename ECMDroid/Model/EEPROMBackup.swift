// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import os.log

private let logger = Logger(subsystem: "org.ecmdroid.ios", category: "EEPROM")

/// A complete, self-describing snapshot of an ECM's EEPROM contents. Stored on
/// disk so a known-good configuration can always be re-applied if an edit or burn
/// goes wrong. The full byte image is captured, not a diff, so a restore is exact.
struct EEPROMBackup: Codable, Identifiable {
    let id: UUID
    /// ECM identifier (e.g. "BUEIB") this snapshot was taken from. Restores are
    /// refused unless this matches the connected ECM, so a backup can't be burned
    /// into the wrong module.
    let ecmId: String
    let version: String?
    let ecmType: String?
    let createdAt: Date
    var name: String
    /// True for the snapshot the app takes automatically the first time an EEPROM
    /// is read. These are the last-resort "factory as-found" backups.
    let isAutomatic: Bool
    let xsize: Int
    let data: [UInt8]

    var byteCount: Int { data.count }
}

enum EEPROMBackupError: LocalizedError {
    case noEEPROM
    case sizeMismatch(expected: Int, actual: Int)
    case ecmMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .noEEPROM:
            return "No EEPROM has been read from the ECM yet."
        case .sizeMismatch(let expected, let actual):
            return "Backup size (\(actual) bytes) does not match this ECM (\(expected) bytes). Restore refused to avoid corrupting the module."
        case .ecmMismatch(let expected, let actual):
            return "This backup was taken from a \(actual) ECM but you are connected to a \(expected). Restore refused."
        }
    }
}

/// Manages EEPROM backup files in the app's Documents directory. One JSON file per
/// backup keeps them individually shareable (via the Files app) and easy to prune.
final class EEPROMBackupManager {
    static let shared = EEPROMBackupManager()

    private let fm = FileManager.default

    private lazy var directory: URL = {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("EEPROMBackups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    /// All backups, newest first.
    func list() -> [EEPROMBackup] {
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        let backups: [EEPROMBackup] = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let backup = try? decoder.decode(EEPROMBackup.self, from: data) else {
                    logger.error("Could not decode backup at \(url.lastPathComponent, privacy: .public)")
                    return nil
                }
                return backup
            }
        return backups.sorted { $0.createdAt > $1.createdAt }
    }

    /// Backups taken from a specific ECM, newest first.
    func list(forEcmId ecmId: String) -> [EEPROMBackup] {
        list().filter { $0.ecmId == ecmId }
    }

    func mostRecentAutomatic(forEcmId ecmId: String) -> EEPROMBackup? {
        list(forEcmId: ecmId).first { $0.isAutomatic }
    }

    func save(_ backup: EEPROMBackup) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(backup)
        let url = directory.appendingPathComponent("\(backup.id.uuidString).json")
        try data.write(to: url, options: .atomic)
        logger.info("Saved EEPROM backup \"\(backup.name, privacy: .public)\" (\(backup.byteCount) bytes)")
    }

    func delete(_ backup: EEPROMBackup) throws {
        let url = directory.appendingPathComponent("\(backup.id.uuidString).json")
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
            logger.info("Deleted EEPROM backup \"\(backup.name, privacy: .public)\"")
        }
    }

    /// File URL for a backup, for sharing/export via the Files app.
    func fileURL(for backup: EEPROMBackup) -> URL {
        directory.appendingPathComponent("\(backup.id.uuidString).json")
    }
}
