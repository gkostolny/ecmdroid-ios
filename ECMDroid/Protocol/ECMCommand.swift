// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

actor ECMCommand {
    private let port: any SerialPort
    // Real BLE round-trip latency (connection interval) plus 9600-baud serial transfer
    // through the dongle can exceed 1s for larger responses, especially the first
    // exchange right after connecting. 1.0s caused spurious "Timeout reading from ECM".
    private static let defaultTimeout: TimeInterval = 2.5

    init(port: any SerialPort) {
        self.port = port
    }

    // Single-flight gate: only one request/response cycle may be in flight at a
    // time. sendPDU() clears the port's input buffer before writing, so a second
    // concurrent caller (e.g. the monitor poll racing the data-log poll) would
    // discard the first caller's in-flight response bytes. The simulator
    // tolerates that (it re-serves on its next poll), but a real ECM over a
    // serial dongle desyncs until reconnect. Concurrent callers wait their turn
    // instead. A short poll is used rather than a waiter queue so a cancelled
    // caller can never wedge the gate.
    private var gateHeld = false

    private func acquireGate() async throws {
        while gateHeld {
            if Task.isCancelled { throw CancellationError() }
            try await Task.sleep(nanoseconds: 1_000_000) // 1 ms
        }
        gateHeld = true
    }

    private func releaseGate() {
        gateHeld = false
    }

    func sendPDU(_ pdu: PDU) async throws -> PDU {
        try await acquireGate()
        defer { releaseGate() }
        // Drop any stale bytes left over from a previous timed-out exchange so
        // the response header parses from a clean packet boundary.
        await port.clearBuffer()
        try await port.write(pdu.bytes)
        let response = try await receivePDU()
        guard response.isResponse else {
            throw ECMCommandError.invalidResponse("No valid response from ECM (wrong Protocol?)")
        }
        guard response.isACK else {
            throw ECMCommandError.notAcknowledged(errorCode: response.errorIndicator)
        }
        return response
    }

    func receivePDU() async throws -> PDU {
        // Read 6-byte header
        let header = try await port.read(count: 6, timeout: Self.defaultTimeout)
        guard header.count == 6 else {
            throw ECMCommandError.timeout
        }
        guard header[0] == PDU.SOH, header[4] == PDU.EOH, header[5] == PDU.SOT else {
            throw ECMCommandError.invalidResponse("Invalid header received")
        }
        let len = Int(header[3])
        // Read payload + checksum
        let rest = try await port.read(count: len + 1, timeout: Self.defaultTimeout)
        guard rest.count == len + 1 else {
            throw ECMCommandError.timeout
        }
        let fullPacket = header + rest
        return try PDU(packet: fullPacket, length: fullPacket.count)
    }

    func readVersion() async throws -> String {
        let response = try await sendPDU(PDU.getVersion())
        let data = response.eepromData
        guard let version = String(bytes: data, encoding: .ascii) else {
            throw ECMCommandError.invalidResponse("Cannot decode version string")
        }
        return version
    }

    func readRTData() async throws -> [UInt8] {
        let response = try await sendPDU(PDU.getRuntimeData())
        return response.bytes
    }

    func getCurrentState() async throws -> UInt8 {
        let response = try await sendPDU(PDU.getCurrentState())
        let data = response.eepromData
        guard !data.isEmpty else {
            throw ECMCommandError.invalidResponse("Empty state response")
        }
        return data[0]
    }

    func isBusy() async throws -> Bool {
        return try await getCurrentState() != 0
    }

    func runTest(_ function: ECMFunction) async throws {
        let response = try await sendPDU(PDU.commandRequest(function))
        guard response.isACK else {
            throw ECMCommandError.testFailed
        }
    }

    func readEEPromPage(_ page: EEPROM.Page, into buffer: inout [UInt8]) async throws {
        var i = 0
        while i < page.length {
            var dtr = min(page.length - i, 16)
            var offset = i
            if page.nr == 0 {
                offset = 0xFF - page.length + i + 1
                dtr = 1
            }
            let response = try await sendPDU(PDU.getRequest(pageno: page.nr, offset: offset, len: dtr))
            let data = response.eepromData
            guard data.count == dtr else {
                throw ECMCommandError.invalidResponse("Requested \(dtr) bytes but received \(data.count)")
            }
            for j in 0..<dtr {
                buffer[page.start + i + j] = data[j]
            }
            i += dtr
        }
    }

    func writeEEPromPage(_ page: EEPROM.Page, from buffer: [UInt8]) async throws {
        var i = 0
        while i < page.length {
            var dtr = min(page.length - i, 16)
            var offset = i
            if page.nr == 0 {
                offset = 0xFF - page.length + i + 1
                dtr = 1
            }
            _ = try await sendPDU(try PDU.setRequest(pageno: page.nr, offset: offset, data: buffer, pos: page.start + offset, len: dtr))
            i += dtr
        }
    }

    func getErrors(ecmID: String, rtData: [UInt8]?, eepromData: [UInt8]?, eepromHasPageZero: Bool, type: ECMDiagError.ErrorType) async throws -> [ECMDiagError] {
        var fieldPattern: String
        var ds: DataSource
        var data: [UInt8]?

        if type == .current {
            fieldPattern = "CDiag%d"
            ds = .runtimeData
            data = rtData
        } else {
            fieldPattern = "HDiag%d_LD"
            ds = .runtimeData
            data = rtData
        }

        if data == nil {
            if type == .stored, let eepData = eepromData {
                fieldPattern = "HDiag%d"
                ds = .eeprom
                data = eepData
            } else {
                return []
            }
        }

        guard let activeData = data else { return [] }

        var errors: [ECMDiagError] = []
        let bitsetProvider = BitSetProvider.shared

        for i in 0... {
            let field = String(format: fieldPattern, i)
            guard let bitset = bitsetProvider.getBitSet(ecmID: ecmID, name: field, source: ds) else {
                break
            }
            if ds == .eeprom && bitset.offset < 0 && !eepromHasPageZero {
                continue
            }
            for bit in bitset {
                if bit.refreshValue(from: activeData) {
                    let error = ECMDiagError(
                        code: bit.code,
                        errorDescription: bit.remark,
                        type: type
                    )
                    errors.append(error)
                }
            }
        }
        return errors
    }
}

enum ECMCommandError: LocalizedError {
    case timeout
    case invalidResponse(String)
    case notAcknowledged(errorCode: UInt8)
    case testFailed

    var errorDescription: String? {
        switch self {
        case .timeout: return "Timeout reading from ECM"
        case .invalidResponse(let msg): return msg
        case .notAcknowledged(let code): return "Request not acknowledged (error code \(code))"
        case .testFailed: return "Test failed"
        }
    }
}
