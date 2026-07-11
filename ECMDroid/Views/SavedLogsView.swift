// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Browses recorded logs in the app's Documents folder and offers to share the raw
/// binary or export a MegaLogViewer-compatible MSL file.
struct SavedLogsView: View {
    @State private var logs: [URL] = []
    @State private var shareItem: ShareItem?
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        List {
            if logs.isEmpty {
                ContentUnavailableView {
                    Label("No Logs", systemImage: "waveform")
                } description: {
                    Text("Logs you record appear here. Record one from the Data Log screen.")
                }
            } else {
                ForEach(logs, id: \.self) { url in
                    logRow(url)
                }
                .onDelete(perform: deleteLogs)
            }
        }
        .navigationTitle("Saved Logs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .overlay {
            if isExporting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Converting to MSL…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("Export Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func logRow(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .foregroundStyle(Color.buellGold)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(url))
                    .fontWeight(.medium)
                Text(subtitle(url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    shareItem = ShareItem(url: url)
                } label: {
                    Label("Share Log File", systemImage: "square.and.arrow.up")
                }
                Button {
                    exportMSL(url)
                } label: {
                    Label("Export to MSL", systemImage: "tablecells")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color.buellGold)
                    .font(.title3)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func exportMSL(_ url: URL) {
        isExporting = true
        // Defer to the next runloop tick so the spinner can appear before the
        // (main-actor, DB-bound) conversion runs.
        Task { @MainActor in
            do {
                let out = try LogExporter.exportToMSL(logURL: url)
                isExporting = false
                shareItem = ShareItem(url: out)
            } catch {
                isExporting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func deleteLogs(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: logs[index])
        }
        reload()
    }

    private func reload() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? fm.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        logs = files
            .filter { $0.pathExtension == "log" }
            .sorted { modified($0) > modified($1) }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func displayName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private func subtitle(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let sizeStr = size < 1024 ? "\(size) B" : "\(size / 1024) KB"
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return "\(sizeStr) • \(df.string(from: modified(url)))"
    }
}
