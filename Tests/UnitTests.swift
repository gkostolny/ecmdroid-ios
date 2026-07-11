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
        let pdu = PDU.setRequest(pageno: 3, offset: 2, data: data, pos: 4, len: 3)
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

    await t.test("TorqueData: reference data is populated") {
        t.expect(!TorqueData.categories.isEmpty, "categories present")
        let specCount = TorqueData.categories.reduce(0) { $0 + $1.specs.count }
        t.expect(specCount > 10, "has a useful number of specs (got \(specCount))")
    }
}
