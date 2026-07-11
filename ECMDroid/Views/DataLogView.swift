// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

private struct LogInterval: Identifiable, Hashable {
    let id: Int
    let label: String
    let delay: TimeInterval

    static let intervals: [LogInterval] = [
        LogInterval(id: 0, label: "No Delay", delay: 0),
        LogInterval(id: 1, label: "250ms", delay: 0.25),
        LogInterval(id: 2, label: "500ms", delay: 0.5),
        LogInterval(id: 3, label: "1s", delay: 1.0),
        LogInterval(id: 4, label: "2s", delay: 2.0),
        LogInterval(id: 5, label: "5s", delay: 5.0),
    ]
}

struct DataLogView: View {
    var ecm = ECM.shared
    @State private var selectedInterval = LogInterval.intervals[1]
    @State private var errorMessage: String?
    @State private var logFileURL: URL?
    @State private var showShareSheet = false

    private var tpsValue: String {
        guard ecm.isRecording, let v = ecm.getRuntimeValue(Variables.TPD) else { return "--" }
        return v.formattedValue.isEmpty ? "--" : v.formattedValue
    }

    private var rpmValue: String {
        guard ecm.isRecording, let v = ecm.getRuntimeValue(Variables.RPM) else { return "--" }
        return v.formattedValue.isEmpty ? "--" : v.formattedValue
    }

    private var cltValue: String {
        guard ecm.isRecording, let v = ecm.getRuntimeValue(Variables.CLT) else { return "--" }
        return v.formattedValue.isEmpty ? "--" : v.formattedValue
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Live gauges
                HStack(spacing: 0) {
                    gaugeCard("RPM", value: rpmValue, unit: "", color: .buellGold)
                    Divider()
                    gaugeCard("TPS", value: tpsValue, unit: "\u{00B0}", color: .cyan)
                    Divider()
                    gaugeCard("CLT", value: cltValue, unit: "\u{00B0}", color: .orange)
                }
                .frame(height: 100)
                .background(.fill.quinary)

                Divider()

                // Recording status
                VStack(spacing: 16) {
                    if ecm.isRecording {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                                .shadow(color: .red.opacity(0.6), radius: 4)
                            Text("RECORDING")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.red)
                                .tracking(1.5)
                        }
                        .padding(.top, 20)

                        HStack(spacing: 32) {
                            statColumn("\(ecm.recordsLogged)", label: "Records")
                            statColumn(formatBytes(ecm.bytesLogged), label: "Size")
                            statColumn(selectedInterval.label, label: "Interval")
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 24)

                            Text("Ready to record")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Interval picker
                        HStack {
                            Text("Interval")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("Interval", selection: $selectedInterval) {
                                ForEach(LogInterval.intervals) { interval in
                                    Text(interval.label).tag(interval)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.buellGold)
                        }
                        .padding(.horizontal, 24)
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: toggleRecording) {
                        HStack {
                            Image(systemName: ecm.isRecording ? "stop.fill" : "record.circle")
                                .font(.title3)
                            Text(ecm.isRecording ? "Stop Recording" : "Start Recording")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ecm.isRecording ? .red : .buellGold)
                    .disabled(!ecm.isConnected)

                    if let url = logFileURL, !ecm.isRecording {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Share Last Log", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .sheet(isPresented: $showShareSheet) {
                            ShareSheet(activityItems: [url])
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Data Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SavedLogsView()
                    } label: {
                        Image(systemName: "folder")
                    }
                }
            }
        }
    }

    private func gaugeCard(_ label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(value + (value != "--" ? unit : ""))
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(ecm.isRecording ? color : .secondary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func statColumn(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        return "\(bytes / 1024) KB"
    }

    private func toggleRecording() {
        if ecm.isRecording {
            ecm.stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        errorMessage = nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "\(formatter.string(from: Date())).log"

        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docsURL.appendingPathComponent(filename)

        do {
            try ecm.startRecording(to: fileURL, interval: selectedInterval.delay)
            logFileURL = fileURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
