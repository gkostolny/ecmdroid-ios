// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "org.ecmdroid.ios", category: "TCP")

enum TCPPortError: LocalizedError {
    case invalidPort
    case connectFailed(String)
    case timeout
    case disconnected

    var errorDescription: String? {
        switch self {
        case .invalidPort: return "Invalid TCP port"
        case .connectFailed(let msg): return "Connection failed: \(msg)"
        case .timeout: return "Timeout"
        case .disconnected: return "Disconnected"
        }
    }
}

/// TCP transport for the ecmsim ECM simulator (github.com/ecmdroid/ecmsim,
/// default port 6275). Feature parity with the Android app's TCP/IP connection
/// type: the full protocol stack can be exercised against a simulated ECM —
/// including in the iOS Simulator, which has no Bluetooth.
actor TCPSerialPort: SerialPort {
    private let connection: NWConnection
    private var buffer: [UInt8] = []
    private var readContinuations: [CheckedContinuation<Void, Never>] = []
    private var state: State = .connecting

    private enum State {
        case connecting
        case ready
        case failed(Error)
    }

    static func connect(host: String, port: UInt16, timeout: TimeInterval = 10) async throws -> TCPSerialPort {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw TCPPortError.invalidPort
        }
        let params = NWParameters.tcp
        // Small request/response PDUs: don't let Nagle hold them back.
        if let tcpOptions = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        let serialPort = TCPSerialPort(connection: connection)
        try await serialPort.start(timeout: timeout)
        return serialPort
    }

    private init(connection: NWConnection) {
        self.connection = connection
    }

    private func start(timeout: TimeInterval) async throws {
        connection.stateUpdateHandler = { [weak self] nwState in
            guard let self else { return }
            switch nwState {
            case .ready:
                logger.info("TCP connection ready")
                Task { await self.markReady() }
            case .failed(let error):
                logger.error("TCP connection failed: \(error.localizedDescription, privacy: .public)")
                Task { await self.markFailed(error) }
            case .waiting(let error):
                // NWConnection parks refused/unreachable connections in .waiting and
                // retries until connectivity changes. For a deliberate connect to a
                // known address that's wrong UX — surface the error immediately
                // instead of burning the whole connect timeout.
                logger.error("TCP connection waiting: \(error.localizedDescription, privacy: .public)")
                self.connection.cancel()
                Task { await self.markFailed(error) }
            case .cancelled:
                Task { await self.markFailed(TCPPortError.disconnected) }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            switch state {
            case .ready:
                startReceive()
                return
            case .failed(let error):
                throw TCPPortError.connectFailed(error.localizedDescription)
            case .connecting:
                if Date() > deadline {
                    connection.cancel()
                    throw TCPPortError.timeout
                }
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }

    private func markReady() {
        if case .connecting = state { state = .ready }
    }

    private func markFailed(_ error: Error) {
        if case .failed = state { return }
        state = .failed(error)
        // Wake pending reads so they can notice the failure instead of waiting
        // out their full timeout.
        wakeReaders()
    }

    private func startReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                if let data, !data.isEmpty {
                    await self.appendToBuffer(Array(data))
                }
                if let error {
                    await self.markFailed(error)
                } else if isComplete {
                    await self.markFailed(TCPPortError.disconnected)
                } else {
                    await self.continueReceive()
                }
            }
        }
    }

    private func continueReceive() {
        if case .ready = state { startReceive() }
    }

    private func appendToBuffer(_ data: [UInt8]) {
        logger.debug("RX \(data.count) bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
        buffer.append(contentsOf: data)
        wakeReaders()
    }

    private func wakeReaders() {
        for continuation in readContinuations {
            continuation.resume()
        }
        readContinuations.removeAll()
    }

    // MARK: - SerialPort

    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        let deadline = Date().addingTimeInterval(timeout)

        while buffer.count < count {
            if case .failed(let error) = state {
                throw error
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                throw TCPPortError.timeout
            }
            // Wait for a data/failure notification, or poll again after 50ms.
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

    func write(_ data: [UInt8]) async throws {
        if case .failed(let error) = state {
            throw error
        }
        logger.debug("TX \(data.count) bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(data), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    func clearBuffer() {
        buffer.removeAll()
    }

    func close() {
        connection.cancel()
        markFailed(TCPPortError.disconnected)
    }
}
