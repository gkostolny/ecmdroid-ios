// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

// @Observable so live edits to `data` and page `touched` flags propagate to SwiftUI.
// ECM holds EEPROM by reference, so without this a byte edit would mutate state
// silently and the editor UI would never refresh.
@Observable
class EEPROM {
    @Observable
    class Page {
        var nr: Int
        var length: Int
        var start: Int = 0
        var touched: Bool = false
        weak var parent: EEPROM?

        init(nr: Int, length: Int) {
            self.nr = nr
            self.length = length
        }

        func touch() { touched = true }
        func saved() { touched = false }
    }

    var type: ECMType?
    var id: String
    var version: String?
    var pages: [Page] = []
    var data: [UInt8] = []
    var eepromRead: Bool = false
    var touched: Bool = false
    var xsize: Int = 0

    init(id: String) {
        self.id = id
    }

    var length: Int { data.count }

    var hasPageZero: Bool { data.count == xsize }

    var pageCount: Int { pages.count }

    func getPage(_ pageNo: Int) -> Page? {
        pages.first(where: { $0.nr == pageNo })
    }

    func touch(offset: Int, length: Int) {
        for pg in pages {
            if offset >= pg.start && offset < pg.start + pg.length {
                pg.touch()
            }
        }
        touched = true
    }

    func markSaved() {
        touched = false
        for pg in pages {
            pg.saved()
        }
    }
}
