// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI
import CoreBluetooth

struct DeviceScanView: View {
    let ecm = ECM.shared

    @State private var selectedProtocol: ECMProtocol = .stock
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showAllDevices = false

    // TCP connection to the ecmsim simulator (feature parity with the Android
    // app's TCP/IP connection type). Host persists across launches.
    @AppStorage(PREFS_TCP_HOST) private var tcpHost = ""
    @AppStorage(PREFS_TCP_PORT) private var tcpPort = DEFAULT_TCP_PORT

    private var bleManager: BLEManager { ecm.bleManagerInstance }

    /// Serial adapters first (strongest signal first within each group); unnamed
    /// background devices (earbuds, beacons, watches…) hidden unless requested.
    private var displayedDevices: [DiscoveredDevice] {
        let devices = showAllDevices
            ? bleManager.discoveredDevices
            : bleManager.discoveredDevices.filter { $0.isSerialAdapter || $0.hasName }
        return devices.sorted {
            if $0.isSerialAdapter != $1.isSerialAdapter { return $0.isSerialAdapter }
            return $0.rssi > $1.rssi
        }
    }

    private var hiddenDeviceCount: Int {
        bleManager.discoveredDevices.count - displayedDevices.count
    }

    var body: some View {
        NavigationStack {
            List {
                // Protocol selector
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Protocol", systemImage: "gearshape.2")
                        // Full-width segmented control: a fixed narrow frame squeezes
                        // the segment labels ("Stock / P&A", "Factory Race") until
                        // they truncate into unreadable text.
                        Picker("Protocol", selection: $selectedProtocol) {
                            ForEach(ECMProtocol.allCases, id: \.self) { proto in
                                Text(proto.label).tag(proto)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }

                // Bluetooth state warning
                if bleManager.bluetoothState != .poweredOn {
                    Section {
                        Label {
                            Text(bluetoothStateMessage)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "bluetooth.slash")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Discovered devices
                Section {
                    if bleManager.discoveredDevices.isEmpty && bleManager.isScanning {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Scanning for BLE serial adapters...")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    } else if bleManager.discoveredDevices.isEmpty && !bleManager.isScanning {
                        ContentUnavailableView {
                            Label("No Devices", systemImage: "antenna.radiowaves.left.and.right.slash")
                        } description: {
                            Text("Tap Scan to search for nearby BLE serial adapters. Make sure the bike's ignition is on so the adapter has power.")
                        }
                        .listRowBackground(Color.clear)
                    }

                    ForEach(displayedDevices) { device in
                        Button {
                            connectToDevice(device)
                        } label: {
                            HStack(spacing: 12) {
                                signalIndicator(rssi: device.rssi)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(device.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        if device.isSerialAdapter {
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.caption)
                                                .foregroundStyle(Color.buellGold)
                                        }
                                    }
                                    Text(device.isSerialAdapter
                                         ? "BLE serial adapter"
                                         : device.peripheral.identifier.uuidString.prefix(8) + "...")
                                        .font(.caption2)
                                        .foregroundStyle(device.isSerialAdapter ? AnyShapeStyle(Color.buellGold) : AnyShapeStyle(.tertiary))
                                        .monospaced()
                                }

                                Spacer()

                                Text("\(device.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 2)
                        }
                        .disabled(isConnecting)
                    }

                    if hiddenDeviceCount > 0 || showAllDevices {
                        Toggle(isOn: $showAllDevices) {
                            Text(showAllDevices
                                 ? "Showing all devices"
                                 : "Show all devices (\(hiddenDeviceCount) hidden)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Discovered Devices")
                } footer: {
                    if !bleManager.discoveredDevices.isEmpty {
                        Text("Devices marked \(Image(systemName: "checkmark.seal.fill")) advertise a compatible serial service and are most likely your adapter.")
                    }
                }

                // ECM simulator (TCP)
                Section {
                    HStack {
                        Text("Host")
                        TextField("127.0.0.1 or Mac's IP", text: $tcpHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                            .monospaced()
                    }
                    HStack {
                        Text("Port")
                        TextField("Port", value: $tcpPort, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospaced()
                    }
                    Button {
                        connectToSimulator()
                    } label: {
                        Label("Connect to Simulator", systemImage: "network")
                    }
                    .disabled(isConnecting || tcpHost.trimmingCharacters(in: .whitespaces).isEmpty
                              || !(1...65535).contains(tcpPort))
                } header: {
                    Text("ECM Simulator (TCP)")
                } footer: {
                    Text("Connects to an ecmsim instance instead of a BLE adapter. In the iOS Simulator use 127.0.0.1; on a phone use the IP of the machine running ecmsim.")
                }

                // Disconnect
                if ecm.isConnected {
                    Section {
                        Button(role: .destructive) {
                            ecm.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "bolt.slash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Connect")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Button {
                            if bleManager.isScanning {
                                bleManager.stopScan()
                            } else {
                                bleManager.startScan()
                            }
                        } label: {
                            Text(bleManager.isScanning ? "Stop" : "Scan")
                                .fontWeight(.semibold)
                        }
                        .disabled(bleManager.bluetoothState != .poweredOn)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionStatusView(ecm: ecm)
                }
            }
            .alert("Connection Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func connectToSimulator() {
        let host = tcpHost.trimmingCharacters(in: .whitespaces)
        guard let port = UInt16(exactly: tcpPort) else { return }
        isConnecting = true
        Task {
            do {
                try await ecm.connect(host: host, port: port, protocol: selectedProtocol)
                _ = try await ecm.setupEEPROM()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    ecm.disconnect()
                }
            }
            await MainActor.run {
                isConnecting = false
            }
        }
    }

    private func connectToDevice(_ device: DiscoveredDevice) {
        isConnecting = true
        Task {
            do {
                try await ecm.connect(peripheral: device, protocol: selectedProtocol)
                _ = try await ecm.setupEEPROM()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    ecm.disconnect()
                }
            }
            await MainActor.run {
                isConnecting = false
            }
        }
    }

    private func signalIndicator(rssi: Int) -> some View {
        let level: Int = rssi > -50 ? 3 : rssi > -70 ? 2 : 1
        return Image(systemName: "wifi", variableValue: Double(level) / 3.0)
            .font(.title3)
            .foregroundStyle(level >= 3 ? .green : level >= 2 ? Color.buellGold : .orange)
            .frame(width: 28)
    }

    private var bluetoothStateMessage: String {
        switch bleManager.bluetoothState {
        case .poweredOff: return "Bluetooth is turned off"
        case .unauthorized: return "Bluetooth permission not granted"
        case .unsupported: return "Bluetooth LE is not supported"
        default: return "Bluetooth is not available"
        }
    }
}
