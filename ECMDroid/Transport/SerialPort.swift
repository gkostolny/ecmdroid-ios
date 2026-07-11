// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

/// Byte-stream transport to an ECM. The BLE dongle (BLESerialPort) and the TCP
/// connection to the ecmsim simulator (TCPSerialPort) both provide this, so the
/// protocol layer (ECMCommand) doesn't care which one it's talking through.
protocol SerialPort: Actor {
    /// Read exactly `count` bytes, waiting up to `timeout` for them to arrive.
    func read(count: Int, timeout: TimeInterval) async throws -> [UInt8]
    /// Send bytes to the ECM.
    func write(_ data: [UInt8]) async throws
    /// Discard any buffered input (called before each command so stale bytes from
    /// a timed-out exchange can't misalign the next response header).
    func clearBuffer()
}
