// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import CoreBluetooth

class TelitTIOAdapter: BLEAdapter {
    static let serviceUUIDValue = CBUUID(string: "0000FEFB-0000-1000-8000-00805F9B34FB")
    static let charTX = CBUUID(string: "00000001-0000-1000-8000-008025000000")
    static let charRX = CBUUID(string: "00000002-0000-1000-8000-008025000000")
    static let charTXCredits = CBUUID(string: "00000003-0000-1000-8000-008025000000")
    static let charRXCredits = CBUUID(string: "00000004-0000-1000-8000-008025000000")

    let serviceUUID = serviceUUIDValue
    weak var delegate: BLEAdapterDelegate?

    private var _readChar: CBCharacteristic?
    private var _writeChar: CBCharacteristic?
    private var readCreditsChar: CBCharacteristic?
    private var writeCreditsChar: CBCharacteristic?

    private var readCredits: Int = 0
    private var writeCredits: Int = 0
    private let lock = NSLock()

    private weak var _peripheral: CBPeripheral?

    func configureCharacteristics(service: CBService, peripheral: CBPeripheral) -> Bool {
        guard let chars = service.characteristics else { return false }
        _peripheral = peripheral

        for char in chars {
            switch char.uuid {
            case TelitTIOAdapter.charRX: _readChar = char
            case TelitTIOAdapter.charTX: _writeChar = char
            case TelitTIOAdapter.charRXCredits: readCreditsChar = char
            case TelitTIOAdapter.charTXCredits: writeCreditsChar = char
            default: break
            }
        }

        guard _readChar != nil, _writeChar != nil, readCreditsChar != nil, writeCreditsChar != nil else {
            return false
        }

        // Enable notification on read credits characteristic
        guard let rcChar = readCreditsChar else { return false }
        peripheral.setNotifyValue(true, for: rcChar)

        // Return false to indicate async setup continues in onDescriptorWrite
        return false
    }

    func readCharacteristic() -> CBCharacteristic? { _readChar }
    func writeCharacteristic() -> CBCharacteristic? { _writeChar }

    func canWrite() -> Bool {
        lock.lock()
        let credits = writeCredits
        lock.unlock()
        return credits > 0
    }

    func onDescriptorWrite(peripheral: CBPeripheral, descriptor: CBDescriptor, error: Error?) {
        if let rcChar = readCreditsChar, descriptor.characteristic == rcChar {
            if error != nil {
                delegate?.adapterDidFailToConnect(error: error!)
            }
            // Read credits descriptor is written; now the main connectCharacteristics flow continues
        }
        if let readC = _readChar, descriptor.characteristic == readC {
            // Main read descriptor written; set write types and grant read credits
            grantReadCredits()
        }
    }

    func onNotificationStateUpdated(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        // iOS never reports CCCD writes made via setNotifyValue through
        // didWriteValueFor:descriptor:, so onDescriptorWrite alone would leave the
        // peripheral with zero read credits and it would never send anything.
        // Grant the initial credits once notifications on the read characteristic
        // are confirmed active.
        if characteristic == _readChar {
            grantReadCredits()
        }
    }

    func onCharacteristicChanged(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        if characteristic == readCreditsChar {
            if let value = characteristic.value, !value.isEmpty {
                let newCredits = Int(value[0])
                lock.lock()
                writeCredits += newCredits
                lock.unlock()
            }
        }
        if characteristic == _readChar {
            grantReadCredits()
        }
    }

    func onCharacteristicWrite(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        if characteristic == _writeChar {
            lock.lock()
            if writeCredits > 0 {
                writeCredits -= 1
            }
            lock.unlock()
        }
    }

    func disconnect() {
        readCreditsChar = nil
        writeCreditsChar = nil
        _peripheral = nil
    }

    private func grantReadCredits() {
        let minReadCredits = 16
        let maxReadCredits = 64

        lock.lock()
        if readCredits > 0 {
            readCredits -= 1
        }
        if readCredits <= minReadCredits {
            let newCredits = maxReadCredits - readCredits
            readCredits += newCredits
            lock.unlock()

            guard let wcChar = writeCreditsChar, let peripheral = _peripheral else { return }
            let data = Data([UInt8(newCredits & 0xFF)])
            peripheral.writeValue(data, for: wcChar, type: .withoutResponse)
        } else {
            lock.unlock()
        }
    }
}
