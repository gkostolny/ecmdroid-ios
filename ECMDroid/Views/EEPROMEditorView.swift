// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

// MARK: - Editor entry

struct EEPROMEditorView: View {
    var ecm = ECM.shared

    // Writing to the ECM is off by default and must be consciously enabled — a bad
    // burn can make the bike run poorly. Mirrors the original app's burn preference.
    @AppStorage(PREFS_ENABLE_BURN) private var burnEnabled = false

    @State private var showCreateBackup = false
    @State private var newBackupName = ""
    @State private var showRevertConfirm = false
    @State private var showBurnConfirm = false
    @State private var isBurning = false
    @State private var alert: EditorAlert?

    var body: some View {
        NavigationStack {
            Group {
                if !ecm.canEditEEPROM {
                    ContentUnavailableView {
                        Label("EEPROM Not Read", systemImage: "memorychip")
                    } description: {
                        Text("Connect to an ECM and read the EEPROM from the ECM tab before editing.")
                    }
                } else {
                    editorList
                }
            }
            .navigationTitle("EEPROM")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionStatusView(ecm: ecm)
                }
            }
        }
        .alert("Create Backup", isPresented: $showCreateBackup) {
            TextField("Backup name", text: $newBackupName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { createBackup() }
        } message: {
            Text("Save the current EEPROM values so you can restore them later.")
        }
        .alert("Revert All Changes?", isPresented: $showRevertConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Revert", role: .destructive) { ecm.revertToPristine() }
        } message: {
            Text("This discards every edit and restores the values the ECM currently holds. Nothing is written to the ECM.")
        }
        .alert("Write to ECM?", isPresented: $showBurnConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Write", role: .destructive) { burn() }
        } message: {
            Text("This permanently writes the changed pages to your ECM. Make sure the ignition is on and the engine is not running. An automatic backup of the original values has been saved.")
        }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
        }
    }

    private var editorList: some View {
        List {
            // Status / modification banner
            Section {
                HStack(spacing: 12) {
                    Image(systemName: ecm.isEEPROMModifiedFromPristine ? "pencil.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(ecm.isEEPROMModifiedFromPristine ? Color.buellGold : .green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ecm.isEEPROMModifiedFromPristine ? "Unsaved changes" : "Matches ECM")
                            .fontWeight(.medium)
                        Text(ecm.id ?? "Unknown ECM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            // Safety: backups & restore
            Section {
                Button {
                    newBackupName = defaultBackupName()
                    showCreateBackup = true
                } label: {
                    Label("Save Current as Backup", systemImage: "square.and.arrow.down")
                }

                NavigationLink {
                    EEPROMBackupsView(ecm: ecm)
                } label: {
                    Label("Backups & Restore", systemImage: "clock.arrow.circlepath")
                }

                Button(role: .destructive) {
                    showRevertConfirm = true
                } label: {
                    Label("Revert to ECM Values", systemImage: "arrow.uturn.backward")
                }
                .disabled(!ecm.isEEPROMModifiedFromPristine)
            } header: {
                Text("Safety")
            } footer: {
                Text("An automatic backup was saved when you first read this EEPROM. You can always return to it under Backups & Restore.")
            }

            // Pages
            Section("Pages") {
                ForEach(sortedPages, id: \.nr) { page in
                    NavigationLink {
                        EEPROMPageEditorView(page: page, ecm: ecm)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pageIsModified(page) ? "circle.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(pageIsModified(page) ? Color.buellGold : .clear)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Page \(page.nr)")
                                    .fontWeight(.medium)
                                Text("\(page.length) bytes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if page.nr == 0 {
                                Text("read-only")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if page.touched {
                                Text("modified")
                                    .font(.caption2)
                                    .foregroundStyle(Color.buellGold)
                            }
                        }
                    }
                }
            }

            // Burn
            Section {
                Toggle(isOn: $burnEnabled) {
                    Label("Enable Writing to ECM", systemImage: "exclamationmark.triangle")
                }
                .tint(.buellGold)

                Button {
                    showBurnConfirm = true
                } label: {
                    HStack {
                        if isBurning {
                            ProgressView().controlSize(.small)
                            Text("Writing...").foregroundStyle(.secondary)
                        } else {
                            Label("Write to ECM", systemImage: "square.and.arrow.up.on.square")
                        }
                        Spacer()
                    }
                }
                .disabled(!burnEnabled || !ecm.hasUnsavedEEPROMChanges || isBurning)
            } header: {
                Text("Write")
            } footer: {
                Text("Writing sends only the pages you changed. Incorrect values can affect how the bike runs — keep your backup.")
            }
        }
    }

    private var sortedPages: [EEPROM.Page] {
        (ecm.eeprom?.pages ?? []).sorted { $0.nr < $1.nr }
    }

    private func pageIsModified(_ page: EEPROM.Page) -> Bool {
        guard let pristine = ecm.pristineData, let data = ecm.eeprom?.data,
              page.start >= 0, page.start + page.length <= data.count,
              page.start + page.length <= pristine.count else { return page.touched }
        for i in page.start..<(page.start + page.length) where data[i] != pristine[i] {
            return true
        }
        return false
    }

    private func defaultBackupName() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, HH:mm"
        return "\(ecm.id ?? "ECM") — \(df.string(from: Date()))"
    }

    private func createBackup() {
        let name = newBackupName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let backup = try ecm.createBackup(name: name.isEmpty ? defaultBackupName() : name)
            alert = EditorAlert(title: "Backup Saved", message: "\"\(backup.name)\" (\(backup.byteCount) bytes) was saved.")
        } catch {
            alert = EditorAlert(title: "Backup Failed", message: error.localizedDescription)
        }
    }

    private func burn() {
        isBurning = true
        Task {
            do {
                try await ecm.burnEEPROM()
                await MainActor.run {
                    isBurning = false
                    alert = EditorAlert(title: "Write Complete", message: "The changed pages were written to the ECM.")
                }
            } catch {
                await MainActor.run {
                    isBurning = false
                    alert = EditorAlert(title: "Write Failed", message: error.localizedDescription)
                }
            }
        }
    }
}

private struct EditorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Page byte editor

struct EEPROMPageEditorView: View {
    let page: EEPROM.Page
    var ecm = ECM.shared

    @State private var editingOffset: Int?
    @State private var editText = ""
    @State private var showEdit = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    /// Page 0 can't be burned (the write protocol doesn't support it), so editing
    /// its bytes would only create changes that can never reach the ECM.
    private var isReadOnly: Bool { page.nr == 0 }

    var body: some View {
        ScrollView {
            if isReadOnly {
                Text("Page 0 holds diagnostic data and cannot be written to the ECM.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top])
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(offsets, id: \.self) { offset in
                    byteCell(offset: offset)
                }
            }
            .padding()
        }
        .navigationTitle("Page \(page.nr)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Edit Byte", isPresented: $showEdit) {
            TextField("0–255 or 0x00–0xFF", text: $editText)
                .keyboardType(.asciiCapable)
            Button("Cancel", role: .cancel) { editingOffset = nil }
            Button("Set") { commitEdit() }
        } message: {
            if let offset = editingOffset {
                Text("Offset \(hex(offset, width: 4)) (page \(page.nr), byte \(offset - page.start))\nCurrent: \(byteDescription(offset))")
            }
        }
    }

    private var offsets: [Int] {
        guard page.start >= 0 else { return [] }
        let end = min(page.start + page.length, ecm.eeprom?.data.count ?? 0)
        guard end > page.start else { return [] }
        return Array(page.start..<end)
    }

    private func byteCell(offset: Int) -> some View {
        let value = ecm.getEEPROMByte(at: offset) ?? 0
        let modified = ecm.isByteModified(at: offset)
        return Button {
            editingOffset = offset
            editText = "\(value)"
            showEdit = true
        } label: {
            VStack(spacing: 2) {
                Text(hex(offset, width: 3))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(hex(Int(value), width: 2))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(modified ? .white : .primary)
                Text("\(value)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(modified ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(modified ? Color.buellGold : Color.buellGold.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
    }

    private func commitEdit() {
        defer { editingOffset = nil }
        guard let offset = editingOffset, let value = parseByte(editText) else { return }
        ecm.setEEPROMByte(at: offset, to: value)
    }

    private func byteDescription(_ offset: Int) -> String {
        let v = ecm.getEEPROMByte(at: offset) ?? 0
        var s = "\(v) (\(hex(Int(v), width: 2)))"
        if let orig = ecm.pristineByte(at: offset), orig != v {
            s += ", was \(orig) (\(hex(Int(orig), width: 2)))"
        }
        return s
    }

    /// Accepts decimal (0–255) or hex (0x.. / $.. / bare hex like FF), clamped to a byte.
    private func parseByte(_ text: String) -> UInt8? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return nil }
        let value: Int?
        if t.hasPrefix("0x") {
            value = Int(t.dropFirst(2), radix: 16)
        } else if t.hasPrefix("$") {
            value = Int(t.dropFirst(), radix: 16)
        } else if let dec = Int(t) {
            value = dec
        } else {
            value = Int(t, radix: 16)
        }
        guard let v = value, (0...255).contains(v) else { return nil }
        return UInt8(v)
    }

    private func hex(_ value: Int, width: Int) -> String {
        String(format: "0x%0\(width)X", value)
    }
}

// MARK: - Backups & restore

struct EEPROMBackupsView: View {
    var ecm = ECM.shared

    @State private var backups: [EEPROMBackup] = []
    @State private var restoreTarget: EEPROMBackup?
    @State private var alert: EditorAlert?

    var body: some View {
        List {
            if backups.isEmpty {
                ContentUnavailableView {
                    Label("No Backups", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Backups you save appear here, along with the automatic snapshot taken when you first read the EEPROM.")
                }
            } else {
                if !matchingBackups.isEmpty {
                    Section("This ECM (\(ecm.id ?? "?"))") {
                        ForEach(matchingBackups) { backup in
                            backupRow(backup, restorable: true)
                        }
                        .onDelete { deleteBackups(matchingBackups, at: $0) }
                    }
                }
                if !otherBackups.isEmpty {
                    Section("Other ECMs") {
                        ForEach(otherBackups) { backup in
                            backupRow(backup, restorable: false)
                        }
                        .onDelete { deleteBackups(otherBackups, at: $0) }
                    }
                }
            }
        }
        .navigationTitle("Backups & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore into Editor") { performRestore() }
            Button("Cancel", role: .cancel) { restoreTarget = nil }
        } message: {
            if let b = restoreTarget {
                Text("This loads \"\(b.name)\" into the editor and marks all pages to be written. Nothing is sent to the ECM until you choose Write to ECM.")
            }
        }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
        }
    }

    private var matchingBackups: [EEPROMBackup] {
        backups.filter { $0.ecmId == ecm.id }
    }

    private var otherBackups: [EEPROMBackup] {
        backups.filter { $0.ecmId != ecm.id }
    }

    private func backupRow(_ backup: EEPROMBackup, restorable: Bool) -> some View {
        Button {
            if restorable { restoreTarget = backup }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: backup.isAutomatic ? "a.circle.fill" : "square.and.arrow.down.fill")
                    .foregroundStyle(backup.isAutomatic ? .green : Color.buellGold)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.name)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("\(backup.byteCount) bytes • \(dateText(backup.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if restorable {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(Color.buellGold)
                }
            }
        }
        .disabled(!restorable)
    }

    private func reload() {
        backups = EEPROMBackupManager.shared.list()
    }

    private func dateText(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private func performRestore() {
        guard let backup = restoreTarget else { return }
        restoreTarget = nil
        do {
            try ecm.stageRestore(from: backup)
            alert = EditorAlert(title: "Restored", message: "\"\(backup.name)\" was loaded into the editor. Review the values, then use Write to ECM to apply them.")
        } catch {
            alert = EditorAlert(title: "Restore Failed", message: error.localizedDescription)
        }
    }

    private func deleteBackups(_ list: [EEPROMBackup], at offsets: IndexSet) {
        for index in offsets {
            try? EEPROMBackupManager.shared.delete(list[index])
        }
        reload()
    }
}
