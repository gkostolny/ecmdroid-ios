// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

class ECMBitSet: Sequence {
    var bits: [Bit?] = Array(repeating: nil, count: 8)
    var name: String
    var label: String
    var offset: Int

    init(name: String, label: String, offset: Int) {
        self.name = name
        self.label = label
        self.offset = offset
    }

    func add(_ bit: Bit) {
        guard bit.bitNr >= 0, bit.bitNr < 8 else { return }
        bits[bit.bitNr] = bit
    }

    func getBit(_ index: Int) -> Bit? {
        guard index >= 0, index < 8 else { return nil }
        return bits[index]
    }

    func getActiveBits(from data: [UInt8]) -> ECMBitSet {
        let active = ECMBitSet(name: name, label: label, offset: offset)
        for bit in bits {
            if let b = bit, b.refreshValue(from: data) {
                active.add(b)
            }
        }
        return active
    }

    func setAll(_ value: Bool) {
        for bit in bits {
            bit?.setValue(value)
        }
    }

    var value: UInt8 {
        var result: UInt8 = 0
        for bit in bits {
            if let b = bit {
                result |= b.value
            }
        }
        return result
    }

    var mask: UInt8 {
        var result: UInt8 = 0
        for bit in bits {
            if let b = bit {
                result |= (1 << b.bitNr)
            }
        }
        return result
    }

    @discardableResult
    func updateValue(_ bytes: inout [UInt8]) -> Bool {
        let nval = value
        let msk = mask
        let co = offset < 0 ? bytes.count + offset : offset
        guard co >= 0, co < bytes.count else { return false }
        let oldval = bytes[co]
        var val = (oldval & ~msk)
        val |= nval
        bytes[co] = val
        return val != oldval
    }

    func makeIterator() -> AnyIterator<Bit> {
        let nonNilBits = bits.compactMap { $0 }
        var index = 0
        return AnyIterator {
            guard index < nonNilBits.count else { return nil }
            let bit = nonNilBits[index]
            index += 1
            return bit
        }
    }
}
