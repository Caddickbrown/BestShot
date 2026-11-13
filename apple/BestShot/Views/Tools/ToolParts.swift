import SwiftData
import SwiftUI

// Parts Join Videos and Anti-Crop share, in the light table's look: the
// project picker, a pixel field, and the bar along the bottom with the one
// red pill.

/// Picks media already in a project, using its file on disk, without the
/// Data-based import path. Videos can be picked several at a time, in the order
/// tapped; a photo is picked with one tap.
struct ToolProjectPicker: View {
    let kind: MediaType
    let choose: ([URL]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MediaItem.importedAt, order: .reverse) private var items: [MediaItem]
    @State private var picked: [UUID] = []

    private var matching: [MediaItem] { items.filter { $0.mediaType == kind } }
    private var many: Bool { kind == .video }

    var body: some View {
        NavigationStack {
            Group {
                if matching.isEmpty {
                    EmptyState(kind == .video ? "No Videos" : "No Photos",
                               message: "Nothing like this has been imported into a project yet.")
                } else {
                    List {
                        TableSection(many ? "Tap in the order to join" : "Tap a photo") {
                            ForEach(matching) { item in
                                Button { tap(item) } label: { row(item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .tableForm()
            .navigationTitle(kind == .video ? "Project Videos" : "Project Photos")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if many {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(picked.isEmpty ? "Add" : "Add \(picked.count)") {
                            choose(picked.compactMap { id in matching.first { $0.uuid == id }?.fileURL })
                            dismiss()
                        }
                        .disabled(picked.isEmpty)
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .escapeScreen { dismiss() }
    }

    private func row(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            AsyncFileImage(url: item.thumbnailURL ?? (item.mediaType == .image ? item.fileURL : nil),
                           downsampleTo: 120)
                .frame(width: 44, height: 44)
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename).font(.row).lineLimit(1)
                Text(item.project?.name ?? "Project")
                    .font(.small)
                    .foregroundStyle(Theme.table.muted)
            }
            Spacer()
            if let position = picked.firstIndex(of: item.uuid) {
                Text("\(position + 1)")
                    .font(.mono(13, medium: true))
                    .foregroundStyle(Theme.table.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private func tap(_ item: MediaItem) {
        guard many else {
            choose([item.fileURL])
            dismiss()
            return
        }
        if let index = picked.firstIndex(of: item.uuid) { picked.remove(at: index) } else { picked.append(item.uuid) }
    }
}

/// A whole number of pixels, in a field Esc can leave. Typing that isn't yet a
/// number leaves the value as it was.
struct PixelField: View {
    let label: String
    @Binding var value: Int
    @State private var draft = ""

    var body: some View {
        HStack {
            Text(label).font(.row)
            Spacer()
            EscapingField(placeholder: "0", text: $draft, numeric: true)
                .frame(maxWidth: 110)
            Text("px").font(.small).foregroundStyle(Theme.table.muted)
        }
        .onAppear { draft = String(value) }
        .onChange(of: value) { _, new in if Int(draft) != new { draft = String(new) } }
        .onChange(of: draft) { _, text in if let number = Int(text), number != value { value = number } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// Where a tool's media comes from: Photos (the pill), Files, or a project.
/// Shown on the empty screen.
struct ToolSourceButtons<Photos: View>: View {
    let files: () -> Void
    let project: () -> Void
    @ViewBuilder var photos: () -> Photos

    var body: some View {
        photos()
        HStack(spacing: Theme.Space.actions) {
            Button("From Files", action: files)
            Button("From a project", action: project)
        }
        .buttonStyle(.text)
    }
}

/// The bottom of a tool: its main action while editing, progress and Cancel
/// while working, then Save to Photos (the pill) and Share once there's a file.
struct ToolBottomBar<Idle: View>: View {
    let busy: Bool
    let phase: String
    /// Nil while there's no measure of how far through.
    let progress: Double?
    let cancel: () -> Void
    let result: URL?
    let isVideo: Bool
    @ViewBuilder var idle: () -> Idle

    @State private var saving = false
    @State private var saved = false
    @State private var message: String?

    var body: some View {
        BottomBar {
            if busy {
                HStack {
                    Text(phase).font(.note).foregroundStyle(Theme.table.muted)
                    Spacer()
                    if progress == nil { ProgressView().controlSize(.small) }
                    Button("Cancel", action: cancel).buttonStyle(.text)
                }
                if let progress { ProgressLine(value: progress) }
            } else if let result {
                HStack(spacing: Theme.Space.actions) {
                    ShareLink(item: result) { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.text)
                    Spacer()
                    Button {
                        save(result)
                    } label: {
                        Text(saved ? "Saved to Photos" : saving ? "Saving…" : "Save to Photos")
                    }
                    .buttonStyle(.pill)
                    .disabled(saving || saved)
                }
                if let message { FormNote(message) }
            } else {
                idle()
            }
        }
        .onChange(of: result) {
            saved = false
            message = nil
        }
    }

    private func save(_ url: URL) {
        saving = true
        message = nil
        Task {
            let ok = await PhotoLibraryService.shared.saveFile(url, isVideo: isVideo)
            saving = false
            saved = ok
            if !ok { message = "Couldn't save. Allow BestShot to add to Photos in Settings." }
        }
    }
}

/// Small print in the accent: something went wrong.
struct ToolError: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.note)
            .foregroundStyle(Theme.table.accent)
            .textSelection(.enabled)
    }
}

/// A tool opened from a project, over it: the tool and Done, and Esc closes it.
struct ToolSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .escapeScreen { dismiss() }
    }
}
