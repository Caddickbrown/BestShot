import AVKit
import PhotosUI
import SwiftUI

struct VideoJoinView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var session = VideoJoinSession()
  @State private var photos: [PhotosPickerItem] = []
  @State private var importing = false
  @State private var openingSettings = false
  @State private var savingSettings = false
  @State private var dragged: String?
  var body: some View {
    @Bindable var session = session
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Join whole clips in order. Originals stay untouched.").font(.note)
        HStack {
          Button("Add from Files") { importing = true }
          PhotosPicker(
            "Photos", selection: $photos, maxSelectionCount: 30, selectionBehavior: .ordered,
            matching: .videos)
          ToolProjectPicker(kind: .video) { session.add([$0]) }
        }.disabled(session.busy)
        ForEach(Array(session.clips.enumerated()), id: \.element.id) { index, clip in
          VStack(alignment: .leading, spacing: 8) {
            VideoClipRow(
              clip: clip, index: index, count: session.clips.count,
              up: { session.move(index, by: -1) }, down: { session.move(index, by: 1) },
              remove: { session.remove(clip.id) }
            )
            .onDrag {
              dragged = clip.id
              return NSItemProvider(object: clip.id as NSString)
            }
            .onDrop(of: [.text], isTargeted: nil) { _ in
              guard !session.busy, let dragged,
                let from = session.clips.firstIndex(where: { $0.id == dragged }), from != index
              else { return false }
              session.move(IndexSet(integer: from), to: index > from ? index + 1 : index)
              self.dragged = nil
              return true
            }
            if index < session.clips.count - 1 {
              Toggle(
                "Override join after clip \(index+1)",
                isOn: Binding(
                  get: { session.overrides[clip.id] != nil },
                  set: { value in
                    session.overrides[clip.id] = value ? session.transition : nil
                    session.invalidate()
                  }))
              if session.overrides[clip.id] != nil {
                VideoTransitionEditor(
                  transition: Binding(
                    get: { session.overrides[clip.id] ?? session.transition },
                    set: {
                      session.overrides[clip.id] = $0
                      session.invalidate()
                    }))
              }
              Button("Preview this join") { session.render(export: false, boundary: index) }
                .disabled(session.validation != nil)
            }
          }.padding().background(.primary.opacity(0.04)).clipShape(
            RoundedRectangle(cornerRadius: 8))
        }.disabled(session.busy)
        if !session.clips.isEmpty {
          Button("Undo order / removal") { session.undo() }.disabled(
            !session.canUndo || session.busy)
          GroupBox("Output · Fit with padding") {
            VStack(alignment: .leading) {
              HStack {
                TextField("Width", value: $session.output.width, format: .number)
                  .accessibilityLabel("Output width in pixels")
                Text("×")
                TextField("Height", value: $session.output.height, format: .number)
                  .accessibilityLabel("Output height in pixels")
              }.textFieldStyle(.roundedBorder)
              HStack {
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
              }
              Picker("Frame rate", selection: $session.output.frame_rate) {
                ForEach([24, 25, 30, 50, 60], id: \.self) { Text("\($0) fps").tag($0) }
              }
              Picker("Codec", selection: $session.output.codec) {
                Text("H.264").tag("h264")
                Text("HEVC").tag("hevc")
              }
              if session.mixedSize {
                Label(
                  "Mixed dimensions. The target defaults to the first clip. Clips fit inside it with black padding.",
                  systemImage: "exclamationmark.triangle")
                Toggle("Use this target resolution with padding", isOn: $session.confirmedMixedSize)
              }
              if session.mixedFPS {
                Label(
                  "Mixed frame rates: the selected rate may duplicate or drop frames.",
                  systemImage: "exclamationmark.triangle")
              }
              Text(
                "Output is re-encoded as SDR Rec.709. Retaining dimensions does not preserve source bitrate or compression quality."
              ).font(.caption)
              if session.clips.contains(where: \.isHDR) {
                Label(
                  "HDR source detected. This export converts to SDR; HDR preservation is not supported.",
                  systemImage: "exclamationmark.triangle")
              }
            }
          }.disabled(session.busy)
          GroupBox("Default transition for every join") {
            VideoTransitionEditor(transition: $session.transition)
          }.disabled(session.busy)
          Text(
            "Crossfades overlap clips and shorten the timeline. Fade through black splits the fade evenly around a sequential join and keeps the total duration."
          ).font(.caption)
          if let duration = session.durationText {
            Text("Timeline: \(duration)").font(.caption.monospaced())
          }
          if let validation = session.validation {
            Label(validation, systemImage: "exclamationmark.triangle")
          }
          HStack {
            Button("Preview all") { session.render(export: false) }
            Button("Export MP4") { session.render(export: true) }
          }.disabled(session.busy || session.validation != nil)
          HStack {
            Button("Save settings") { savingSettings = true }
            Button("Reopen settings") { openingSettings = true }
          }.disabled(session.busy)
        }
        if let player = session.player { VideoPlayer(player: player).frame(height: 260) }
        if session.busy {
          Text(session.phase)
          ProgressView(value: session.phase == "Exporting MP4…" ? session.progress : nil)
          Button("Cancel") { session.cancel() }
        }
        if let error = session.error {
          Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
        }
        if let url = session.result { MediaResultView(url: url, isVideo: true) }
      }.padding()
    }.tableSurface().navigationTitle("Join Videos")
      .fileImporter(
        isPresented: $importing, allowedContentTypes: [.movie], allowsMultipleSelection: true
      ) { result in
        switch result {
        case .success(let urls): session.add(urls)
        case .failure(let error): session.error = error.localizedDescription
        }
      }
      .fileImporter(isPresented: $openingSettings, allowedContentTypes: [.json]) { result in
        switch result {
        case .success(let url): session.loadSettings(url)
        case .failure(let error): session.error = error.localizedDescription
        }
      }
      .fileExporter(
        isPresented: $savingSettings,
        document: MediaSettingsDocument((try? JSONEncoder().encode(session.config)) ?? Data()),
        contentType: .json, defaultFilename: "BestShot-VideoJoin"
      ) { result in
        if case .failure(let error) = result { session.error = error.localizedDescription }
      }
      .onChange(of: photos) { _, items in
        if !items.isEmpty {
          session.addPhotos(items)
          photos = []
        }
      }
      .onChange(of: session.output.width) { _, _ in
        session.confirmedMixedSize = false
        session.invalidate()
      }
      .onChange(of: session.output.height) { _, _ in
        session.confirmedMixedSize = false
        session.invalidate()
      }
      .onChange(of: session.output.frame_rate) { _, _ in session.invalidate() }
      .onChange(of: session.output.codec) { _, _ in session.invalidate() }
      .onChange(of: session.transition) { _, _ in session.invalidate() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background && session.busy {
          session.cancel()
          session.error =
            "Operation cancelled when BestShot entered the background. Keep the app open while exporting."
        }
      }
      .onDisappear { session.cancel() }
  }
}

struct VideoClipRow: View {
  let clip: ToolVideoClip
  let index: Int
  let count: Int
  let up: () -> Void
  let down: () -> Void
  let remove: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        if let thumbnail = clip.thumbnail {
          Image(decorative: thumbnail, scale: 1).resizable().scaledToFit().frame(
            width: 70, height: 50)
        }
        VStack(alignment: .leading) {
          Text("\(index+1). \(clip.name)").lineLimit(2)
          Text(
            String(
              format: "%.3fs · %d × %d · %.2f fps", Double(clip.durationMS) / 1000, clip.width,
              clip.height, clip.fps)
          ).font(.caption.monospaced())
          Text(clip.hasAudio ? "Audio present" : "Silent clip").font(.caption)
        }
      }
      HStack {
        Button("Move up", action: up).disabled(index == 0).accessibilityLabel(
          "Move clip \(index+1) earlier")
        Button("Move down", action: down).disabled(index == count - 1).accessibilityLabel(
          "Move clip \(index+1) later")
        Button("Remove", action: remove).accessibilityLabel("Remove clip \(index+1)")
      }.font(.caption)
    }
  }
}

struct VideoTransitionEditor: View {
  @Binding var transition: VideoTransition
  var body: some View {
    VStack(alignment: .leading) {
      Picker(
        "Visual transition",
        selection: Binding(get: { transition.type }, set: { transition.setKind($0) })
      ) {
        ForEach(VideoTransition.kinds, id: \.self) { Text(VideoTransition.title($0)).tag($0) }
      }
      if transition.type != "hard_cut" {
        Stepper(value: $transition.duration_ms, in: 100...5000, step: 100) {
          Text("Fade: \(Double(transition.duration_ms)/1000,specifier:"%.1f") seconds")
        }
        Picker("Transition audio", selection: $transition.audio) {
          Text("Crossfade / fade").tag("crossfade")
          Text("Hard cut").tag("hard_cut")
          Text("Mute during transition").tag("mute")
        }
      }
    }
  }
}
