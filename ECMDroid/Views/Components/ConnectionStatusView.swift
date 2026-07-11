// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

struct ConnectionStatusView: View {
    let ecm: ECM

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.system(size: 10))
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, isActive: ecm.isReading || ecm.isRecording)
            Text(ecm.statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var statusIcon: String {
        if ecm.isConnected && ecm.isReading {
            return "antenna.radiowaves.left.and.right"
        } else if ecm.isConnected {
            return "bolt.horizontal.fill"
        } else {
            return "bolt.slash.fill"
        }
    }

    private var statusColor: Color {
        if ecm.isConnected && ecm.isReading {
            return .green
        } else if ecm.isConnected {
            return .buellGold
        } else {
            return .secondary
        }
    }
}

// MARK: - Brand Colors

extension Color {
    static let buellGold = Color(red: 0.88, green: 0.68, blue: 0.22)
}
