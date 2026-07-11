// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

struct ECMDiagError: Identifiable {
    enum ErrorType {
        case current, stored
    }

    let id = UUID()
    var code: String
    var errorDescription: String
    var type: ErrorType
}
