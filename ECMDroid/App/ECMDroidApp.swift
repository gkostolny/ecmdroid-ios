// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

@main
struct ECMDroidApp: App {
    init() {
        if !DatabaseManager.shared.open() {
            print("Failed to open database")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
