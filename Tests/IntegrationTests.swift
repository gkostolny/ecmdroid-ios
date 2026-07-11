// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0
//
// Test suite - integration tests against a live ecmsim instance.
// The simulator must be running (run-tests.sh starts one on a dedicated port).

import Foundation

@MainActor
func runIntegrationTests(_ t: TestRunner, host: String, port: UInt16) async {
    let ecm = ECM.shared

    await t.test("TCP: connection to a closed port fails fast") {
        let started = Date()
        do {
            _ = try await TCPSerialPort.connect(host: host, port: 1, timeout: 5)
            t.expect(false, "connect to port 1 should fail")
        } catch {
            t.expect(Date().timeIntervalSince(started) < 5.0, "refusal should not need the full timeout")
        }
    }

    await t.test("TCP: read honors its timeout") {
        let serialPort = try await TCPSerialPort.connect(host: host, port: port)
        let started = Date()
        do {
            _ = try await serialPort.read(count: 1, timeout: 0.5)
            t.expect(false, "read with nothing sent should time out")
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            t.expect(elapsed >= 0.4 && elapsed < 2.0, "timed out in \(String(format: "%.2f", elapsed))s")
        }
        await serialPort.close()
        await sleepMs(200) // let the simulator loop back to accept()
    }

    await t.test("ECMCommand: version handshake") {
        let serialPort = try await TCPSerialPort.connect(host: host, port: port)
        let command = ECMCommand(port: serialPort)
        let version = try await command.readVersion()
        t.expectEqual(version, "BUEIB999 01-02-03", "simulator version string")
        await serialPort.close()
        await sleepMs(200)
    }

    await t.test("ECM: connect + setupEEPROM resolves the ECM from the database") {
        try await ecm.connect(host: host, port: port, protocol: .stock)
        let version = try await ecm.setupEEPROM()
        t.expectEqual(version, "BUEIB999 01-02-03", "version")
        t.expectEqual(ecm.id, "BUEIB", "resolved ECM id")
        t.expect(ecm.isConnected, "connected")
        t.expect(ecm.ecmType != nil, "ECM type resolved")
    }

    await t.test("ECM: full EEPROM read (all pages, including page 0)") {
        try await ecm.readEEPROM()
        t.expect(ecm.isEEPROMRead, "eepromRead flag")
        t.expectEqual(ecm.eeprom?.data.count, 1210, "image size")
        t.expect(ecm.pristineData == ecm.eeprom?.data, "pristine captured")
        t.expect(!ecm.hasUnsavedEEPROMChanges, "no dirty pages after read")
    }

    await t.test("ECM: automatic backup created once, deduplicated on re-read") {
        let autos = EEPROMBackupManager.shared.list(forEcmId: "BUEIB").filter { $0.isAutomatic }
        t.expectEqual(autos.count, 1, "one automatic backup after first read")
        try await ecm.readEEPROM() // identical content -> no new auto backup
        let after = EEPROMBackupManager.shared.list(forEcmId: "BUEIB").filter { $0.isAutomatic }
        t.expectEqual(after.count, 1, "still one automatic backup after re-read")
    }

    await t.test("ECM: byte edits set dirty flags on the right page") {
        let original = ecm.getEEPROMByte(at: 100)
        t.expect(original != nil, "byte readable")
        t.expect(ecm.setEEPROMByte(at: 100, to: (original ?? 0) &+ 1), "edit applied")
        t.expect(ecm.isByteModified(at: 100), "byte reports modified")
        t.expect(ecm.hasUnsavedEEPROMChanges, "unsaved changes")
        t.expect(ecm.isEEPROMModifiedFromPristine, "differs from pristine")
        let touched = ecm.eeprom?.pages.filter { $0.touched }.map { $0.nr } ?? []
        t.expectEqual(touched, [1], "offset 100 lives in page 1")
        t.expect(!ecm.setEEPROMByte(at: 5000, to: 1), "out-of-range edit rejected")
    }

    await t.test("ECM: burn writes dirty pages and re-baselines pristine") {
        try await ecm.burnEEPROM()
        t.expect(!ecm.hasUnsavedEEPROMChanges, "dirty flags cleared after burn")
        t.expect(ecm.pristineData == ecm.eeprom?.data, "pristine re-baselined to burned image")
        t.expect(!ecm.isEEPROMModifiedFromPristine, "matches ECM after burn")
    }

    await t.test("ECM: revert restores pristine and clears dirty flags") {
        let original = ecm.getEEPROMByte(at: 200) ?? 0
        ecm.setEEPROMByte(at: 200, to: original &+ 5)
        t.expect(ecm.hasUnsavedEEPROMChanges, "edit pending")
        ecm.revertToPristine()
        t.expectEqual(ecm.getEEPROMByte(at: 200), original, "byte restored")
        t.expect(!ecm.hasUnsavedEEPROMChanges, "no pending burn after revert (buffer == ECM)")
    }

    await t.test("ECM: backup restore stages writable pages, preserves page 0") {
        let backup = try ecm.createBackup(name: "test-suite restore point")
        // Edit a normal byte and a page-0 byte (directly, as the UI forbids page-0 edits)
        let normalOriginal = ecm.getEEPROMByte(at: 300) ?? 0
        ecm.setEEPROMByte(at: 300, to: normalOriginal &+ 9)
        ecm.eeprom?.data[1206] = 0xAB

        try ecm.stageRestore(from: backup)
        t.expectEqual(ecm.getEEPROMByte(at: 300), normalOriginal, "normal byte restored from backup")
        t.expectEqual(ecm.getEEPROMByte(at: 1206), 0xAB, "page-0 byte preserved (not restorable)")
        let touched = Set(ecm.eeprom?.pages.filter { $0.touched }.map { $0.nr } ?? [])
        t.expect(!touched.contains(0), "page 0 never staged for burning")
        t.expectEqual(touched.count, (ecm.eeprom?.pageCount ?? 0) - 1, "all writable pages staged")
        try await ecm.burnEEPROM() // must not crash / must ACK through the sim
        t.expect(!ecm.hasUnsavedEEPROMChanges, "burn after restore completes")
        ecm.eeprom?.data[1206] = 0x00 // tidy up for later comparisons
        ecm.pristineData = ecm.eeprom?.data
    }

    await t.test("ECM: restore validation rejects mismatched backups") {
        let wrongSize = EEPROMBackup(id: UUID(), ecmId: "BUEIB", version: nil, ecmType: nil,
                                     createdAt: Date(), name: "wrong size", isAutomatic: false,
                                     xsize: 10, data: [UInt8](repeating: 0, count: 10))
        let sizeError = await t.expectThrows("size mismatch") { try ecm.stageRestore(from: wrongSize) }
        t.expect(sizeError is EEPROMBackupError, "typed size error")

        let wrongEcm = EEPROMBackup(id: UUID(), ecmId: "BUEGB", version: nil, ecmType: nil,
                                    createdAt: Date(), name: "wrong ecm", isAutomatic: false,
                                    xsize: 1210, data: [UInt8](repeating: 0, count: 1210))
        let ecmError = await t.expectThrows("ECM mismatch") { try ecm.stageRestore(from: wrongEcm) }
        t.expect(ecmError is EEPROMBackupError, "typed ECM error")
    }

    await t.test("Backup manager: save / list / delete round trip") {
        let backup = try ecm.createBackup(name: "delete me")
        let listed = EEPROMBackupManager.shared.list().first { $0.id == backup.id }
        t.expect(listed != nil, "saved backup listed")
        t.expect(FileManager.default.fileExists(atPath: EEPROMBackupManager.shared.fileURL(for: backup).path),
                 "backup file on disk")
        try EEPROMBackupManager.shared.delete(backup)
        t.expect(!EEPROMBackupManager.shared.list().contains { $0.id == backup.id }, "deleted backup gone")
    }

    await t.test("ECM: runtime data read and channel decode") {
        try await ecm.readRTDataOnce()
        t.expectEqual(ecm.rtData?.count, 107, "BUEIB RT packet size")
        let rpm = ecm.getRuntimeValue(Variables.RPM)
        t.expect(rpm != nil, "RPM decodes from live packet")
    }

    await t.test("ECM: diagnostic error scan (current + stored)") {
        let current = try await ecm.getErrors(type: .current)
        let stored = try await ecm.getErrors(type: .stored)
        // The replayed log data may or may not contain DTCs - just prove the
        // full bitset path decodes without throwing.
        t.expect(current.count >= 0 && stored.count >= 0, "error scans complete")
    }

    await t.test("ECM: device test drives the busy flag") {
        try await ecm.runTest(.fuelPump)
        let busy = try await ecm.isBusy()
        t.expect(busy, "busy right after triggering a test")
        await sleepMs(3300) // simulator holds busy for 3s
        let idle = try await ecm.isBusy()
        t.expect(!idle, "idle after the test window")
    }

    await t.test("Recording + MSL export end to end") {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suite-\(UUID().uuidString).bin")
        try ecm.startRecording(to: logURL, interval: 0.1)
        await sleepMs(700)
        ecm.stopRecording()

        t.expect(ecm.recordsLogged >= 2, "captured multiple records (got \(ecm.recordsLogged))")
        let raw = try Data(contentsOf: logURL)
        t.expectEqual(Int(raw.count), ecm.bytesLogged, "byte counter matches file size")
        t.expectEqual(String(bytes: raw.prefix(5), encoding: .ascii), "BUEIB", "log header")

        let mslURL = try LogExporter.exportToMSL(logURL: logURL)
        let msl = try String(contentsOf: mslURL, encoding: .utf8)
        let lines = msl.split(separator: "\n")
        t.expectEqual(lines.count, 3 + ecm.recordsLogged, "3 header lines + one row per record")
        t.expect(lines[1].contains("RPM"), "RPM column exported")
        try? FileManager.default.removeItem(at: logURL)
        try? FileManager.default.removeItem(at: mslURL)
    }

    await t.test("ECM: disconnect tears down the session") {
        ecm.disconnect()
        t.expect(!ecm.isConnected, "disconnected")
        t.expect(ecm.pristineData == nil, "pristine cleared")
        await sleepMs(300) // let the sim notice and re-listen
    }

    await t.test("Simulator survives an abrupt client reset (regression)") {
        sendImmediateRST(host: host, port: port)
        await sleepMs(300)
        // If the reset killed the simulator, this connect fails.
        try await ecm.connect(host: host, port: port, protocol: .stock)
        let version = try await ecm.setupEEPROM()
        t.expectEqual(version, "BUEIB999 01-02-03", "sim still alive after RST")
        ecm.disconnect()
        await sleepMs(200)
    }
}

/// Connects and immediately resets (SO_LINGER 0 close sends RST, not FIN) —
/// reproduces the client behavior that crashed unpatched ecmsim.
private func sendImmediateRST(host: String, port: UInt16) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    inet_pton(AF_INET, host, &addr.sin_addr)
    let connected = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    if connected == 0 {
        var lingerOpt = linger(l_onoff: 1, l_linger: 0)
        setsockopt(fd, SOL_SOCKET, SO_LINGER, &lingerOpt, socklen_t(MemoryLayout<linger>.size))
    }
    close(fd)
}
