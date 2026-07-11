// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

class Bit {
    var id: Int = 0
    var type: ECMType?
    var offset: Int = 0
    var byteNr: Int = 0
    var bitNr: Int = 0
    var code: String = ""
    var name: String = ""
    var remark: String = ""
    var value: UInt8 = 0

    @discardableResult
    func refreshValue(from data: [UInt8]) -> Bool {
        var o = offset
        if o >= data.count {
            value = 0
            return false
        } else if o < 0 {
            o = data.count + o
        }
        guard o >= 0, o < data.count else {
            value = 0
            return false
        }
        let mask: UInt8 = 1 << bitNr
        value = data[o] & mask
        return value != 0
    }

    func setValue(_ val: Bool) {
        value = val ? UInt8((1 << bitNr) & 0xff) : 0
    }

    var isSet: Bool { value != 0 }
}
