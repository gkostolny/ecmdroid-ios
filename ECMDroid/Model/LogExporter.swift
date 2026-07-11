// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import Foundation

enum LogExportError: LocalizedError {
    case emptyLog
    case unknownECM
    case noChannels
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyLog:
            return "The log file is empty or has no complete records to convert."
        case .unknownECM:
            return "This log was recorded without a known ECM id, so its channels can't be decoded."
        case .noChannels:
            return "No runtime channels are defined for this ECM in the database."
        case .writeFailed(let msg):
            return "Could not write the exported file: \(msg)"
        }
    }
}

/// Converts a recorded binary data log into a tab-separated MSL file that opens in
/// MegaLogViewer, Excel, or Numbers. Decoding reuses the exact same runtime variable
/// definitions and offsets the live Data view uses, so exported values match what was
/// shown on screen during recording.
///
/// Runs on the main actor because it touches `VariableProvider`/`DatabaseManager`,
/// which share a single non-thread-safe SQLite connection and cache with the app.
@MainActor
enum LogExporter {

    static func exportToMSL(logURL: URL) throws -> URL {
        let raw = try Data(contentsOf: logURL)
        let headerLen = ECM.logFormatMagicHeaderLength
        let bytes = [UInt8](raw)
        guard bytes.count > headerLen else { throw LogExportError.emptyLog }

        // 5-byte ECM id header (space padded)
        let ecmId = String(bytes: bytes[0..<headerLen], encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !ecmId.isEmpty, ecmId != "UNKWN" else { throw LogExportError.unknownECM }

        // First record's length gives the (constant) packet size; use it to keep only
        // channels whose bytes actually fit, so we don't emit columns of stale zeros.
        guard headerLen + 6 <= bytes.count else { throw LogExportError.emptyLog }
        let packetLen = (Int(bytes[headerLen]) << 8) | Int(bytes[headerLen + 1])
        guard packetLen > 0, headerLen + 6 + packetLen <= bytes.count else { throw LogExportError.emptyLog }

        let vp = VariableProvider.shared
        let allVars = vp.getScalarRtVariableNames(ecm: ecmId).compactMap { vp.getRtVariable(ecm: ecmId, name: $0) }
        let vars = allVars.filter { $0.offset >= 0 && $0.offset + $0.size <= packetLen }
        guard !vars.isEmpty else { throw LogExportError.noChannels }

        var lines: [String] = []
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("\"ECMDroid iOS\"\t\"\(ecmId)\"\t\"\(df.string(from: Date()))\"")
        lines.append((["Time"] + vars.map { sanitize($0.name) }).joined(separator: "\t"))
        lines.append((["s"] + vars.map { $0.unit.isEmpty ? "-" : sanitize($0.unit) }).joined(separator: "\t"))

        // Records: [2-byte BE packet length][4-byte BE centiseconds][full RT PDU packet]
        var i = headerLen
        var recordCount = 0
        while i + 6 <= bytes.count {
            let len = (Int(bytes[i]) << 8) | Int(bytes[i + 1])
            let cs = (Int(bytes[i + 2]) << 24) | (Int(bytes[i + 3]) << 16)
                   | (Int(bytes[i + 4]) << 8) | Int(bytes[i + 5])
            i += 6
            guard len > 0, i + len <= bytes.count else { break }
            let packet = Array(bytes[i..<(i + len)])
            i += len

            var row = [String(format: "%.2f", Double(cs) / 100.0)]
            for v in vars {
                v.refreshValue(from: packet)
                row.append(numericString(v))
            }
            lines.append(row.joined(separator: "\t"))
            recordCount += 1
        }

        guard recordCount > 0 else { throw LogExportError.emptyLog }

        let output = lines.joined(separator: "\n") + "\n"
        let outURL = logURL.deletingPathExtension().appendingPathExtension("msl")
        do {
            try output.write(to: outURL, atomically: true, encoding: .utf8)
        } catch {
            throw LogExportError.writeFailed(error.localizedDescription)
        }
        return outURL
    }

    /// Plain numeric string (no unit symbol) for a decoded channel value.
    private static func numericString(_ v: Variable) -> String {
        guard let first = v.rawValues.first else { return "" }
        if let d = first as? Double { return String(format: "%g", d) }
        if let n = first as? Int { return "\(n)" }
        if let s = first as? Int16 { return "\(Int(s))" }
        return ""
    }

    /// MSL is tab-delimited, so tabs/newlines can't appear inside a field.
    private static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ")
         .replacingOccurrences(of: "\n", with: " ")
    }
}
