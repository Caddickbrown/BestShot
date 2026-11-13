import AVFoundation
import PhotosUI
import SwiftUI

@MainActor @Observable
final class VideoJoinSession {
  var clips: [ToolVideoClip] = []
  var output = VideoJoinConfiguration.Output()
  var transition = VideoTransition()
  var overrides: [String: VideoTransition] = [:]
  var busy = false
  var phase = ""
  var progress = 0.0
  var error: String?
  var result: URL?
  var player: AVPlayer?
  var confirmedMixedSize = false
  private var workspace: MediaWorkspace?
  private var task: Task<Void, Never>?
  private var exporter: AVAssetExportSession?
  private var history: [[ToolVideoClip]] = []
  var canUndo: Bool { !history.isEmpty }
  var mixedSize: Bool {
    guard let first = clips.first else { return false }
    return clips.contains { $0.width != first.width || $0.height != first.height }
  }
  var mixedFPS: Bool {
    guard let first = clips.first else { return false }
    return clips.contains { abs($0.fps - first.fps) > 0.1 }
  }
  var config: VideoJoinConfiguration {
    VideoJoinConfiguration(
      clips: clips.map {
        .init(id: $0.id, source_ref: $0.name, in_ms: $0.startMS, out_ms: $0.startMS + $0.durationMS)
      },
      output: output, default_transition: transition,
      join_overrides: clips.dropLast().compactMap { clip in
        overrides[clip.id].map { .init(after_clip_id: clip.id, transition: $0) }
      })
  }
  var validation: String? {
    do {
      _ = try config.plan()
      if mixedSize && !confirmedMixedSize {
        return "Mixed dimensions: confirm the target size and Fit with padding below."
      }
      return nil
    } catch { return error.localizedDescription }
  }
  var durationText: String? {
    (try? config.plan()).map { plan in
      let seconds = Double(plan.duration_ms) / 1000
      return seconds < 60
        ? String(format: "%.1f s", seconds)
        : String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
  }
  func invalidate() {
    player?.pause()
    player = nil
    result = nil
  }
  private func remember() {
    history.append(clips)
    if history.count > 30 { history.removeFirst() }
    invalidate()
  }
  func move(_ from: IndexSet, to: Int) {
    remember()
    clips.move(fromOffsets: from, toOffset: to)
  }
  func move(_ index: Int, by delta: Int) {
    guard clips.indices.contains(index + delta) else { return }
    remember()
    clips.swapAt(index, index + delta)
  }
  func remove(_ id: String) {
    remember()
    clips.removeAll { $0.id == id }
  }
  func undo() {
    if let previous = history.popLast() {
      clips = previous
      invalidate()
    }
  }
  func add(_ urls: [URL], removeAfter: Bool = false) {
    guard !busy else { return }
    busy = true
    phase = "Inspecting clips…"
    error = nil
    task = Task {
      var pending: [URL] = []
      var committed = false
      defer {
        busy = false
        if !committed { pending.forEach { try? FileManager.default.removeItem(at: $0) } }
        if removeAfter { urls.forEach { ToolPickedFile.remove($0) } }
      }
      do {
        let workspace = try self.workspace ?? MediaWorkspace()
        self.workspace = workspace
        var imported: [ToolVideoClip] = []
        for url in urls {
          try Task.checkCancellation()
          let copy = try await Task.detached(priority: .userInitiated) {
            defer { if removeAfter { ToolPickedFile.remove(url) } }
            return try workspace.stage(url)
          }.value
          pending.append(copy)
          imported.append(try await ToolVideoClip.inspect(url: copy, name: url.lastPathComponent))
        }
        try Task.checkCancellation()
        remember()
        if clips.isEmpty, let first = imported.first {
          output.width = first.width
          output.height = first.height
          output.frame_rate =
            [24, 25, 30, 50, 60].min(by: { abs(Float($0) - first.fps) < abs(Float($1) - first.fps) }
            ) ?? 30
        }
        clips.append(contentsOf: imported)
        committed = true
        confirmedMixedSize = false
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func addPhotos(_ items: [PhotosPickerItem]) {
    guard !busy else { return }
    busy = true
    phase = "Downloading selected clips…"
    error = nil
    task = Task {
      var urls: [URL] = []
      do {
        for item in items {
          try Task.checkCancellation()
          guard let file = try await item.loadTransferable(type: ToolPickedFile.self) else {
            throw MediaToolError.message(
              "Photos could not provide a video. Try importing from Files.")
          }
          urls.append(file.url)
        }
        try Task.checkCancellation()
        busy = false
        add(urls, removeAfter: true)
      } catch {
        urls.forEach { ToolPickedFile.remove($0) }
        busy = false
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }
  func render(export: Bool, boundary: Int? = nil) {
    guard !busy, validation == nil, let workspace else { return }
    let snapshot = config
    let sources = clips
    busy = true
    progress = 0
    phase = export ? "Preparing export…" : "Preparing preview…"
    error = nil
    player?.pause()
    task = Task {
      var temporary: URL?
      defer {
        if let temporary { try? FileManager.default.removeItem(at: temporary) }
        busy = false
        exporter = nil
      }
      do {
        let built = try await VideoJoinService.build(clips: sources, config: snapshot)
        try Task.checkCancellation()
        if !export {
          let player = AVPlayer(playerItem: built.playerItem())
          self.player = player
          if let boundary, let timeline = try? snapshot.plan(),
            timeline.clips.indices.contains(boundary + 1)
          {
            let start = max(0, timeline.clips[boundary + 1].start_ms - 1500)
            player.currentItem?.forwardPlaybackEndTime = VideoJoinService.time(
              min(
                timeline.duration_ms,
                timeline.clips[boundary + 1].start_ms + timeline.joins[boundary].duration_ms + 1500)
            )
            await player.seek(
              to: VideoJoinService.time(start), toleranceBefore: .zero, toleranceAfter: .zero)
          }
          player.play()
          return
        }
        // A conservative estimate, including a bitrate allowance for long jobs.
        let pixels = Double(snapshot.output.width) * Double(snapshot.output.height)
        let bitsPerSecond = pixels * Double(snapshot.output.frame_rate) * 0.35 + 320_000
        let estimatedBytes = bitsPerSecond / 8 * (Double(built.durationMS) / 1000) * 1.5
        let estimate = Int64(min(Double(Int64.max / 2), estimatedBytes))
        try MediaWorkspace.requireSpace(
          at: workspace.directory, bytes: max(64 * 1024 * 1024, estimate))
        let partial = workspace.url("partial.mp4")
        temporary = partial
        let session = try VideoJoinService.exporter(
          built, codec: snapshot.output.codec, destination: partial)
        exporter = session
        phase = "Exporting MP4…"
        let monitor = Task { [weak self] in
          while !Task.isCancelled {
            self?.progress = Double(session.progress)
            try? await Task.sleep(for: .milliseconds(200))
          }
        }
        defer { monitor.cancel() }
        await withTaskCancellationHandler {
          await session.export()
        } onCancel: {
          Task { @MainActor [weak self] in self?.exporter?.cancelExport() }
        }
        try Task.checkCancellation()
        guard session.status == .completed else {
          throw session.error
            ?? MediaToolError.message(
              "Video export failed. Try H.264, a smaller output size, or different source files.")
        }
        let finished = workspace.url("mp4")
        try FileManager.default.moveItem(at: partial, to: finished)
        result = finished
        progress = 1
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func cancel() {
    task?.cancel()
    exporter?.cancelExport()
    player?.pause()
  }
}
