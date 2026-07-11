// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

struct ContentView: View {
    var ecm = ECM.shared

    var body: some View {
        TabView {
            DeviceScanView()
                .tabItem {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }

            ECMInfoView()
                .tabItem {
                    Label("ECM", systemImage: "cpu")
                }

            DataChannelsView()
                .tabItem {
                    Label("Live Data", systemImage: "gauge.with.dots.needle.33percent")
                }

            DataLogView()
                .tabItem {
                    Label("Log", systemImage: "waveform")
                }

            TroubleCodesView()
                .tabItem {
                    Label("DTCs", systemImage: "exclamationmark.triangle")
                }

            ActiveTestsView()
                .tabItem {
                    Label("Tests", systemImage: "wrench.and.screwdriver")
                }

            SetupView()
                .tabItem {
                    Label("Setup", systemImage: "slider.horizontal.3")
                }

            EEPROMEditorView()
                .tabItem {
                    Label("EEPROM", systemImage: "memorychip")
                }

            TorqueValuesView()
                .tabItem {
                    Label("Torque", systemImage: "wrench.adjustable")
                }
        }
        .tint(.buellGold)
    }
}
