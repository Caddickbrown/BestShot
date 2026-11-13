import AVKit
import PhotosUI
import SwiftUI

/// Join Videos: whole clips end to end, with cuts or fades, exported as one MP4.
/// Opened from Tools in the menu, or with videos selected in a project.
struct VideoJoinView: View {
    /// Clips to add straight away, in order, when started from a project.
    var initial: [URL] = []

    @Environment(\.scenePhase) private var scenePhase
    @State private var session = VideoJoinSession()
    @State private var photos: [PhotosPickerItem] = []
    @State private var choosingPhotos = false
    @State private var choosingFiles = false
    @State private var choosingProject = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "Tools", title: "Join Videos", status: status)
            if session.clips.isEmpty {
                empty
            } else {
                editor
            }
        }
        .tableSurfaceList()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !session.clips.isEmpty || session.busy {
                ToolBottomBar(
                    busy: session.busy, phase: session.phase,
                    progress: session.phase == "Exporting MP4…" ? session.progress : nil,
                    cancel: session.cancel, result: session.result, isVideo: true
                ) {
                    HStack(spacing: Theme.Space.actions) {
                        Button("Preview") { session.render(export: false) }
                            .buttonStyle(.text)
                        Button { session.render(export: true) } label: {
                            Text("Export MP4").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pill)
                    }
                    .disabled(session.validation != nil)
                }
            }
        }
        .photosPicker(isPresented: $choosingPhotos, selection: $photos, maxSelectionCount: 30,
                      selectionBehavior: .ordered, matching: .videos)
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): session.add(urls)
            case .failure(let error): session.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $choosingProject) {
            ToolProjectPicker(kind: .video) { session.add($0) }
        }
        .onChange(of: photos) { _, items in
            if !items.isEmpty {
                session.addPhotos(items)
                photos = []
            }
        }
        .onChange(of: session.output.width) {
            session.confirmedMixedSize = false
            session.invalidate()
        }
        .onChange(of: session.output.height) {
            session.confirmedMixedSize = false
            session.invalidate()
        }
        .onChange(of: session.output.frame_rate) { session.invalidate() }
        .onChange(of: session.output.codec) { session.invalidate() }
        .onChange(of: session.transition) { session.invalidate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && session.busy {
                session.cancel()
                session.error = "Stopped when BestShot went into the background. Keep it open while exporting."
            }
        }
        .task {
            if !initial.isEmpty && session.clips.isEmpty { session.add(initial) }
        }
        .onDisappear { session.cancel() }
    }

    private var status: String? {
        let n = session.clips.count
        guard n > 0 else { return nil }
        let clips = "\(n) clip\(n == 1 ? "" : "s")"
        return session.durationText.map { "\(clips) · \($0)" } ?? clips
    }

    // MARK: - Nothing added

    private var empty: some View {
        EmptyState(title: "Add Videos",
                   message: "Put two or more clips end to end, with cuts or fades, as one video. The originals stay as they are.") {
            if !session.busy {
                ToolSourceButtons(files: { choosingFiles = true }, project: { choosingProject = true }) {
                    Button("Choose from Photos") { choosingPhotos = true }
                        .buttonStyle(.pill)
                }
            }
            if let error = session.error { ToolError(text: error) }
        }
    }

    // MARK: - Editing

    private var editor: some View {
        @Bindable var session = session
        return Form {
            if let player = session.player {
                Section {
                    VideoPlayer(player: player)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }

            TableSection(title: "Clips") {
                ForEach(Array(session.clips.enumerated()), id: \.element.id) { index, clip in
                    VideoClipRow(clip: clip, index: index)
                        .accessibilityAction(named: "Move earlier") { session.move(index, by: -1) }
                        .accessibilityAction(named: "Move later") { session.move(index, by: 1) }
                }
                .onMove { session.move($0, to: $1) }
                .onDelete { offsets in
                    offsets.map { session.clips[$0].id }.forEach { session.remove($0) }
                }
                HStack(spacing: Theme.Space.actions) {
                    Menu {
                        Button("From Photos") { choosingPhotos = true }
                        Button("From Files") { choosingFiles = true }
                        Button("From a project") { choosingProject = true }
                    } label: {
                        Label("Add Clips", systemImage: "plus")
                    }
                    Spacer()
                    Button("Undo") { session.undo() }.disabled(!session.canUndo)
                }
                .buttonStyle(.text)
                .font(.note)
            } footer: {
                FormNote("Hold and drag a clip to move it; swipe left to take it out.")
            }

            if session.clips.count >= 2 {
                TableSection(title: "Every join") {
                    VideoTransitionEditor(transition: $session.transition)
                } footer: {
                    FormNote("A crossfade overlaps the clips, so the video gets shorter. Fade through black fades out, then in, and keeps the length.")
                }

                TableSection("Each join") {
                    ForEach(Array(session.clips.dropLast().enumerated()), id: \.element.id) { index, clip in
                        joinRow(index: index, clip: clip)
                    }
                }

                outputSection
            }

            if let problem = session.validation ?? session.error {
                TableSection { ToolError(text: problem) }
            }
        }
        .tableForm()
        .scrollDismissesKeyboard(.interactively)
        .disabled(session.busy)
    }

    @ViewBuilder
    private func joinRow(index: Int, clip: ToolVideoClip) -> some View {
        let own = Binding(
            get: { session.overrides[clip.id] != nil },
            set: { on in
                session.overrides[clip.id] = on ? session.transition : nil
                session.invalidate()
            }
        )
        HStack {
            Text("\(index + 1) → \(index + 2)").font(.row)
            Spacer()
            Button("Preview") { session.render(export: false, boundary: index) }
                .buttonStyle(.text)
                .disabled(session.validation != nil)
        }
        Toggle("Its own transition", isOn: own)
        if session.overrides[clip.id] != nil {
            VideoTransitionEditor(transition: Binding(
                get: { session.overrides[clip.id] ?? session.transition },
                set: {
                    session.overrides[clip.id] = $0
                    session.invalidate()
                }
            ))
        }
    }

    private var outputSection: some View {
        @Bindable var session = session
        return TableSection(title: "Output") {
            PixelField(label: "Width", value: $session.output.width)
            PixelField(label: "Height", value: $session.output.height)
            HStack(spacing: Theme.Space.actions) {
                Button("1080p") {
                    session.output.width = 1920
                    session.output.height = 1080
                }
                Button("Portrait") {
                    session.output.width = 1080
                    session.output.height = 1920
                }
                Button("First clip") {
                    if let first = session.clips.first {
                        session.output.width = first.width
                        session.output.height = first.height
                    }
                }
                Spacer()
            }
            .buttonStyle(.text)
            Picker("Frame rate", selection: $session.output.frame_rate) {
                ForEach([24, 25, 30, 50, 60], id: \.self) { Text("\($0) fps").tag($0) }
            }
            Picker("Format", selection: $session.output.codec) {
                Text("H.264").tag("h264")
                Text("HEVC").tag("hevc")
            }
            if session.mixedSize {
                Toggle("Fit every clip in this size, with black bars", isOn: $session.confirmedMixedSize)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if session.mixedSize {
                    FormNote("The clips are different sizes. Each is fitted inside the output, with black bars where it doesn't fill it.")
                }
                if session.mixedFPS {
                    FormNote("The clips have different frame rates, so some frames may be repeated or dropped.")
                }
                if session.clips.contains(where: \.isHDR) {
                    FormNote("HDR clips come out in standard range: HDR isn't kept.")
                }
                FormNote("Always re-encoded as SDR MP4. The same size doesn't mean the same quality or file size as the originals.")
            }
        }
    }
}

struct VideoClipRow: View {
    let clip: ToolVideoClip
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = clip.thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
                } else {
                    Theme.table.tile
                }
            }
            .frame(width: 56, height: 42)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text("\(index + 1). \(clip.name)").font(.row).lineLimit(1)
                Text(String(format: "%.1f s · %d × %d · %.0f fps", Double(clip.durationMS) / 1000,
                            clip.width, clip.height, clip.fps) + (clip.hasAudio ? "" : " · silent"))
                    .font(.small)
                    .foregroundStyle(Theme.table.muted)
            }
        }
    }
}

struct VideoTransitionEditor: View {
    @Binding var transition: VideoTransition

    var body: some View {
        Picker("Transition", selection: Binding(get: { transition.type }, set: { transition.setKind($0) })) {
            ForEach(VideoTransition.kinds, id: \.self) { Text(VideoTransition.title($0)).tag($0) }
        }
        if transition.type != "hard_cut" {
            Stepper(value: $transition.duration_ms, in: 100...5000, step: 100) {
                Text("Length \(Double(transition.duration_ms) / 1000, specifier: "%.1f") s").font(.row)
            }
            Picker("Sound", selection: $transition.audio) {
                Text("Fade").tag("crossfade")
                Text("Cut").tag("hard_cut")
                Text("Silent").tag("mute")
            }
        }
    }
}
