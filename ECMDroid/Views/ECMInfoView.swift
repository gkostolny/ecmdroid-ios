// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

struct ECMInfoView: View {
    let ecm = ECM.shared
    @State private var isReadingEEPROM = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            if !ecm.isConnected {
                ContentUnavailableView {
                    Label("Not Connected", systemImage: "bolt.slash")
                } description: {
                    Text("Connect to an ECM from the Connect tab to view module information.")
                }
            } else {
                List {
                    // ECM identity card
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.buellGold)

                            Text(ecm.id ?? "Unknown ECM")
                                .font(.title2)
                                .fontWeight(.bold)

                            if let version = ecm.version {
                                Text(version)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 16) {
                                infoPill(ecm.ecmType?.displayName ?? "N/A", icon: "cpu")
                                infoPill(ecm.currentProtocol.label, icon: "antenna.radiowaves.left.and.right")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    if ecm.isEEPROMRead {
                        Section("Manufacturing") {
                            infoRow("Serial No.", value: ecm.serialNo, icon: "number")
                            infoRow("Mfg. Date", value: ecm.mfgDate, icon: "calendar")
                            infoRow("Country ID", value: ecm.countryID, icon: "globe")
                        }

                        Section("Firmware") {
                            infoRow("Calibration", value: ecm.calibrationID, icon: "doc.text")
                            infoRow("Layout Rev.", value: ecm.layoutRevision, icon: "list.number")
                        }

                        if let eeprom = ecm.eeprom {
                            Section("EEPROM") {
                                infoRow("Size", value: "\(eeprom.length) bytes", icon: "memorychip")
                                infoRow("Pages", value: "\(eeprom.pageCount)", icon: "square.stack.3d.up")
                                infoRow("Page 0", value: eeprom.hasPageZero ? "Present" : "Absent", icon: "0.square")
                            }
                        }
                    }

                    // Read EEPROM action
                    Section {
                        Button {
                            readEEPROM()
                        } label: {
                            HStack {
                                if isReadingEEPROM {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                    Text("Reading EEPROM...")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Label(ecm.isEEPROMRead ? "Re-read EEPROM" : "Read EEPROM", systemImage: "arrow.down.doc")
                                }
                                Spacer()
                            }
                        }
                        .disabled(!ecm.isConnected || isReadingEEPROM)
                    }
                }
            }
        }
        .navigationTitle("ECM")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ConnectionStatusView(ecm: ecm)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func infoPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: Capsule())
    }

    private func infoRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.buellGold)
                .frame(width: 22)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func readEEPROM() {
        isReadingEEPROM = true
        Task {
            do {
                try await ecm.readEEPROM()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            await MainActor.run {
                isReadingEEPROM = false
            }
        }
    }
}
