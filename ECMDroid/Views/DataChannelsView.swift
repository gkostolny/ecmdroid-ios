// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

struct DataChannelsView: View {
    let ecm = ECM.shared

    @State private var channels: [String?] = Array(repeating: nil, count: 5)
    @State private var variableNames: [String] = []

    var body: some View {
        NavigationStack {
            if !ecm.isConnected {
                ContentUnavailableView {
                    Label("Not Connected", systemImage: "bolt.slash")
                } description: {
                    Text("Connect to an ECM to view live data channels.")
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // Live data toggle
                        HStack {
                            Label(ecm.isReading ? "Streaming" : "Paused",
                                  systemImage: ecm.isReading ? "waveform.path.ecg" : "pause.circle")
                                .font(.subheadline)
                                .foregroundStyle(ecm.isReading ? .green : .secondary)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { ecm.isReading },
                                set: { newValue in
                                    if newValue {
                                        ecm.startReading()
                                    } else {
                                        ecm.stopReading()
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(.buellGold)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        // Data channels
                        ForEach(0..<5, id: \.self) { index in
                            DataChannelRow(
                                ecm: ecm,
                                variableNames: variableNames,
                                selectedVariable: $channels[index],
                                channelIndex: index
                            )
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom)
                }
            }
        }
        .navigationTitle("Live Data")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ConnectionStatusView(ecm: ecm)
            }
        }
        .onAppear {
            loadVariableNames()
        }
        .onChange(of: ecm.id) { _, _ in
            loadVariableNames()
        }
    }

    private func loadVariableNames() {
        guard let ecmID = ecm.id else {
            variableNames = []
            return
        }
        variableNames = VariableProvider.shared.getScalarRtVariableNames(ecm: ecmID)
    }
}
