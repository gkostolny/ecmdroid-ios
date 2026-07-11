// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
@preconcurrency import CoreBluetooth
import os.log

private let logger = Logger(subsystem: "org.ecmdroid.ios", category: "Serial")

enum BLEError: LocalizedError {
    case notConnected
    case writeCharacteristicNotFound
    case multipleWriteCharacteristics
    case noWriteCharacteristic
    case noSerialProfile
    case timeout
    case disconnected

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected"
        case .writeCharacteristicNotFound: return "Write characteristic not found"
        case .multipleWriteCharacteristics: return "Multiple write characteristics"
        case .noWriteCharacteristic: return "No write characteristic"
        case .noSerialProfile: return "No serial profile found"
        case .timeout: return "Timeout"
        case .disconnected: return "Disconnected"
        }
    }
}

actor BLESerialPort: BLEAdapterDelegate, SerialPort {
    private let peripheral: CBPeripheral
    private let adapter: BLEAdapter
    private var buffer: [UInt8] = []
    private var readContinuations: [CheckedContinuation<Void, Never>] = []
    private var connected = false
    private var payloadSize: Int = 20

    private var writeBuffer: [[UInt8]] = []
    private var writePending = false

    init(peripheral: CBPeripheral, adapter: BLEAdapter) {
        self.peripheral = peripheral
        self.adapter = adapter
    }

    func setPayloadSize(_ size: Int) {
        payloadSize = size
    }

    /// Discard any buffered input. Called before sending a new command so that
    /// stale bytes from a previous timed-out exchange can't misalign the next
    /// response header — without this, one corrupted packet poisons every
    /// subsequent read on the connection.
    func clearBuffer() {
        buffer.removeAll()
    }

    nonisolated func adapterDidConnect() {
        Task { await markConnected() }
    }

    nonisolated func adapterDidFailToConnect(error: Error) {
        // Handled by BLEManager
    }

    nonisolated func adapterDidReceiveData(_ data: Data) {
        logger.debug("RX \(data.count) bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
        Task { await appendToBuffer(Array(data)) }
    }

    nonisolated func adapterDidEncounterError(_ error: Error) {
        // Handled by BLEManager
    }

    private func markConnected() {
        connected = true
    }

    private func appendToBuffer(_ data: [UInt8]) {
        buffer.append(contentsOf: data)
        // Wake up any waiting readers
        for continuation in readContinuations {
            continuation.resume()
        }
        readContinuations.removeAll()
    }

    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        let deadline = Date().addingTimeInterval(timeout)

        while buffer.count < count {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                throw BLEError.timeout
            }

            // Wait for data notification or timeout
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                readContinuations.append(continuation)
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(min(remaining, 0.05) * 1_000_000_000))
                    self.wakeReaders()
                }
            }
        }

        let result = Array(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }

    private func wakeReaders() {
        for continuation in readContinuations {
            continuation.resume()
        }
        readContinuations.removeAll()
    }

    func write(_ data: [UInt8]) async throws {
        guard let writeChar = adapter.writeCharacteristic() else {
            throw BLEError.writeCharacteristicNotFound
        }
        logger.debug("TX \(data.count) bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")

        // Chunk data by payload size
        var chunks: [[UInt8]] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + payloadSize, data.count)
            chunks.append(Array(data[offset..<end]))
            offset = end
        }

        let writeType: CBCharacteristicWriteType =
            writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse

        for chunk in chunks {
            // iOS silently drops writes-without-response when its internal queue
            // is full, so wait until the stack reports ready. Also respects
            // adapter-level flow control (Telit write credits). Bounded at ~1s;
            // a stack that still isn't ready by then would swallow the write,
            // so fail the command instead of sending into the void.
            if writeType == .withoutResponse {
                var attempts = 0
                while true {
                    let stackReady = await MainActor.run {
                        self.peripheral.canSendWriteWithoutResponse
                    }
                    if stackReady && adapter.canWrite() { break }
                    attempts += 1
                    if attempts >= 100 { throw BLEError.timeout }
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
            }

            let chunkData = Data(chunk)
            await MainActor.run {
                self.peripheral.writeValue(chunkData, for: writeChar, type: writeType)
            }

            // Small delay between chunks to avoid overwhelming the BLE stack
            if chunks.count > 1 {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
    }
}
