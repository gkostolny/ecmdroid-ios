// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import CoreBluetooth

class NRFAdapter: BLEAdapter {
    static let serviceUUIDValue = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let charRW2 = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let charRW3 = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    let serviceUUID = serviceUUIDValue
    weak var delegate: BLEAdapterDelegate?

    private var _readChar: CBCharacteristic?
    private var _writeChar: CBCharacteristic?

    func configureCharacteristics(service: CBService, peripheral: CBPeripheral) -> Bool {
        guard let chars = service.characteristics else { return false }

        var rw2: CBCharacteristic?
        var rw3: CBCharacteristic?

        for char in chars {
            if char.uuid == NRFAdapter.charRW2 { rw2 = char }
            if char.uuid == NRFAdapter.charRW3 { rw3 = char }
        }

        guard let c2 = rw2, let c3 = rw3 else { return false }

        let rw2write = c2.properties.contains(.write) || c2.properties.contains(.writeWithoutResponse)
        let rw3write = c3.properties.contains(.write) || c3.properties.contains(.writeWithoutResponse)

        if rw2write && rw3write {
            delegate?.adapterDidFailToConnect(error: BLEError.multipleWriteCharacteristics)
            return false
        } else if rw2write {
            _writeChar = c2
            _readChar = c3
        } else if rw3write {
            _writeChar = c3
            _readChar = c2
        } else {
            delegate?.adapterDidFailToConnect(error: BLEError.noWriteCharacteristic)
            return false
        }

        return true
    }

    func readCharacteristic() -> CBCharacteristic? { _readChar }
    func writeCharacteristic() -> CBCharacteristic? { _writeChar }
}
