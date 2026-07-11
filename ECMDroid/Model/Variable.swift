// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

class Variable {
    enum DataType: String, CaseIterable {
        case scalar = "SCALAR"
        case value = "VALUE"
        case bits = "BITS"
        case bitfield = "BITFIELD"
        case array = "ARRAY"
        case axis = "AXIS"
        case table = "TABLE"
        case map = "MAP"
        case string = "STRING"
    }

    var id: Int = 0
    var ecmType: ECMType?
    var name: String = ""
    var type: DataType = .scalar
    var size: Int = 0
    var width: Int = 1
    var rows: Int = 0
    var cols: Int = 0
    var offset: Int = 0
    var unit: String = ""
    var symbol: String = ""
    var scale: Double = 0
    var translate: Double = 0
    var label: String = ""
    var format: String?
    var low: Double = 0
    var high: Double = 0
    var ulow: Int = 0
    var uhigh: Int = 0
    var remarks: String = ""
    var variableDescription: String = ""
    var rawValues: [Any] = []
    var formattedValues: [String] = []

    func initialize() {
        let count = max(size / width, 1)
        rawValues = Array(repeating: 0 as Any, count: count)
        formattedValues = Array(repeating: "", count: count)
    }

    var elementCount: Int { rawValues.count }

    var computedHigh: Double {
        if (size == 1 && uhigh == 0xFF) || (size == 2 && uhigh == 0xFFFF) {
            return high * scale + translate
        }
        return high
    }

    @discardableResult
    func refreshValue(from data: [UInt8]) -> Variable {
        let co = offset < 0 ? data.count + offset : offset
        guard co >= 0, co + size <= data.count else { return self }

        let elemCount = size / width
        for s in 0..<elemCount {
            var value = 0
            // Little-endian read: matches Java exactly
            for i in stride(from: width, through: 1, by: -1) {
                value <<= 8
                value |= Int(data[co + s * width + i - 1]) & 0xff
            }

            if type == .bits || type == .bitfield {
                rawValues[s] = Int16(value & 0xffff)
            } else if type != .string {
                var v = Double(value)
                if scale != 0 { v *= scale }
                if translate != 0 { v += translate }
                rawValues[s] = v
                if format == "0" {
                    rawValues[s] = Int(v)
                }
            } else {
                let bytes = Array(data[co..<(co + size)])
                rawValues[s] = bytes
            }
            formatValueAt(s)
        }
        return self
    }

    func updateValue(into data: inout [UInt8]) {
        guard !rawValues.isEmpty, !(rawValues[0] is NSNull) else { return }
        let co = offset < 0 ? data.count + offset : offset
        var buffer = [UInt8](repeating: 0, count: size)

        let elemCount = size / width
        for s in 0..<elemCount {
            var value = 0
            if type == .bitfield || type == .bits {
                if let sv = rawValues[0] as? Int16 {
                    value = Int(sv) & 0xFFFF
                }
            } else if type != .string {
                var v: Double = 0
                if let dv = rawValues[s] as? Double {
                    v = dv
                } else if let iv = rawValues[s] as? Int {
                    v = Double(iv)
                }
                if translate != 0 { v -= translate }
                if scale != 0 { v /= scale }
                value = Int(v)
            } else {
                return
            }

            for i in 0..<width {
                buffer[i + s * width] = UInt8(value & 0xFF)
                value >>= 8
            }
        }

        for i in 0..<size {
            data[co + i] = buffer[i]
        }
    }

    func parseValue(_ value: Any) {
        parseValueAt(0, value: value)
    }

    func parseValueAt(_ index: Int, value: Any) {
        let v = Double("\(value)") ?? 0
        rawValues[index] = v
        if format == "0" {
            rawValues[index] = Int(v)
        }
        formatValueAt(index)
    }

    func formatValueAt(_ index: Int) {
        guard index < rawValues.count, index < formattedValues.count else { return }

        if type == .bits || type == .bitfield {
            if let v = rawValues[index] as? Int16 {
                let binary = String(Int(v) & 0xFF, radix: 2)
                formattedValues[index] = String(repeating: "0", count: max(0, 8 - binary.count)) + binary
            }
        } else if type == .string {
            if let bytes = rawValues[index] as? [UInt8] {
                var len = bytes.count
                for i in 0..<bytes.count {
                    if bytes[i] == 0 { len = i; break }
                }
                formattedValues[index] = String(bytes: Array(bytes[0..<len]), encoding: .ascii) ?? ""
            }
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if let fmt = format {
                formatter.positiveFormat = fmt
                formatter.negativeFormat = "-\(fmt)"
            } else {
                formatter.positiveFormat = "0"
                formatter.negativeFormat = "-0"
            }

            if let dv = rawValues[index] as? Double {
                formattedValues[index] = formatter.string(from: NSNumber(value: dv)) ?? "\(dv)"
            } else if let iv = rawValues[index] as? Int {
                formattedValues[index] = formatter.string(from: NSNumber(value: iv)) ?? "\(iv)"
            }

            if !symbol.isEmpty {
                formattedValues[index] += symbol
            }
        }
    }

    var formattedValue: String {
        formattedValues.isEmpty ? "" : formattedValues[0]
    }

    var intValue: Int { intValueAt(0) }

    func intValueAt(_ index: Int) -> Int {
        guard index < rawValues.count else { return 0 }
        if type == .bitfield || type == .bits {
            if let sv = rawValues[index] as? Int16 { return Int(sv) }
        }
        if let iv = rawValues[index] as? Int { return iv }
        if let dv = rawValues[index] as? Double { return Int(dv) }
        return 0
    }

    func intValueAt(row: Int, col: Int) -> Int {
        intValueAt(row * cols + col)
    }
}
