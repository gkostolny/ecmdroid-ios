// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import CoreBluetooth

protocol BLEAdapterDelegate: AnyObject {
    func adapterDidConnect()
    func adapterDidFailToConnect(error: Error)
    func adapterDidReceiveData(_ data: Data)
    func adapterDidEncounterError(_ error: Error)
}

protocol BLEAdapter: AnyObject {
    var serviceUUID: CBUUID { get }
    var delegate: BLEAdapterDelegate? { get set }

    func configureCharacteristics(service: CBService, peripheral: CBPeripheral) -> Bool
    func canWrite() -> Bool
    func writeCharacteristic() -> CBCharacteristic?
    func readCharacteristic() -> CBCharacteristic?

    func onDescriptorWrite(peripheral: CBPeripheral, descriptor: CBDescriptor, error: Error?)
    func onNotificationStateUpdated(peripheral: CBPeripheral, characteristic: CBCharacteristic)
    func onCharacteristicChanged(peripheral: CBPeripheral, characteristic: CBCharacteristic)
    func onCharacteristicWrite(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?)
    func disconnect()
}

extension BLEAdapter {
    func onDescriptorWrite(peripheral: CBPeripheral, descriptor: CBDescriptor, error: Error?) {}
    func onNotificationStateUpdated(peripheral: CBPeripheral, characteristic: CBCharacteristic) {}
    func onCharacteristicChanged(peripheral: CBPeripheral, characteristic: CBCharacteristic) {}
    func onCharacteristicWrite(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {}
    func disconnect() {}
    func canWrite() -> Bool { true }
}

let BLUETOOTH_LE_CCCD = CBUUID(string: "00002902-0000-1000-8000-00805f9b34fb")
