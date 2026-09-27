// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

struct PDU {
    static let CMD_RTDATA: UInt8 = 0x43
    static let CMD_SET: UInt8 = 0x57
    static let CMD_GET: UInt8 = 0x52
    static let CMD_VERSION: UInt8 = 0x56
    static let ACK: UInt8 = 0x06
    static let DROID_ID: UInt8 = 0x00
    static let STOCK_ECM_ID: UInt8 = 0x42
    static let RACE_ECM_ID: UInt8 = 0x55

    static let SOH: UInt8 = 0x01
    static let EOH: UInt8 = 0xFF
    static let SOT: UInt8 = 0x02
    static let EOT: UInt8 = 0x03

    private(set) var bytes: [UInt8]

    private static var ecmID: UInt8 = STOCK_ECM_ID

    static func setProtocol(_ proto: ECMProtocol) {
        let id: UInt8 = (proto == .factoryRace) ? RACE_ECM_ID : STOCK_ECM_ID
        ecmID = id
    }

    static func getECMID() -> UInt8 {
        return ecmID
    }

    // MARK: - Factory methods

    static func getVersion() -> PDU {
        return PDU(sender: DROID_ID, recipient: ecmID, payload: [CMD_VERSION])
    }

    static func getRuntimeData() -> PDU {
        return PDU(sender: DROID_ID, recipient: ecmID, payload: [CMD_RTDATA])
    }

    static func getCurrentState() -> PDU {
        return getRequest(pageno: 0x20, offset: 0, len: 1)
    }

    static func getRequest(pageno: Int, offset: Int, len: Int) -> PDU {
        let payload: [UInt8] = [
            CMD_GET,
            UInt8(offset & 0xFF),
            UInt8(pageno & 0xFF),
            UInt8(len & 0xFF)
        ]
        return PDU(sender: DROID_ID, recipient: ecmID, payload: payload)
    }

    static func setRequest(pageno: Int, offset: Int, data: [UInt8], pos: Int, len: Int) throws -> PDU {
        guard len >= 0, pos >= 0, pos + len <= data.count else {
            throw PDUError.outOfBounds("SET slice out of bounds: pos \(pos), len \(len), buffer \(data.count)")
        }
        var payload = [UInt8](repeating: 0, count: 3 + len)
        payload[0] = CMD_SET
        payload[1] = UInt8(offset & 0xFF)
        payload[2] = UInt8(pageno & 0xFF)
        for i in 0..<len {
            payload[3 + i] = data[pos + i]
        }
        return PDU(sender: DROID_ID, recipient: ecmID, payload: payload)
    }

    static func commandRequest(_ function: ECMFunction) -> PDU {
        return PDU(sender: DROID_ID, recipient: ecmID, payload: [CMD_SET, 0, 0x20, UInt8(function.rawValue & 0xFF)])
    }

    // MARK: - Init from raw packet (received)

    init(packet: [UInt8], length: Int) throws {
        guard length >= 0, length <= packet.count else {
            throw PDUError.shortPacket
        }
        self.bytes = Array(packet[0..<length])
        try validate()
    }

    private func validate() throws {
        guard bytes.count >= 9 else {
            throw PDUError.shortPacket
        }
        guard bytes[0] == PDU.SOH else {
            throw PDUError.invalidHeader("No SOH")
        }
        guard bytes[4] == PDU.EOH else {
            throw PDUError.invalidHeader("No EOH")
        }
        guard bytes[5] == PDU.SOT else {
            throw PDUError.invalidHeader("No SOT")
        }
        let size = Int(bytes[3])
        guard bytes.count - 7 == size else {
            throw PDUError.sizeMismatch(expected: size, actual: bytes.count - 7)
        }
        guard bytes[bytes.count - 2] == PDU.EOT else {
            throw PDUError.invalidHeader("No EOT")
        }
        let cs = checksum()
        guard cs == bytes[bytes.count - 1] else {
            throw PDUError.checksumMismatch(expected: cs, actual: bytes[bytes.count - 1])
        }
    }

    // MARK: - Init from components (sending)

    init(sender: UInt8, recipient: UInt8, payload: [UInt8]) {
        var pdu = [UInt8](repeating: 0, count: payload.count + 8)
        var i = 0
        pdu[i] = PDU.SOH; i += 1
        pdu[i] = sender; i += 1
        pdu[i] = recipient; i += 1
        pdu[i] = UInt8((payload.count + 1) & 0xFF); i += 1
        pdu[i] = PDU.EOH; i += 1
        pdu[i] = PDU.SOT; i += 1
        for b in payload {
            pdu[i] = b; i += 1
        }
        pdu[i] = PDU.EOT; i += 1
        self.bytes = pdu
        // Compute checksum and store
        self.bytes[i] = checksum()
    }

    // MARK: - Accessors

    var sender: UInt8 { bytes[1] }
    var recipient: UInt8 { bytes[2] }
    var dataLength: Int { Int(bytes[3]) }

    var payload: [UInt8] {
        let len = dataLength - 1
        guard len > 0, 6 + len <= bytes.count else { return [] }
        return Array(bytes[6..<(6 + len)])
    }

    var eepromData: [UInt8] {
        let headerSize = isRequest ? 4 : 2
        let len = dataLength - headerSize
        let start = isRequest ? 9 : 7
        guard len > 0, start + len <= bytes.count else { return [] }
        return Array(bytes[start..<(start + len)])
    }

    var pageNr: Int {
        guard isRequest, bytes.count > 8, (bytes[6] == PDU.CMD_GET || bytes[6] == PDU.CMD_SET) else { return -1 }
        return Int(bytes[8])
    }

    var pageOffset: Int {
        guard isRequest, bytes.count > 7, (bytes[6] == PDU.CMD_GET || bytes[6] == PDU.CMD_SET) else { return -1 }
        return Int(bytes[7])
    }

    var command: UInt8 {
        isRequest ? bytes[6] : 0
    }

    var errorIndicator: UInt8 {
        isResponse ? bytes[6] : 0
    }

    var isACK: Bool {
        isResponse && bytes[6] == PDU.ACK
    }

    var isRequest: Bool {
        recipient == PDU.ecmID
    }

    var isResponse: Bool {
        sender == PDU.ecmID
    }

    // MARK: - Checksum

    private func checksum() -> UInt8 {
        var cs: UInt8 = 0
        for i in 1..<(bytes.count - 1) {
            cs ^= bytes[i]
        }
        return cs
    }

    var hexDump: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

enum PDUError: LocalizedError {
    case shortPacket
    case invalidHeader(String)
    case sizeMismatch(expected: Int, actual: Int)
    case checksumMismatch(expected: UInt8, actual: UInt8)
    case outOfBounds(String)

    var errorDescription: String? {
        switch self {
        case .shortPacket: return "Short packet length"
        case .invalidHeader(let msg): return "Invalid header: \(msg)"
        case .sizeMismatch(let exp, let act): return "Size mismatch (\(exp)/\(act))"
        case .checksumMismatch(let exp, let act): return "Invalid checksum (\(String(format: "%02X", exp))/\(String(format: "%02X", act)))"
        case .outOfBounds(let msg): return msg
        }
    }
}
