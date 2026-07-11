// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation
import CoreBluetooth
import os.log

private let logger = Logger(subsystem: "org.ecmdroid.ios", category: "BLE")

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let advertisedName: String?
    let rssi: Int
    let advertisedServices: [CBUUID]

    // HM-10 style modules often only carry their name in the scan response,
    // where it shows up as the advertised local name rather than peripheral.name.
    var name: String { peripheral.name ?? advertisedName ?? id.uuidString }
    var hasName: Bool { peripheral.name != nil || advertisedName != nil }

    /// True when the device advertises one of the serial services this app can
    /// actually talk to (CC254x/NRF/RN4870/Telit) — almost certainly the adapter.
    var isSerialAdapter: Bool {
        advertisedServices.contains { BLEManager.knownServiceUUIDs.contains($0) }
    }

    init(peripheral: CBPeripheral, rssi: Int, advertisedName: String? = nil, advertisedServices: [CBUUID] = []) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.advertisedName = advertisedName
        self.rssi = rssi
        self.advertisedServices = advertisedServices
    }
}

@Observable
class BLEManager: NSObject {
    var discoveredDevices: [DiscoveredDevice] = []
    var isScanning = false
    var bluetoothState: CBManagerState = .unknown
    var connectedPeripheral: CBPeripheral?
    /// Called when an established peripheral disconnects without ECM initiating it.
    /// ECM uses this to clear its session and disable potentially unsafe controls.
    var onConnectionLost: (() -> Void)?

    private var centralManager: CBCentralManager!
    fileprivate var connectContinuation: CheckedContinuation<BLESerialPort, Error>?
    fileprivate var currentAdapter: BLEAdapter?
    fileprivate var currentSerialPort: BLESerialPort?
    private var peripheralDelegate: PeripheralDelegate?
    private var connectionTimeoutTask: Task<Void, Never>?

    /// Connection timeout in seconds
    private static let connectionTimeout: TimeInterval = 15

    static let knownServiceUUIDs: [CBUUID] = [
        CC254xAdapter.serviceUUIDValue,
        NRFAdapter.serviceUUIDValue,
        RN4870Adapter.serviceUUIDValue,
        TelitTIOAdapter.serviceUUIDValue
    ]

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        logger.info("BLEManager initialized")
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot start scan: Bluetooth state is \(String(describing: self.centralManager.state.rawValue), privacy: .public)")
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        logger.info("Starting BLE scan for all peripherals")
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        logger.info("Stopped BLE scan")
    }

    func connect(peripheral: CBPeripheral) async throws -> BLESerialPort {
        stopScan()
        guard connectContinuation == nil else {
            logger.warning("Connect requested while another connection attempt is in progress")
            throw BLEError.notConnected
        }
        logger.info("Initiating connection to \(peripheral.name ?? "Unknown", privacy: .public) (\(peripheral.identifier.uuidString, privacy: .public))")
        return try await withCheckedThrowingContinuation { continuation in
            self.connectContinuation = continuation
            self.centralManager.connect(peripheral, options: nil)
            self.startConnectionTimeout()
        }
    }

    func disconnect() {
        cancelConnectionTimeout()
        // Resolve any in-flight connection attempt so the caller isn't left hanging
        if let continuation = connectContinuation {
            connectContinuation = nil
            continuation.resume(throwing: BLEError.disconnected)
        }
        if let peripheral = connectedPeripheral {
            logger.info("Disconnecting from \(peripheral.name ?? "Unknown", privacy: .public)")
            centralManager.cancelPeripheralConnection(peripheral)
        }
        if let serialPort = currentSerialPort {
            Task { await serialPort.close() }
        }
        currentAdapter?.disconnect()
        currentAdapter = nil
        currentSerialPort = nil
        connectedPeripheral = nil
        peripheralDelegate = nil
    }

    // MARK: - Connection Timeout

    private func startConnectionTimeout() {
        cancelConnectionTimeout()
        connectionTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(BLEManager.connectionTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.handleConnectionTimeout()
        }
    }

    @MainActor
    private func handleConnectionTimeout() {
        guard let continuation = connectContinuation else { return }
        logger.error("Connection timed out after \(BLEManager.connectionTimeout, privacy: .public) seconds")
        connectContinuation = nil
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        currentAdapter = nil
        currentSerialPort = nil
        peripheralDelegate = nil
        continuation.resume(throwing: BLEError.timeout)
    }

    fileprivate func cancelConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        logger.info("Bluetooth state changed: \(String(describing: central.state.rawValue), privacy: .public) (\(self.bluetoothStateName(central.state), privacy: .public))")
        if central.state != .poweredOn {
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        // Only drop clearly invalid readings (iOS reports 127 when RSSI is unavailable).
        // Previously this filtered anything below -90 dBm, which could hide a dongle
        // mounted on the bike behind bodywork — exactly the device the user needs.
        guard rssi != 127 else { return }

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertisedName ?? "Unknown"
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        logger.debug("Discovered: \(name, privacy: .public) RSSI=\(rssi) services=\(serviceUUIDs.map { $0.uuidString }, privacy: .public)")

        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            // The advertisement packet and scan response arrive as separate callbacks
            // with different payloads — merge so the name and service list from one
            // aren't lost when the other updates the RSSI.
            let existing = discoveredDevices[index]
            let mergedServices = Array(Set(existing.advertisedServices).union(serviceUUIDs))
            discoveredDevices[index] = DiscoveredDevice(
                peripheral: peripheral,
                rssi: rssi,
                advertisedName: advertisedName ?? existing.advertisedName,
                advertisedServices: mergedServices
            )
        } else {
            discoveredDevices.append(DiscoveredDevice(
                peripheral: peripheral,
                rssi: rssi,
                advertisedName: advertisedName,
                advertisedServices: serviceUUIDs
            ))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to \(peripheral.name ?? "Unknown", privacy: .public). Discovering services...")
        connectedPeripheral = peripheral
        let delegate = PeripheralDelegate(manager: self, peripheral: peripheral)
        self.peripheralDelegate = delegate
        peripheral.delegate = delegate
        peripheral.discoverServices(BLEManager.knownServiceUUIDs)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let err = error ?? BLEError.notConnected
        logger.error("Failed to connect to \(peripheral.name ?? "Unknown", privacy: .public): \(err.localizedDescription, privacy: .public)")
        cancelConnectionTimeout()
        connectContinuation?.resume(throwing: err)
        connectContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error {
            logger.warning("Disconnected from \(peripheral.name ?? "Unknown", privacy: .public) with error: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.info("Disconnected from \(peripheral.name ?? "Unknown", privacy: .public)")
        }
        let wasConnected = peripheral == connectedPeripheral
        if wasConnected {
            let serialPort = currentSerialPort
            connectedPeripheral = nil
            currentAdapter?.disconnect()
            currentAdapter = nil
            currentSerialPort = nil
            peripheralDelegate = nil
            Task { await serialPort?.close() }
            onConnectionLost?()
        }
        // If the peripheral dropped while connection setup was still in flight
        // (e.g. dongle power dips at key-on), fail the attempt immediately
        // instead of leaving the caller waiting for the timeout.
        if let continuation = connectContinuation {
            cancelConnectionTimeout()
            connectContinuation = nil
            continuation.resume(throwing: error ?? BLEError.disconnected)
        }
    }

    private func bluetoothStateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }
}

// MARK: - Peripheral Delegate (handles service/characteristic discovery and data)

private class PeripheralDelegate: NSObject, CBPeripheralDelegate {
    weak var manager: BLEManager?
    let peripheral: CBPeripheral
    private var connectionCompleted = false
    private var attemptedUnfilteredDiscovery = false

    init(manager: BLEManager, peripheral: CBPeripheral) {
        self.manager = manager
        self.peripheral = peripheral
    }

    /// Initial discovery is filtered to the known serial service UUIDs. If that finds
    /// nothing (some firmwares respond oddly to filtered discovery), retry once with
    /// no filter. The flag prevents retrying forever when the device genuinely has no
    /// supported service.
    private func retryUnfilteredOrFail() {
        if attemptedUnfilteredDiscovery {
            logger.error("No known BLE serial service found. Known UUIDs: FFE0 (CC254x), 6E400001 (NRF), 49535343 (RN4870), FEFB (Telit)")
            failConnection(error: BLEError.noSerialProfile)
        } else {
            attemptedUnfilteredDiscovery = true
            logger.info("No known service from filtered discovery; retrying without UUID filter...")
            peripheral.discoverServices(nil)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            logger.error("Service discovery failed: \(error.localizedDescription, privacy: .public)")
            failConnection(error: error)
            return
        }

        guard let services = peripheral.services, !services.isEmpty else {
            retryUnfilteredOrFail()
            return
        }

        logger.info("Discovered \(services.count) service(s):")
        for service in services {
            logger.info("  Service: \(service.uuid.uuidString, privacy: .public)")
        }

        // Find matching adapter
        var adapter: BLEAdapter?
        var matchedService: CBService?

        for service in services {
            if service.uuid == CC254xAdapter.serviceUUIDValue {
                adapter = CC254xAdapter()
                matchedService = service
                logger.info("Matched CC254x adapter (service \(service.uuid.uuidString, privacy: .public))")
                break
            }
            if service.uuid == NRFAdapter.serviceUUIDValue {
                adapter = NRFAdapter()
                matchedService = service
                logger.info("Matched NRF adapter (service \(service.uuid.uuidString, privacy: .public))")
                break
            }
            if service.uuid == RN4870Adapter.serviceUUIDValue {
                adapter = RN4870Adapter()
                matchedService = service
                logger.info("Matched RN4870 adapter (service \(service.uuid.uuidString, privacy: .public))")
                break
            }
            if service.uuid == TelitTIOAdapter.serviceUUIDValue {
                adapter = TelitTIOAdapter()
                matchedService = service
                logger.info("Matched Telit TIO adapter (service \(service.uuid.uuidString, privacy: .public))")
                break
            }
        }

        guard let adapter = adapter, let service = matchedService else {
            retryUnfilteredOrFail()
            return
        }

        manager?.currentAdapter = adapter
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            logger.error("Characteristic discovery failed for service \(service.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            failConnection(error: error)
            return
        }

        let chars = service.characteristics ?? []
        logger.info("Discovered \(chars.count) characteristic(s) for service \(service.uuid.uuidString, privacy: .public):")
        for char in chars {
            let props = characteristicPropertiesDescription(char.properties)
            logger.info("  Char: \(char.uuid.uuidString, privacy: .public) properties: [\(props, privacy: .public)]")
        }

        guard let adapter = manager?.currentAdapter else {
            logger.error("Characteristics discovered but no adapter selected")
            failConnection(error: BLEError.noSerialProfile)
            return
        }

        let serialPort = BLESerialPort(peripheral: peripheral, adapter: adapter)
        adapter.delegate = serialPort
        manager?.currentSerialPort = serialPort

        let syncComplete = adapter.configureCharacteristics(service: service, peripheral: peripheral)
        logger.info("Adapter configureCharacteristics returned syncComplete=\(syncComplete)")

        guard let readChar = adapter.readCharacteristic() else {
            logger.error("Adapter has no read characteristic after configuration")
            failConnection(error: BLEError.noSerialProfile)
            return
        }
        logger.info("Read characteristic: \(readChar.uuid.uuidString, privacy: .public)")
        if let writeChar = adapter.writeCharacteristic() {
            logger.info("Write characteristic: \(writeChar.uuid.uuidString, privacy: .public)")
        }

        // Enable notifications on the read characteristic. We must NOT consider the
        // connection ready until iOS confirms notifications are actually enabled
        // (didUpdateNotificationStateFor). If we complete early and immediately send
        // the first command (e.g. readVersion), the dongle's reply — delivered as a
        // notification — can be dropped before the CCCD write lands, causing a
        // spurious "Timeout reading from ECM". This applies to every adapter type.
        let canNotify = readChar.properties.contains(.notify) || readChar.properties.contains(.indicate)
        if canNotify {
            logger.info("Enabling notifications on read characteristic; will complete once confirmed...")
            peripheral.setNotifyValue(true, for: readChar)
        } else {
            // Read characteristic can't notify — there's no confirmation callback coming,
            // so complete now. (None of the known adapters hit this path in practice.)
            logger.warning("Read characteristic does not support notify/indicate; completing without notification confirmation")
            completeConnection(serialPort: serialPort)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.error("Failed to enable notifications for \(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            failConnection(error: error)
            return
        }

        logger.info("Notifications enabled for characteristic \(characteristic.uuid.uuidString, privacy: .public)")

        // Let the adapter react first (Telit grants its initial read credits here),
        // then complete the connection once the READ characteristic's notifications
        // are confirmed enabled so the dongle's responses can't be missed.
        manager?.currentAdapter?.onNotificationStateUpdated(peripheral: peripheral, characteristic: characteristic)

        if let adapter = manager?.currentAdapter,
           characteristic == adapter.readCharacteristic(),
           let serialPort = manager?.currentSerialPort {
            completeConnection(serialPort: serialPort)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        logger.debug("Descriptor written for characteristic \(descriptor.characteristic?.uuid.uuidString ?? "?", privacy: .public)")
        // Forward to adapter (needed for Telit credit-based flow control setup)
        if let adapter = manager?.currentAdapter {
            adapter.onDescriptorWrite(peripheral: peripheral, descriptor: descriptor, error: error)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            if let error {
                logger.error("Characteristic update error for \(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        if let adapter = manager?.currentAdapter {
            adapter.onCharacteristicChanged(peripheral: peripheral, characteristic: characteristic)

            if characteristic == adapter.readCharacteristic() {
                adapter.delegate?.adapterDidReceiveData(data)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.error("Write failed for \(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        if let adapter = manager?.currentAdapter {
            adapter.onCharacteristicWrite(peripheral: peripheral, characteristic: characteristic, error: error)
        }
    }

    // MARK: - Helpers

    private func completeConnection(serialPort: BLESerialPort) {
        guard !connectionCompleted else {
            logger.debug("completeConnection called again, ignoring (already completed)")
            return
        }
        guard let continuation = manager?.connectContinuation else {
            logger.debug("completeConnection called but no continuation available")
            return
        }

        connectionCompleted = true
        manager?.connectContinuation = nil
        manager?.cancelConnectionTimeout()

        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        logger.info("Connection complete! MTU=\(mtu)")
        Task {
            await serialPort.setPayloadSize(max(mtu, 20))
        }

        continuation.resume(returning: serialPort)
    }

    private func failConnection(error: Error) {
        guard !connectionCompleted else { return }
        connectionCompleted = true
        manager?.cancelConnectionTimeout()
        manager?.connectContinuation?.resume(throwing: error)
        manager?.connectContinuation = nil
    }

    private func characteristicPropertiesDescription(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.read) { parts.append("read") }
        if props.contains(.write) { parts.append("write") }
        if props.contains(.writeWithoutResponse) { parts.append("writeNoResp") }
        if props.contains(.notify) { parts.append("notify") }
        if props.contains(.indicate) { parts.append("indicate") }
        if props.contains(.broadcast) { parts.append("broadcast") }
        return parts.joined(separator: ", ")
    }
}
