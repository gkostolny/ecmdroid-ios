// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import CoreBluetooth

class CC254xAdapter: BLEAdapter {
    static let serviceUUIDValue = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    static let charRW = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    static let charTX = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")

    let serviceUUID = serviceUUIDValue
    weak var delegate: BLEAdapterDelegate?

    private var _readChar: CBCharacteristic?
    private var _writeChar: CBCharacteristic?

    func configureCharacteristics(service: CBService, peripheral: CBPeripheral) -> Bool {
        guard let chars = service.characteristics else { return false }

        var ffe1: CBCharacteristic?
        var ffe2: CBCharacteristic?
        for char in chars {
            if char.uuid == CC254xAdapter.charRW { ffe1 = char }
            if char.uuid == CC254xAdapter.charTX { ffe2 = char }
        }

        guard let readChar = ffe1 else { return false }
        _readChar = readChar

        // Two firmware layouts exist for this service:
        //  - classic HM-10: FFE1 handles both notify and write
        //  - split variant (e.g. BUELLtooth): FFE1 is notify-only, FFE2 is write-only
        let ffe1Writable = readChar.properties.contains(.write) || readChar.properties.contains(.writeWithoutResponse)
        if ffe1Writable {
            _writeChar = readChar
        } else if let tx = ffe2,
                  tx.properties.contains(.write) || tx.properties.contains(.writeWithoutResponse) {
            _writeChar = tx
        }

        return _readChar != nil && _writeChar != nil
    }

    func readCharacteristic() -> CBCharacteristic? { _readChar }
    func writeCharacteristic() -> CBCharacteristic? { _writeChar }
}
