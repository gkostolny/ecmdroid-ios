// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

struct TroubleCodesView: View {
    let ecm = ECM.shared

    @State private var currentErrors: [ECMDiagError] = []
    @State private var storedErrors: [ECMDiagError] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showClearConfirm = false

    private var totalErrors: Int { currentErrors.count + storedErrors.count }

    var body: some View {
        NavigationStack {
            if !ecm.isConnected {
                ContentUnavailableView {
                    Label("Not Connected", systemImage: "bolt.slash")
                } description: {
                    Text("Connect to an ECM to read diagnostic trouble codes.")
                }
            } else {
                List {
                    // Actions
                    Section {
                        HStack(spacing: 12) {
                            Button {
                                readErrors()
                            } label: {
                                Label("Read Codes", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.buellGold)
                            .disabled(isLoading)

                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Label("Clear", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isLoading || totalErrors == 0)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                    }

                    if isLoading {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Reading trouble codes...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Current errors
                    Section {
                        if currentErrors.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.green)
                                Text("No active faults")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(currentErrors) { error in
                                errorRow(error)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Current")
                            Spacer()
                            Text("\(currentErrors.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundColor(currentErrors.isEmpty ? .secondary : .red)
                        }
                    }

                    // Stored errors
                    Section {
                        if storedErrors.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.green)
                                Text("No stored faults")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(storedErrors) { error in
                                errorRow(error)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Stored")
                            Spacer()
                            Text("\(storedErrors.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundColor(storedErrors.isEmpty ? .secondary : .orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("Trouble Codes")
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
        .confirmationDialog("Clear Codes", isPresented: $showClearConfirm) {
            Button("Clear All Codes", role: .destructive) {
                clearCodes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all stored trouble codes from the ECM.")
        }
    }

    private func errorRow(_ error: ECMDiagError) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: error.type == .current ? "exclamationmark.circle.fill" : "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(error.type == .current ? .red : .orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.code)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.bold)
                Text(error.errorDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func readErrors() {
        isLoading = true
        Task {
            do {
                let current = try await ecm.getErrors(type: .current)
                let stored = try await ecm.getErrors(type: .stored)
                await MainActor.run {
                    currentErrors = current
                    storedErrors = stored
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func clearCodes() {
        Task {
            do {
                try await ecm.runTest(.clearCodes)
                readErrors()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
