// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

// Main-actor isolated: every stored property feeds SwiftUI views, and isolation
// makes the class Sendable so its Task/MainActor.run closures capture it legally.
// ECM communication still runs off the main thread via the BLESerialPort and
// ECMCommand actors; this class only awaits their results.
@MainActor
@Observable
class ECM {
    static let shared = ECM()

    var isConnected = false
    var eeprom: EEPROM?
    var rtData: [UInt8]?
    var isReading = false
    var statusMessage: String = ""
    var currentProtocol: ECMProtocol = .stock

    /// Byte image the ECM currently holds: captured when the EEPROM is read and
    /// refreshed after each successful burn. This is the in-memory "discard edits"
    /// reference; the as-found image is also written to disk as an automatic backup.
    /// Reset on disconnect.
    var pristineData: [UInt8]?

    // Created on first use: CBCentralManager fires up Bluetooth (and its permission
    // machinery) the moment it's constructed, which TCP-only sessions — the ecmsim
    // path and the headless test suite — never need.
    private var _bleManager: BLEManager?
    private var bleManager: BLEManager {
        if let manager = _bleManager { return manager }
        let manager = BLEManager()
        manager.onConnectionLost = { [weak self] in
            Task { @MainActor in
                self?.handleTransportDisconnected()
            }
        }
        _bleManager = manager
        return manager
    }
    private var serialPort: (any SerialPort)?
    private var command: ECMCommand?
    private var readingTask: Task<Void, Never>?
    // Token identifying the currently running read loop, so a stale loop that is
    // dying (stopped or erroring) can't tear down state owned by a newer one.
    private var readingSessionID: UUID?
    private let variableProvider = VariableProvider.shared
    private let bitsetProvider = BitSetProvider.shared
    private let eepromProvider = EEPROMProvider.shared

    private static let unknown = "N/A"

    private init() {}

    /// Test seam: build an ECM around an already-constructed command (e.g. over a
    /// fake transport) so the connection state machine can be exercised without
    /// BLE or a live simulator. Not used by the app itself.
    init(command: ECMCommand) {
        self.command = command
        self.isConnected = true
    }

    var bleManagerInstance: BLEManager { bleManager }

    // MARK: - Connection

    func connect(peripheral: any Sendable, protocol proto: ECMProtocol) async throws {
        guard let device = peripheral as? DiscoveredDevice else {
            throw ECMCommandError.invalidResponse("Invalid device")
        }
        currentProtocol = proto
        PDU.setProtocol(proto)

        statusMessage = "Connecting..."
        let port = try await bleManager.connect(peripheral: device.peripheral)
        serialPort = port
        command = ECMCommand(port: port)
        isConnected = true
        statusMessage = "Connected"
    }

    /// Connect to an ecmsim simulator (or any TCP-attached ECM) instead of a BLE
    /// dongle. Same protocol stack, different transport — mirrors the Android
    /// app's TCP/IP connection type.
    func connect(host: String, port: UInt16, protocol proto: ECMProtocol) async throws {
        currentProtocol = proto
        PDU.setProtocol(proto)

        statusMessage = "Connecting to \(host):\(port)..."
        let tcpPort = try await TCPSerialPort.connect(host: host, port: port)
        serialPort = tcpPort
        command = ECMCommand(port: tcpPort)
        isConnected = true
        statusMessage = "Connected (TCP)"
    }

    func disconnect() {
        stopReading()
        stopRecording()
        _bleManager?.disconnect()
        if let tcpPort = serialPort as? TCPSerialPort {
            Task { await tcpPort.close() }
        }
        clearConnectionState(status: "Disconnected")
    }

    /// Called by BLEManager when a peripheral drops unexpectedly. This follows the
    /// same cleanup path as an explicit disconnect, but does not attempt to cancel
    /// a connection CoreBluetooth has already torn down.
    private func handleTransportDisconnected() {
        guard isConnected || serialPort != nil else { return }
        stopReading()
        stopRecording()
        clearConnectionState(status: "Connection lost")
    }

    private func clearConnectionState(status: String) {
        serialPort = nil
        command = nil
        isConnected = false
        rtData = nil
        pristineData = nil
        statusMessage = status
    }

    // MARK: - EEPROM Setup

    func setupEEPROM() async throws -> String {
        guard let cmd = command else {
            throw ECMCommandError.invalidResponse("Not connected")
        }

        statusMessage = "Reading ECM version..."
        let version = try await cmd.readVersion()

        guard let eeprom = eepromProvider.getEEPROM(name: version) else {
            throw ECMCommandError.invalidResponse("Unsupported ECM Version '\(version)'")
        }
        eeprom.version = version
        self.eeprom = eeprom
        statusMessage = "ECM: \(version)"
        return version
    }

    // MARK: - Runtime Data

    func startReading() {
        guard readingTask == nil else { return }
        isReading = true
        let sessionID = UUID()
        readingSessionID = sessionID
        readingTask = Task { [weak self] in
            while !Task.isCancelled {
                // Stop if this run is no longer the current session (a stop or a
                // restart raced us while we were in flight).
                let current = await MainActor.run { self?.readingSessionID == sessionID }
                guard current else { break }
                let cmd = await MainActor.run { self?.command }
                guard let cmd else { break }
                do {
                    let data = try await cmd.readRTData()
                    await MainActor.run {
                        guard let self, self.readingSessionID == sessionID else { return }
                        self.rtData = data
                    }
                } catch {
                    await MainActor.run {
                        guard let self, self.readingSessionID == sessionID else { return }
                        self.statusMessage = "Read error: \(error.localizedDescription)"
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
            }
            // Loop exited (stopped, cancelled, or error). Clear state only if this
            // run is still the current session, so a stale loop can't tear down a
            // newer one. Crucially this also clears readingTask itself: a run that
            // ended in an error used to leave a live task behind, which made every
            // later startReading() a permanent no-op until reconnection.
            await MainActor.run {
                guard let self, self.readingSessionID == sessionID else { return }
                self.readingSessionID = nil
                self.readingTask = nil
                self.isReading = false
            }
        }
    }

    func stopReading() {
        // Invalidate the session first so the dying loop skips its own cleanup.
        readingSessionID = nil
        readingTask?.cancel()
        readingTask = nil
        isReading = false
    }

    func readRTDataOnce() async throws {
        guard let cmd = command else { return }
        rtData = try await cmd.readRTData()
    }

    // MARK: - EEPROM Read/Write

    func readEEPROM() async throws {
        guard let cmd = command, let eeprom = eeprom else { return }

        statusMessage = "Reading EEPROM..."
        for page in eeprom.pages {
            statusMessage = "Reading page \(page.nr)..."
            try await cmd.readEEPromPage(page, into: &eeprom.data)
        }
        eeprom.eepromRead = true
        // Fresh authoritative copy from the ECM: clear any leftover dirty flags so the
        // editor doesn't think there are pending changes.
        eeprom.markSaved()
        // Capture the pristine image for in-memory revert, and write a durable
        // automatic backup so the as-found configuration survives even edits + burns.
        pristineData = eeprom.data
        autoBackup(for: eeprom)
        statusMessage = "EEPROM read complete"
    }

    func writeEEPROM() async throws {
        guard let cmd = command, let eeprom = eeprom else { return }

        statusMessage = "Writing EEPROM..."
        // Page 0 is never written: the protocol's page-0 write path is unsupported
        // (the original ECMDroid skips it too — "We don't handle page 0 for now").
        for page in eeprom.pages where page.touched && page.nr != 0 {
            statusMessage = "Writing page \(page.nr)..."
            try await cmd.writeEEPromPage(page, from: eeprom.data)
            // Clear per page so a failure mid-burn doesn't rewrite completed pages on retry.
            page.saved()
        }
        eeprom.markSaved()
        statusMessage = "EEPROM write complete"
    }

    // MARK: - Tests

    func runTest(_ function: ECMFunction) async throws {
        guard let cmd = command else { return }
        try await cmd.runTest(function)
    }

    func isBusy() async throws -> Bool {
        guard let cmd = command else { return false }
        return try await cmd.isBusy()
    }

    // MARK: - EEPROM Bit Access

    func getEEPROMBit(name: String, bitNr: Int) -> Bit? {
        guard let ecmID = id, let eeprom = eeprom else { return nil }
        guard let bitset = bitsetProvider.getBitSet(ecmID: ecmID, name: name, source: .eeprom) else { return nil }
        guard let bit = bitset.getBit(bitNr) else { return nil }
        if bit.offset < 0 && !eeprom.hasPageZero { return nil }
        bit.refreshValue(from: eeprom.data)
        return bit
    }

    // MARK: - Recording support

    var isRecording = false
    private var recordingTask: Task<Void, Never>?
    private var recordingSessionID: UUID?
    private var logOutputStream: OutputStream?
    var bytesLogged: Int = 0
    var recordsLogged: Int = 0
    private var recordingStartTime: Date?
    var recordingInterval: TimeInterval = 0.25

    func startRecording(to url: URL, interval: TimeInterval) throws {
        guard isConnected, !isRecording else { return }
        guard let stream = OutputStream(url: url, append: false) else {
            throw ECMCommandError.invalidResponse("Cannot open log file")
        }
        stream.open()
        logOutputStream = stream

        // Write 5-byte header (ECM ID or "UNKWN")
        let idString = eeprom?.id ?? "UNKWN"
        let headerBytes = Array(idString.utf8.prefix(5))
        var header = [UInt8](repeating: 0x20, count: 5)
        for (i, b) in headerBytes.enumerated() { header[i] = b }
        guard Self.writeFully(header, to: stream) else {
            stream.close()
            logOutputStream = nil
            throw ECMCommandError.invalidResponse("Cannot write to log file")
        }

        bytesLogged = 5
        recordsLogged = 0
        recordingStartTime = Date()
        recordingInterval = interval
        isRecording = true
        let sessionID = UUID()
        recordingSessionID = sessionID

        recordingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      let cmd = self.command,
                      self.isRecording,
                      self.recordingSessionID == sessionID else { break }
                do {
                    let data = try await cmd.readRTData()
                    guard self.isRecording, self.recordingSessionID == sessionID else { break }
                    await MainActor.run {
                        self.rtData = data
                    }
                    self.logPacket(data)
                } catch {
                    await MainActor.run { [weak self] in
                        self?.statusMessage = "Recording error: \(error.localizedDescription)"
                    }
                    break
                }
                let ns = UInt64(max(self.recordingInterval, 0.05) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
            await MainActor.run { [weak self] in
                self?.finishRecording(sessionID: sessionID)
            }
        }
    }

    private func logPacket(_ data: [UInt8]) {
        guard let stream = logOutputStream, let startTime = recordingStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let centiseconds = Int32(elapsed * 100)

        // Record layout: [2-byte BE packet length][4-byte BE timestamp (centiseconds)]
        // [full RT PDU packet]. Storing the entire packet — not just the payload — lets
        // the exporter decode each record with the exact same variable offsets the live
        // view uses (RT offsets are relative to the full packet). The length prefix makes
        // the log self-describing, so conversion never has to guess the record size.
        let len = min(data.count, 0xFFFF)
        var record = [UInt8]()
        record.reserveCapacity(6 + len)
        record.append(UInt8((len >> 8) & 0xFF))
        record.append(UInt8(len & 0xFF))
        record.append(UInt8((centiseconds >> 24) & 0xFF))
        record.append(UInt8((centiseconds >> 16) & 0xFF))
        record.append(UInt8((centiseconds >> 8) & 0xFF))
        record.append(UInt8(centiseconds & 0xFF))
        record.append(contentsOf: data.prefix(len))

        guard Self.writeFully(record, to: stream) else {
            statusMessage = "Recording error: could not write to log file"
            stopRecording()
            return
        }

        bytesLogged += record.count
        recordsLogged += 1
    }

    static let logFormatMagicHeaderLength = 5

    /// OutputStream.write may consume fewer bytes than asked (or fail outright);
    /// loop until everything is on disk so a short write can't corrupt the log.
    private static func writeFully(_ bytes: [UInt8], to stream: OutputStream) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBufferPointer { buf in
                stream.write(buf.baseAddress!, maxLength: buf.count)
            }
            if written <= 0 { return false }
            offset += written
        }
        return true
    }

    func stopRecording() {
        recordingSessionID = nil
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        logOutputStream?.close()
        logOutputStream = nil
        recordingStartTime = nil
    }

    private func finishRecording(sessionID: UUID) {
        // A cancelled task from an older recording can finish after a new session
        // starts. Only the task that owns the active session may close its stream.
        guard recordingSessionID == sessionID else { return }
        recordingSessionID = nil
        recordingTask = nil
        isRecording = false
        logOutputStream?.close()
        logOutputStream = nil
        recordingStartTime = nil
    }

    // MARK: - Errors

    func getErrors(type: ECMDiagError.ErrorType) async throws -> [ECMDiagError] {
        guard let cmd = command, let ecmID = id else { return [] }

        // Ensure we have RT data
        if rtData == nil && isConnected {
            try await readRTDataOnce()
        }

        return try await cmd.getErrors(
            ecmID: ecmID,
            rtData: rtData,
            eepromData: eeprom?.data,
            eepromHasPageZero: eeprom?.hasPageZero ?? false,
            type: type
        )
    }

    // MARK: - Variable Access

    func getRuntimeValue(_ name: String) -> Variable? {
        guard let ecmID = id else { return nil }
        guard let v = variableProvider.getRtVariable(ecm: ecmID, name: name) else { return nil }
        if let data = rtData {
            v.refreshValue(from: data)
        }
        return v
    }

    func getEEPROMValue(_ name: String) -> Variable? {
        guard let ecmID = id, let eeprom = eeprom else { return nil }
        guard let v = variableProvider.getEEPROMVariable(ecm: ecmID, name: name) else { return nil }
        if v.offset < 0 && !eeprom.hasPageZero { return nil }
        v.refreshValue(from: eeprom.data)
        return v
    }

    func getFormattedEEPROMValue(_ name: String, defaultValue: String = "N/A") -> String {
        guard let v = getEEPROMValue(name) else { return defaultValue }
        let formatted = v.formattedValue
        return formatted.isEmpty ? defaultValue : formatted
    }

    // MARK: - Computed Properties

    var id: String? { eeprom?.id }

    var version: String? { eeprom?.version }

    var ecmType: ECMType? { eeprom?.type }

    var serialNo: String {
        getFormattedEEPROMValue(Variables.KMFG_Serial)
    }

    var mfgDate: String {
        guard let yearStr = getEEPROMValue(Variables.KMFG_Year)?.formattedValue,
              let dayStr = getEEPROMValue(Variables.KMFG_Day)?.formattedValue,
              let yearInt = Int(yearStr),
              let dayInt = Int(dayStr) else {
            return ECM.unknown
        }
        var y = yearInt + 2000
        if y >= 2090 { y -= 100 }
        let d = dayInt + 1
        var components = DateComponents()
        components.year = y
        components.day = d
        guard let date = Calendar.current.date(from: components) else { return ECM.unknown }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var countryID: String {
        let idStr = getFormattedEEPROMValue(Variables.Country_ID)
        if idStr == "255" {
            let s = getFormattedEEPROMValue(Variables.KID_Series, defaultValue: "?")
            let m = getFormattedEEPROMValue(Variables.KID_Market, defaultValue: "?")
            let v = getFormattedEEPROMValue(Variables.KID_Version, defaultValue: "?")
            return "S\(s)-M\(m)-V\(v)"
        }
        return idStr
    }

    var calibrationID: String {
        getFormattedEEPROMValue(Variables.Cal_ID)
    }

    var layoutRevision: String {
        getFormattedEEPROMValue(Variables.CSR)
    }

    var isEEPROMRead: Bool {
        eeprom?.eepromRead ?? false
    }
}
