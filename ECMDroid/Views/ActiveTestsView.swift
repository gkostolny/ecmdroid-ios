// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

struct ActiveTestsView: View {
    var ecm = ECM.shared

    private static let testFunctions: [ECMFunction] = [
        .frontCoil, .rearCoil, .tachometer, .fuelPump,
        .frontInj, .rearInj, .fan, .exhValve,
        .activeIntake, .shiftLight
    ]

    @State private var selectedFunction: ECMFunction?
    @State private var isRunningTest = false
    @State private var testStatus = ""
    @State private var showTPSAlert = false
    @State private var tpsAlertMessage = ""
    @State private var tpsAlertCanProceed = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Test list
                List(Self.testFunctions, id: \.self) { fn in
                    Button {
                        if !isRunningTest {
                            selectedFunction = fn
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconForFunction(fn))
                                .font(.subheadline)
                                .foregroundStyle(Color.buellGold)
                                .frame(width: 24)

                            Text(fn.displayName)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selectedFunction == fn {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.buellGold)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(selectedFunction == fn ? Color.buellGold.opacity(0.08) : nil)
                }
                .listStyle(.insetGrouped)

                // Status bar
                if !testStatus.isEmpty || errorMessage != nil {
                    VStack(spacing: 4) {
                        if !testStatus.isEmpty {
                            HStack(spacing: 8) {
                                if isRunningTest {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                Text(testStatus)
                                    .font(.subheadline)
                                    .foregroundStyle(isRunningTest ? .secondary : .primary)
                            }
                        }
                        if let error = errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.fill.quinary)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        guard let fn = selectedFunction else { return }
                        runTest(fn)
                    } label: {
                        Label("Start Test", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.buellGold)
                    .disabled(!ecm.isConnected || selectedFunction == nil || isRunningTest)

                    Button {
                        tpsResetTapped()
                    } label: {
                        Label("TPS Reset", systemImage: "dial.low")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!ecm.isConnected || isRunningTest || !ecm.isEEPROMRead)
                }
                .padding()
            }
            .navigationTitle("Active Tests")
            .alert("TPS Reset", isPresented: $showTPSAlert) {
                if tpsAlertCanProceed {
                    Button("Cancel", role: .cancel) {}
                    Button("OK") {
                        runTest(.tpsReset)
                    }
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                Text(tpsAlertMessage)
            }
        }
    }

    private func iconForFunction(_ fn: ECMFunction) -> String {
        switch fn {
        case .frontCoil, .rearCoil: return "bolt.fill"
        case .tachometer: return "gauge.with.needle"
        case .fuelPump: return "fuelpump.fill"
        case .frontInj, .rearInj: return "syringe.fill"
        case .fan: return "fan.fill"
        case .exhValve: return "valve.fill"
        case .activeIntake: return "wind"
        case .shiftLight: return "light.max"
        default: return "wrench.fill"
        }
    }

    private func tpsResetTapped() {
        if ecm.ecmType == .ddfi3 {
            tpsAlertMessage = "TPS Reset is not supported on DDFI-3 ECMs. Use the Screamin' Eagle Pro Super Tuner or Digital Technician II instead."
            tpsAlertCanProceed = false
            showTPSAlert = true
        } else {
            tpsAlertMessage = "Turn ignition on. Make sure the throttle is fully closed (idle position). Press OK to reset the TPS."
            tpsAlertCanProceed = true
            showTPSAlert = true
        }
    }

    private func runTest(_ function: ECMFunction) {
        isRunningTest = true
        errorMessage = nil
        let label = function == .tpsReset ? "Requesting" : "Testing"
        testStatus = "\(label) \(function.displayName)..."

        Task {
            do {
                try await ecm.runTest(function)
                while try await ecm.isBusy() {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                await MainActor.run {
                    if function == .tpsReset {
                        testStatus = "TPS Reset OK"
                    } else {
                        testStatus = "\(function.displayName) test complete"
                    }
                    isRunningTest = false
                }
            } catch {
                await MainActor.run {
                    testStatus = ""
                    errorMessage = error.localizedDescription
                    isRunningTest = false
                }
            }
        }
    }
}
