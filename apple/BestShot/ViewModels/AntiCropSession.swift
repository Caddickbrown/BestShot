import PhotosUI
import SwiftUI

@MainActor @Observable
final class AntiCropSession {
  var source: AntiCropBridge.Source?
  var edit = AntiCropConfiguration()
  var result: URL?
  var error: String?
  var busy = false
  var progress = 0.0
  var phase = ""
  private var workspace: MediaWorkspace?
  private var task: Task<Void, Never>?
  private var job: MediaRenderJob?
  private var undoEdits: [AntiCropConfiguration] = []
  private var applyingUndo = false

  var geometry: CropGeometry? {
    guard let source else { return nil }
    return try? edit.plan(width: source.width, height: source.height)
  }
  var validation: String? {
    guard let source else { return nil }
    do {
      _ = try edit.plan(width: source.width, height: source.height)
      return nil
    } catch { return error.localizedDescription }
  }
  var canUndo: Bool { !undoEdits.isEmpty }
  func record(_ old: AntiCropConfiguration) {
    result = nil
    if old.source_ref != edit.source_ref {
      undoEdits = []
      return
    }
    if applyingUndo {
      applyingUndo = false
      return
    }
    undoEdits.append(old)
    if undoEdits.count > 100 { undoEdits.removeFirst() }
  }
  func undo() {
    if let previous = undoEdits.popLast() {
      applyingUndo = true
      edit = previous
    }
  }
  func reset() {
    guard let source else { return }
    let dimension = edit.axis == "horizontal" ? source.height : source.width
    edit.remove_start_px = max(1, dimension / 3)
    edit.remove_end_px = max(2, dimension * 2 / 3)
  }
  func open(_ url: URL, removeAfter: Bool = false) {
    guard !busy else { return }
    busy = true
    error = nil
    phase = "Opening image…"
    task = Task {
      defer { busy = false }
      do {
        let workspace = try self.workspace ?? MediaWorkspace()
        self.workspace = workspace
        let imported = try await Task.detached(priority: .userInitiated) {
          defer { if removeAfter { ToolPickedFile.remove(url) } }
          let staged = try workspace.stage(url)
          do { return try AntiCropBridge.inspect(staged) } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
          }
        }.value
        if Task.isCancelled {
          try? FileManager.default.removeItem(at: imported.url)
          throw CancellationError()
        }
        if let previous = source?.url { try? FileManager.default.removeItem(at: previous) }
        source = imported
        edit.source_ref = url.lastPathComponent
        reset()
        undoEdits = []
        result = nil
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func openPhoto(_ item: PhotosPickerItem) {
    guard !busy else { return }
    busy = true
    error = nil
    phase = "Downloading selected image…"
    task = Task {
      do {
        guard let picked = try await item.loadTransferable(type: ToolPickedFile.self) else {
          throw MediaToolError.message(
            "Photos could not provide this image. Try exporting it to Files first.")
        }
        if Task.isCancelled {
          ToolPickedFile.remove(picked.url)
          throw CancellationError()
        }
        busy = false
        open(picked.url, removeAfter: true)
      } catch {
        busy = false
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }
  func export() {
    guard !busy, let source, let workspace else { return }
    let snapshot = edit
    let job = MediaRenderJob()
    self.job = job
    busy = true
    progress = 0
    phase = "Exporting original pixels…"
    error = nil
    result = nil
    task = Task {
      defer {
        busy = false
        self.job = nil
      }
      do {
        let worker = Task.detached(priority: .userInitiated) {
          try AntiCropBridge.export(source: source, edit: snapshot, workspace: workspace, job: job)
          { value in
            Task { @MainActor [weak self] in self?.progress = value }
          }
        }
        let output = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          job.cancel()
          worker.cancel()
        }
        try Task.checkCancellation()
        result = output
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func cancel() {
    job?.cancel()
    task?.cancel()
  }
  func loadSettings(_ url: URL) {
    error = nil
    do {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let saved = try JSONDecoder().decode(AntiCropConfiguration.self, from: Data(contentsOf: url))
      guard let source else {
        throw MediaToolError.message("Open the original image before reopening settings.")
      }
      guard saved.source_ref == edit.source_ref else {
        throw MediaToolError.message(
          "These settings refer to \(saved.source_ref). Open that original image before reopening the settings."
        )
      }
      _ = try saved.plan(width: source.width, height: source.height)
      edit = saved
    } catch { self.error = error.localizedDescription }
  }
}
