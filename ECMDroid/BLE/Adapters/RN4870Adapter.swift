// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import CoreBluetooth

class RN4870Adapter: BLEAdapter {
    static let serviceUUIDValue = CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455")
    static let charRW = CBUUID(string: "49535343-1E4D-4BD9-BA61-23C647249616")

    let serviceUUID = serviceUUIDValue
    weak var delegate: BLEAdapterDelegate?

    private var _readChar: CBCharacteristic?
    private var _writeChar: CBCharacteristic?

    func configureCharacteristics(service: CBService, peripheral: CBPeripheral) -> Bool {
        guard let chars = service.characteristics else { return false }
        for char in chars {
            if char.uuid == RN4870Adapter.charRW {
                _readChar = char
                _writeChar = char
            }
        }
        return _readChar != nil && _writeChar != nil
    }

    func readCharacteristic() -> CBCharacteristic? { _readChar }
    func writeCharacteristic() -> CBCharacteristic? { _writeChar }
}
