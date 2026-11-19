import PhotosUI
import SwiftUI

/// Multi Crop's editor state: one source, its boxes, and the files made from
/// them. In Folders (`beside` set) the files go next to the source; elsewhere
/// they wait in the workspace for Save to Photos or Share.
@MainActor @Observable
final class MultiCropSession {
  struct Edit: Equatable {
    var boxes: [CropBoxModel] = []
    var trim = 0
  }

  var source: ToolImage?
  var edit = Edit()
  var focused: String?
  var format = ToolOutputFormat.saved("multicrop") { didSet { format.save("multicrop") } }
  var results: [URL] = []
  var error: String?
  var notice: String?
  var busy = false
  var progress = 0.0
  var phase = ""
  /// Folders: the directory new files are published into.
  var beside: URL?
  /// Folders: told about the files once they're beside the source.
  var onMade: (([URL], String) -> Void)?

  private(set) var history = EditHistory<Edit>()
  private var workspace: MediaWorkspace?
  private var task: Task<Void, Never>?
  private var job: MediaRenderJob?
  private var nextID = 1
  /// Whether the boxes are still exactly what Find made (Find may replace them).
  private var untouchedFind = false

  /// The previous image's boxes, in proportion, for Use last crop. Kept until the app quits.
  static var lastCrop: (boxes: [CropBoxModel], trim: Int)?

  var plan: MultiCropPlan? {
    guard let source, !edit.boxes.isEmpty else { return nil }
    return try? MultiCropBridge.plan(source: source, boxes: edit.boxes, trim: edit.trim)
  }
  var validation: String? {
    guard let source, !edit.boxes.isEmpty else { return nil }
    do {
      _ = try MultiCropBridge.plan(source: source, boxes: edit.boxes, trim: edit.trim)
      return nil
    } catch { return error.localizedDescription }
  }
  /// Box numbers in output (reading) order.
  var numbers: [String: Int] {
    Dictionary(uniqueKeysWithValues: (plan?.boxes ?? []).map { ($0.id, $0.number) })
  }
  var canUseLast: Bool { Self.lastCrop != nil && source != nil }

  // MARK: - Changes, each one step of Undo

  func change(_ body: (inout Edit) -> Void) {
    let old = edit
    body(&edit)
    history.record(old, now: edit)
    if old != edit {
      results = []
      untouchedFind = false
    }
  }
  func beginDrag() { history.begin(edit) }
  func endDrag() {
    history.end(edit)
    untouchedFind = false
    results = []
  }
  func undo() { if let e = history.undo(edit) { edit = e; keepFocus() } }
  func redo() { if let e = history.redo(edit) { edit = e; keepFocus() } }
  private func keepFocus() { if let f = focused, !edit.boxes.contains(where: { $0.id == f }) { focused = nil } }

  func newID() -> String {
    while edit.boxes.contains(where: { $0.id == "b\(nextID)" }) { nextID += 1 }
    defer { nextID += 1 }
    return "b\(nextID)"
  }

  func box(_ id: String?) -> CropBoxModel? { edit.boxes.first { $0.id == id } }
  func update(_ id: String, _ body: (inout CropBoxModel) -> Void) {
    guard let i = edit.boxes.firstIndex(where: { $0.id == id }) else { return }
    body(&edit.boxes[i])
  }

  func add() {
    guard let source else { return }
    let last = box(focused) ?? edit.boxes.last
    let (w, h) = (last?.w ?? Double(source.width) / 3, last?.h ?? Double(source.height) / 3)
    let id = newID()
    change { $0.boxes.append(.rect(id: id, CGRect(x: Double(source.width) / 2 - w / 2, y: Double(source.height) / 2 - h / 2, width: w, height: h))) }
    focused = id
  }
  func duplicate() {
    guard let source, let b = box(focused) else { return }
    var copy = b
    copy.id = newID()
    // The next free spot along the row: one box width on, or down a row at the edge.
    let bounds = b.bounds
    var d = CGVector(dx: bounds.width + 8, dy: 0)
    if bounds.maxX + d.dx > CGFloat(source.width) { d = CGVector(dx: 0, dy: bounds.height + 8) }
    copy.move(by: d)
    change { $0.boxes.append(copy) }
    focused = copy.id
  }
  func remove() {
    guard let id = focused else { return }
    let order = orderedIDs
    change { $0.boxes.removeAll { $0.id == id } }
    if let i = order.firstIndex(of: id) {
      let rest = order.filter { $0 != id }
      focused = rest.isEmpty ? nil : rest[min(i, rest.count - 1)]
    }
  }
  var orderedIDs: [String] {
    let n = numbers
    return edit.boxes.map(\.id).sorted { (n[$0] ?? 0, $0) < (n[$1] ?? 0, $1) }
  }
  func focusStep(_ delta: Int) {
    let ids = orderedIDs
    guard !ids.isEmpty else { return }
    guard let f = focused, let i = ids.firstIndex(of: f) else {
      focused = delta > 0 ? ids.first : ids.last
      return
    }
    focused = ids[(i + delta + ids.count) % ids.count]
  }
  func turn(_ degrees: Int, box id: String? = nil) {
    guard let id = id ?? focused ?? (edit.boxes.count == 1 ? edit.boxes.first?.id : nil) else { return }
    change { e in
      if let i = e.boxes.firstIndex(where: { $0.id == id }) { e.boxes[i].turn = ((e.boxes[i].turn + degrees) % 360 + 360) % 360 }
    }
  }
  func rotate(_ degrees: Double) {
    guard let id = focused else { return }
    change { e in
      guard let i = e.boxes.firstIndex(where: { $0.id == id }) else { return }
      if !e.boxes[i].rect { e.boxes[i].toggleCorners() }
      e.boxes[i].angle = ((e.boxes[i].angle + degrees) * 10).rounded() / 10
    }
  }
  func nudge(dx: Double, dy: Double) {
    guard let id = focused else { return }
    change { e in if let i = e.boxes.firstIndex(where: { $0.id == id }) { e.boxes[i].move(by: CGVector(dx: dx, dy: dy)) } }
  }
  func resize(dw: Double, dh: Double) {
    guard let id = focused else { return }
    change { e in
      guard let i = e.boxes.firstIndex(where: { $0.id == id }) else { return }
      if !e.boxes[i].rect { e.boxes[i].toggleCorners() }
      // From the bottom-right edge: the top-left corner stays.
      let b = e.boxes[i]
      let a = b.angle * .pi / 180
      let nw = max(16, b.w + dw), nh = max(16, b.h + dh)
      let (gw, gh) = ((nw - b.w) / 2, (nh - b.h) / 2)
      e.boxes[i].w = nw
      e.boxes[i].h = nh
      e.boxes[i].cx += gw * cos(a) - gh * sin(a)
      e.boxes[i].cy += gw * sin(a) + gh * cos(a)
    }
  }
  func toggleCorners() {
    guard let id = focused else { return }
    change { e in if let i = e.boxes.firstIndex(where: { $0.id == id }) { e.boxes[i].toggleCorners() } }
  }

  /// The previous image's boxes on this one, in proportion.
  func useLast() {
    guard let source, let last = Self.lastCrop else { return }
    change { e in
      e.boxes = last.boxes.map { $0.scaled(sx: Double(source.width), sy: Double(source.height)) }
      e.trim = last.trim
    }
    nextID = last.boxes.count + 1
    focused = nil
  }

  // MARK: - Opening and finding

  func open(_ url: URL, origin: URL? = nil, extraKeywords: [String] = [], removeAfter: Bool = false, stageCopy: Bool = true) {
    guard !busy else { return }
    busy = true
    error = nil
    phase = "Opening image…"
    task = Task {
      defer { busy = false }
      do {
        let workspace = try self.workspace ?? MediaWorkspace()
        self.workspace = workspace
        let image = try await Task.detached(priority: .userInitiated) {
          defer { if removeAfter { ToolPickedFile.remove(url) } }
          let readable = stageCopy ? try workspace.stage(url) : url
          return try ToolImaging.inspect(readable, origin: origin ?? url, extraKeywords: extraKeywords)
        }.value
        try Task.checkCancellation()
        source = image
        edit = Edit()
        history.clear()
        results = []
        focused = nil
        nextID = 1
        busy = false
        find(replacing: true)
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
          throw MediaToolError.message("Photos could not provide this image. Try exporting it to Files first.")
        }
        busy = false
        open(picked.url, removeAfter: true)
      } catch {
        busy = false
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }

  /// Find photos. Replaces the boxes when none have been edited since the
  /// last Find; otherwise adds only the ones not already covered.
  func find(replacing: Bool = false) {
    guard let source, !busy else { return }
    busy = true
    phase = "Finding photos…"
    let replace = replacing || edit.boxes.isEmpty || untouchedFind
    task = Task {
      defer { busy = false }
      do {
        let found = try await Task.detached(priority: .userInitiated) { try MultiCropBridge.find(in: source) }.value
        let old = edit
        if replace {
          edit.boxes = found
          nextID = found.count + 1
        } else {
          for var b in found where !edit.boxes.contains(where: { overlaps($0.bounds, b.bounds) }) {
            b.id = newID()
            edit.boxes.append(b)
          }
        }
        if edit.trim == 0 && !found.isEmpty { edit.trim = 4 }
        history.record(old, now: edit)
        untouchedFind = true
        results = []
        notice = found.isEmpty ? "No photos found. Drag to draw a box, or press F to try again." : nil
      } catch { self.error = error.localizedDescription }
    }
  }

  private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
    let i = a.intersection(b)
    guard !i.isNull else { return false }
    return i.width * i.height > 0.5 * min(a.width * a.height, b.width * b.height)
  }

  // MARK: - Making the files

  func make() {
    guard !busy, let source, let workspace, plan != nil else { return }
    let snapshot = edit
    let format = format
    let beside = beside
    let existing = beside.map(ToolImaging.names(in:)) ?? []
    let job = MediaRenderJob()
    self.job = job
    busy = true
    progress = 0
    phase = "Making \(snapshot.boxes.count) photo\(snapshot.boxes.count == 1 ? "" : "s")…"
    error = nil
    results = []
    task = Task {
      defer {
        busy = false
        self.job = nil
      }
      do {
        let worker = Task.detached(priority: .userInitiated) { () throws -> [URL] in
          let made = try MultiCropBridge.export(
            source: source, boxes: snapshot.boxes, trim: snapshot.trim, format: format, existing: existing,
            workspace: workspace, job: job
          ) { value in Task { @MainActor [weak self] in self?.progress = value } }
          guard let beside else { return made }
          var published: [URL] = []
          do {
            for url in made { published.append(try ToolImaging.publish(url, as: url.lastPathComponent, in: beside)) }
          } catch {
            ToolImaging.takeBack(published)
            throw error
          }
          return published
        }
        let urls = try await withTaskCancellationHandler { try await worker.value } onCancel: {
          job.cancel()
          worker.cancel()
        }
        Self.lastCrop = (snapshot.boxes.map { $0.normalised(width: source.width, height: source.height) }, snapshot.trim)
        results = urls
        let text = "Made \(urls.count) photo\(urls.count == 1 ? "" : "s") from \(source.stem)"
        notice = text
        onMade?(urls, text)
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }

  /// After making files: take them back (Trash on the Mac).
  func takeBack() {
    guard !results.isEmpty, beside != nil else { return }
    ToolImaging.takeBack(results)
    results = []
    notice = "Taken back."
  }

  func cancel() {
    job?.cancel()
    task?.cancel()
  }
}
