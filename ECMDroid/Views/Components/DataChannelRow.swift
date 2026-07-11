// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

struct DataChannelRow: View {
    let ecm: ECM
    let variableNames: [String]
    @Binding var selectedVariable: String?
    var channelIndex: Int = 0

    private static let channelColors: [Color] = [
        .buellGold, .cyan, .green, .orange, .purple
    ]

    private var accentColor: Color {
        Self.channelColors[channelIndex % Self.channelColors.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Channel header with picker
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 4, height: 20)

                Picker("Variable", selection: $selectedVariable) {
                    Text("Select channel...").tag(nil as String?)
                    ForEach(variableNames, id: \.self) { name in
                        Text(name).tag(name as String?)
                    }
                }
                .pickerStyle(.menu)
                .tint(accentColor)
            }

            if let name = selectedVariable, let variable = ecm.getRuntimeValue(name) {
                // Value display
                HStack(alignment: .firstTextBaseline) {
                    Text(variable.label.isEmpty ? variable.name : variable.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(variable.formattedValue)
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(accentColor)
                        .contentTransition(.numericText())
                }

                // Progress gauge
                if variable.high > variable.low {
                    let rawVal: Double = {
                        if let dv = variable.rawValues.first as? Double { return dv }
                        if let iv = variable.rawValues.first as? Int { return Double(iv) }
                        return 0
                    }()
                    let progress = min(max((rawVal - variable.low) / (variable.high - variable.low), 0), 1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.fill.tertiary)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(gaugeGradient(for: progress))
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                    .animation(.smooth(duration: 0.2), value: progress)
                }
            } else if selectedVariable != nil {
                Text("Waiting for data...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gaugeGradient(for value: Double) -> LinearGradient {
        let color: Color = value < 0.7 ? accentColor : value < 0.9 ? .orange : .red
        return LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
    }
}
