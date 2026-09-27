// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0
//
// Test suite - offline unit tests (no simulator required)

import Foundation

@MainActor
func runUnitTests(_ t: TestRunner) async {

    await t.test("PDU: version request has known-good wire format") {
        PDU.setProtocol(.stock)
        t.expectEqual(PDU.getVersion().bytes, [0x01, 0x00, 0x42, 0x02, 0xFF, 0x02, 0x56, 0x03, 0xE8],
                      "getVersion bytes")
    }

    await t.test("PDU: factory race protocol changes recipient id") {
        PDU.setProtocol(.factoryRace)
        t.expectEqual(PDU.getVersion().bytes[2], 0x55, "race ECM id")
        PDU.setProtocol(.stock)
        t.expectEqual(PDU.getVersion().bytes[2], 0x42, "stock ECM id")
    }

    await t.test("PDU: corrupt checksum is rejected") {
        var bytes = PDU.getVersion().bytes
        bytes[bytes.count - 1] ^= 0xFF
        do {
            _ = try PDU(packet: bytes, length: bytes.count)
            t.expect(false, "checksum mismatch should throw")
        } catch { /* expected */ }
    }

    await t.test("PDU: corrupt header is rejected") {
        var bytes = PDU.getVersion().bytes
        bytes[0] = 0x7F // not SOH
        do {
            _ = try PDU(packet: bytes, length: bytes.count)
            t.expect(false, "bad SOH should throw")
        } catch { /* expected */ }
    }

    await t.test("PDU: setRequest embeds the right slice of the buffer") {
        let data: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        let pdu = try PDU.setRequest(pageno: 3, offset: 2, data: data, pos: 4, len: 3)
        // payload = [CMD_SET, offset, page, data[4], data[5], data[6]]
        t.expectEqual(Array(pdu.bytes[6..<12]), [0x57, 0x02, 0x03, 4, 5, 6], "SET payload")
    }

    await t.test("EEPROM provider: BUEIB layout matches the database") {
        guard let eeprom = EEPROMProvider.shared.getEEPROM(name: "BUEIB") else {
            t.expect(false, "BUEIB should exist"); return
        }
        t.expectEqual(eeprom.data.count, 1210, "xsize")
        t.expectEqual(eeprom.pageCount, 7, "page count")
        guard let page0 = eeprom.getPage(0) else {
            t.expect(false, "page 0 should exist"); return
        }
        t.expectEqual(page0.length, 4, "page 0 length")
        t.expectEqual(page0.start, 1206, "page 0 start (end of image)")
        // Non-zero pages must tile 0..<1206 contiguously
        var cursor = 0
        for page in eeprom.pages.sorted(by: { $0.nr < $1.nr }) where page.nr != 0 {
            t.expectEqual(page.start, cursor, "page \(page.nr) start")
            cursor += page.length
        }
        t.expectEqual(cursor, 1206, "non-zero pages cover image up to page 0")
        t.expect(eeprom.hasPageZero, "hasPageZero")
    }

    await t.test("EEPROM provider: version strings are trimmed to 5-char ECM id") {
        let eeprom = EEPROMProvider.shared.getEEPROM(name: "BUEIB999 01-02-03")
        t.expectEqual(eeprom?.id, "BUEIB", "trimmed id")
        t.expect(EEPROMProvider.shared.getEEPROM(name: "NOPES") == nil, "unknown ECM returns nil")
    }

    await t.test("EEPROM model: touch marks only the page containing the offset") {
        guard let eeprom = EEPROMProvider.shared.getEEPROM(name: "BUEIB") else {
            t.expect(false, "BUEIB should exist"); return
        }
        eeprom.touch(offset: 4, length: 1) // inside page 1 (starts at 0, page 0 lives at the end)
        let touched = eeprom.pages.filter { $0.touched }.map { $0.nr }
        t.expectEqual(touched, [1], "only page 1 touched")
        t.expect(eeprom.touched, "eeprom marked touched")
        eeprom.markSaved()
        t.expect(!eeprom.touched && eeprom.pages.allSatisfy { !$0.touched }, "markSaved clears all")
    }

    await t.test("EEPROMBackup: survives a JSON round trip") {
        let original = EEPROMBackup(id: UUID(), ecmId: "BUEIB", version: "BUEIB999", ecmType: "DDFI-2",
                                    createdAt: Date(), name: "round trip", isAutomatic: false,
                                    xsize: 4, data: [1, 2, 3, 4])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EEPROMBackup.self, from: encoded)
        t.expectEqual(decoded.id, original.id, "id")
        t.expectEqual(decoded.data, original.data, "data")
        t.expectEqual(decoded.ecmId, original.ecmId, "ecmId")
        t.expectEqual(decoded.isAutomatic, original.isAutomatic, "isAutomatic")
    }

    await t.test("VariableProvider: RPM runtime channel exists for BUEIB") {
        let rpm = VariableProvider.shared.getRtVariable(ecm: "BUEIB", name: Variables.RPM)
        t.expect(rpm != nil, "RPM variable")
        if let rpm {
            t.expect(rpm.offset >= 0 && rpm.offset < 107, "RPM offset inside RT packet")
        }
    }

    await t.test("VariableProvider: parses text-backed calibration values") {
        guard let tps = VariableProvider.shared.getRtVariable(ecm: "BUEIB", name: Variables.TPD),
              let clt = VariableProvider.shared.getRtVariable(ecm: "BUEIB", name: Variables.CLT) else {
            t.expect(false, "TPS and coolant channels should exist"); return
        }

        t.expect(abs(tps.scale - 0.1) < 0.000_001, "TPS scale parsed from SQLite text")
        t.expectEqual(tps.high, 900, "TPS upper range parsed from SQLite text")
        t.expect(abs(clt.translate + 40) < 0.000_001, "coolant translation parsed from SQLite text")

        var packet = [UInt8](repeating: 0, count: 107)
        packet[tps.offset] = 0xD2 // 1234, little endian
        packet[tps.offset + 1] = 0x04
        packet[clt.offset] = 0xBC // 700, little endian -> 30.0 °C
        packet[clt.offset + 1] = 0x02
        tps.refreshValue(from: packet)
        clt.refreshValue(from: packet)

        t.expect(abs((tps.rawValues[0] as? Double ?? 0) - 123.4) < 0.000_001, "TPS is scaled")
        t.expectEqual(clt.intValue, 30, "coolant is translated")
    }

    await t.test("TorqueData: reference data is populated") {
        t.expect(!TorqueData.categories.isEmpty, "categories present")
        let specCount = TorqueData.categories.reduce(0) { $0 + $1.specs.count }
        t.expect(specCount > 10, "has a useful number of specs (got \(specCount))")
    }

    // MARK: - Regression tests (REVIEW.md 2026-09-26)

    await t.test("PDU: init rejects a length past the end of the packet") {
        _ = await t.expectThrows("length > packet.count must throw") {
            _ = try PDU(packet: [0x01, 0x42, 0x00, 0x05, 0xFF, 0x02, 0x03, 0x04], length: 12)
        }
    }

    await t.test("PDU: setRequest rejects an out-of-bounds slice") {
        let data: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        _ = await t.expectThrows("pos+len past buffer end must throw") {
            _ = try PDU.setRequest(pageno: 3, offset: 2, data: data, pos: 8, len: 5)
        }
    }

    await t.test("Variable: updateValue refuses to write outside the buffer") {
        let v = Variable()
        v.type = .scalar
        v.size = 2
        v.width = 1
        v.offset = 100 // beyond any sane buffer
        v.initialize()
        v.rawValues[0] = 42.0
        var data = [UInt8](repeating: 0, count: 10)
        v.updateValue(into: &data)
        t.expect(data.allSatisfy { $0 == 0 }, "buffer untouched (no trap, no OOB write)")
    }

    await t.test("ECM: live reading restarts after a read error") {
        let port = FaultyRTPort()
        let ecm = ECM(command: ECMCommand(port: port))
        ecm.startReading()

        // The loop must fail on its first read...
        let deadline = Date().addingTimeInterval(2)
        while await port.readAttempts < 1, Date() < deadline { await sleepMs(5) }
        let firstAttempts = await port.readAttempts
        t.expect(firstAttempts >= 1, "read loop made an attempt")

        // ...and its failed run must have cleaned up (isReading back to false).
        while ecm.isReading, Date() < deadline { await sleepMs(5) }
        t.expect(!ecm.isReading, "failed run cleared isReading")

        // ...so restarting must actually start a new loop. Before the fix the
        // stale task made this a permanent no-op.
        ecm.startReading()
        let restartDeadline = Date().addingTimeInterval(2)
        while await port.readAttempts <= firstAttempts, Date() < restartDeadline { await sleepMs(5) }
        t.expect(await port.readAttempts > firstAttempts,
                 "read loop restarted after error (\(firstAttempts) -> \(await port.readAttempts))")
        ecm.stopReading()
    }

    await t.test("ECMCommand: concurrent requests both complete (single-flight gate)") {
        // A strict request/response device: each write queues one in-flight
        // answer, and clearBuffer() destroys whatever is in flight. If two
        // callers (as in the monitor poll racing the data-log poll) were to
        // interleave, the second's clearBuffer would discard the first's answer.
        let response = PDU(sender: PDU.getECMID(), recipient: PDU.DROID_ID, payload: [PDU.ACK, 0x11, 0x22])
        let port = StrictECMPort(response: response.bytes)
        let command = ECMCommand(port: port)

        let results = await withTaskGroup(of: Result<[UInt8], Error>.self) { group in
            var out: [Result<[UInt8], Error>] = []
            for _ in 0..<2 {
                group.addTask {
                    do { return .success(try await command.readRTData()) }
                    catch { return .failure(error) }
                }
            }
            for await r in group { out.append(r) }
            return out
        }

        t.expectEqual(results.count, 2, "two responses collected")
        for (i, r) in results.enumerated() {
            switch r {
            case .success(let bytes):
                t.expectEqual(bytes.count, response.bytes.count, "reader \(i) got the full response")
            case .failure(let error):
                t.expect(false, "reader \(i) failed: \(error.localizedDescription)")
            }
        }
    }
}
