// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import os.log

private let logger = Logger(subsystem: "org.ecmdroid.ios", category: "EEPROM")

// EEPROM editing, backup, restore, and burn. Kept in an extension so the raw
// read/write protocol in ECM.swift stays focused on the wire protocol.
extension ECM {

    var canEditEEPROM: Bool {
        isConnected && isEEPROMRead && eeprom != nil
    }

    /// There are unsaved edits in the working buffer that have not been burned.
    var hasUnsavedEEPROMChanges: Bool {
        eeprom?.touched ?? false
    }

    /// The working buffer differs from the as-read image (whether or not it's been burned).
    var isEEPROMModifiedFromPristine: Bool {
        guard let eeprom, let pristine = pristineData else { return false }
        return eeprom.data != pristine
    }

    // MARK: - Byte access

    func getEEPROMByte(at offset: Int) -> UInt8? {
        guard let eeprom, offset >= 0, offset < eeprom.data.count else { return nil }
        return eeprom.data[offset]
    }

    /// Original (as-read) value at an offset, for showing what changed.
    func pristineByte(at offset: Int) -> UInt8? {
        guard let pristine = pristineData, offset >= 0, offset < pristine.count else { return nil }
        return pristine[offset]
    }

    func isByteModified(at offset: Int) -> Bool {
        guard let current = getEEPROMByte(at: offset),
              let original = pristineByte(at: offset) else { return false }
        return current != original
    }

    @discardableResult
    func setEEPROMByte(at offset: Int, to value: UInt8) -> Bool {
        guard let eeprom, offset >= 0, offset < eeprom.data.count else { return false }
        guard eeprom.data[offset] != value else { return false }
        eeprom.data[offset] = value
        eeprom.touch(offset: offset, length: 1)
        return true
    }

    // MARK: - Revert

    /// Discard all edits, returning the working buffer to the pristine image — the
    /// bytes the ECM currently holds (as read, updated after each successful burn).
    /// Buffer and ECM now match, so all dirty flags are cleared.
    func revertToPristine() {
        guard let eeprom, let pristine = pristineData else { return }
        eeprom.data = pristine
        eeprom.markSaved()
        statusMessage = "Reverted to ECM values"
    }

    /// Page 0 is excluded: writing it is unsupported (the original ECMDroid skips it
    /// too), and its write-offset math would index outside the EEPROM buffer.
    private func markWritablePagesTouched(_ eeprom: EEPROM) {
        for page in eeprom.pages where page.nr != 0 { page.touch() }
        eeprom.touched = true
    }

    // MARK: - Backups

    @discardableResult
    func createBackup(name: String, automatic: Bool = false) throws -> EEPROMBackup {
        guard let eeprom else { throw EEPROMBackupError.noEEPROM }
        let backup = EEPROMBackup(
            id: UUID(),
            ecmId: eeprom.id,
            version: eeprom.version,
            ecmType: eeprom.type?.displayName,
            createdAt: Date(),
            name: name,
            isAutomatic: automatic,
            xsize: eeprom.xsize,
            data: eeprom.data
        )
        try EEPROMBackupManager.shared.save(backup)
        return backup
    }

    /// Take the automatic "as read" backup, skipping it if an identical one already
    /// exists (so re-reading the same ECM doesn't pile up duplicates).
    func autoBackup(for eeprom: EEPROM) {
        do {
            if let last = EEPROMBackupManager.shared.mostRecentAutomatic(forEcmId: eeprom.id),
               last.data == eeprom.data {
                return
            }
            _ = try createBackup(name: "Automatic (as read)", automatic: true)
        } catch {
            logger.error("Auto-backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load a backup's bytes into the working buffer. Validated against the connected
    /// ECM so a mismatched dump can't be staged for burning. Does NOT write to the
    /// ECM — the user reviews, then burns explicitly.
    func stageRestore(from backup: EEPROMBackup) throws {
        guard let eeprom else { throw EEPROMBackupError.noEEPROM }
        guard backup.data.count == eeprom.data.count else {
            throw EEPROMBackupError.sizeMismatch(expected: eeprom.data.count, actual: backup.data.count)
        }
        guard backup.ecmId == eeprom.id else {
            throw EEPROMBackupError.ecmMismatch(expected: eeprom.id, actual: backup.ecmId)
        }
        var staged = backup.data
        if let page0 = eeprom.getPage(0) {
            // Page 0 is never burned, so keep the ECM's current bytes there — otherwise
            // the buffer (and the pristine image after a burn) would claim page-0 values
            // the ECM doesn't actually hold.
            for i in page0.start..<(page0.start + page0.length) {
                staged[i] = eeprom.data[i]
            }
        }
        eeprom.data = staged
        markWritablePagesTouched(eeprom)
        statusMessage = "Restored \"\(backup.name)\" — review, then write to ECM"
    }

    // MARK: - Burn

    /// Write staged changes to the ECM. Only dirty pages are sent. After a successful
    /// burn the ECM holds our buffer, so that becomes the new pristine reference.
    func burnEEPROM() async throws {
        guard hasUnsavedEEPROMChanges else {
            statusMessage = "No changes to write"
            return
        }
        try await writeEEPROM()
        pristineData = eeprom?.data
    }
}
