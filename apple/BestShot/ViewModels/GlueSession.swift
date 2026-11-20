import PhotosUI
import SwiftUI

/// Glue's editor state: the photos, the edit the core plans, and the file made.
@MainActor @Observable
final class GlueSession {
  var images: [ToolImage] = []
  var edit = GlueConfiguration()
  /// Index into `images` (and `edit.sources`).
  var focused: Int?
  var format = ToolOutputFormat.saved("glue") { didSet { format.save("glue") } }
  var result: URL?
  var error: String?
  var notice: String?
  var busy = false
  var progress = 0.0
  var phase = ""
  var beside: URL?
  var onMade: (([URL], String) -> Void)?
  /// Leaves the editor (Folders' sheet); nil where it's a place of its own.
  var onClose: (() -> Void)?
  /// The canvas zoom (1 fits), shared by the keys, the phone and the monitor.
  var zoom: CGFloat = 1
  /// Showing "before": the photos butted with no settings (`\`).
  var before = false

  private(set) var history = EditHistory<GlueConfiguration>()
  private var workspace: MediaWorkspace?
  private var task: Task<Void, Never>?
  private var job: MediaRenderJob?
  private var turnedPreviews: [String: CGImage] = [:]

  static let maxPhotos = 10

  var plan: GluePlan? { images.count >= 2 ? try? edit.plan() : nil }
  /// What the canvas shows: the plan, or the before view's.
  var shownPlan: GluePlan? {
    guard before else { return plan }
    return images.count >= 2 ? try? edit.before.plan() : nil
  }
  /// The edit behind `shownPlan`, for its fades.
  var shownEdit: GlueConfiguration { before ? edit.before : edit }
  var validation: String? {
    guard images.count >= 2 else { return images.isEmpty ? nil : "Add at least one more photo." }
    do {
      _ = try edit.plan()
      return nil
    } catch { return error.localizedDescription }
  }
  var vertical: Bool { plan?.orientation == "vertical" }
  var isFree: Bool { edit.arrangement == "free" }

  /// A photo's preview as it's turned.
  func preview(_ index: Int) -> CGImage? {
    guard images.indices.contains(index) else { return nil }
    let turn = edit.sources[index].turn
    let key = "\(images[index].id)-\(turn)"
    if let cached = turnedPreviews[key] { return cached }
    let image = ToolImaging.turned(images[index].preview, turn)
    turnedPreviews[key] = image
    return image
  }

  // MARK: - Changes

  func change(_ body: (inout GlueConfiguration) -> Void) {
    let old = edit
    body(&edit)
    history.record(old, now: edit)
    if old != edit { result = nil }
  }
  func beginDrag() { history.begin(edit) }
  func endDrag() {
    history.end(edit)
    result = nil
  }
  func undo() { if let e = history.undo(edit) { edit = e } }
  func redo() { if let e = history.redo(edit) { edit = e } }

  func flipLayout() {
    let now = vertical ? "horizontal" : "vertical"
    change {
      $0.orientation = now
      $0.offsets_px = []
    }
  }
  func setArrangement(_ arrangement: String) {
    guard arrangement != edit.arrangement else { return }
    // Free starts from the layout on screen, so the tidy one is where jagged begins.
    let current = plan
    change { e in
      if arrangement == "free", let current {
        var places = Array(repeating: GlueConfiguration.Place(x: 0, y: 0, w: 100), count: e.sources.count)
        for item in current.items {
          places[item.index] = .init(x: Double(item.x), y: Double(item.y), w: Double(item.w))
        }
        e.free = places
        if e.join_px < 0 { e.fade_px = min(e.fade_px, 40) }
      }
      e.arrangement = arrangement
      e.offsets_px = []
    }
  }
  func cycleArrangement() {
    let all = ["line", "grid", "free"]
    setArrangement(all[((all.firstIndex(of: edit.arrangement) ?? 0) + 1) % all.count])
  }
  func cycleSize() {
    let all = ["match_smaller", "match_larger", "keep"]
    change { $0.size = all[((all.firstIndex(of: $0.size) ?? 0) + 1) % all.count] }
  }
  func setJoin(_ value: Int) {
    let limit = plan?.max_overlap_px ?? 0
    change {
      $0.join_px = max(-limit, min(2000, value))
      // A one-off Line up value gives way to the slider.
      for k in $0.seams.indices { $0.seams[k].join_px = nil }
    }
  }
  func setFade(_ value: Int) { change { $0.fade_px = max(0, min(4000, value)) } }
  func turn(_ degrees: Int, photo index: Int? = nil) {
    guard let i = index ?? focused ?? (images.count == 1 ? 0 : nil) else { return }
    change { e in
      let s = e.sources[i]
      let ratio = s.turn % 180 == 90 ? Double(s.width) / Double(s.height) : Double(s.height) / Double(s.width)
      e.sources[i].turn = ((s.turn + degrees) % 360 + 360) % 360
      // In Free, keep its area about the same when it turns a quarter.
      if e.arrangement == "free", e.free.indices.contains(i), degrees % 180 != 0 { e.free[i].w *= ratio }
    }
  }
  func move(_ index: Int, by delta: Int) {
    let target = index + delta
    guard images.indices.contains(index), images.indices.contains(target) else { return }
    change { e in
      e.sources.swapAt(index, target)
      if e.free.count == e.sources.count { e.free.swapAt(index, target) }
      if e.offsets_px.count == e.sources.count { e.offsets_px.swapAt(index, target) }
    }
    images.swapAt(index, target)
    focused = target
  }
  func removePhoto(_ index: Int) {
    guard images.indices.contains(index) else { return }
    change { e in
      e.sources.remove(at: index)
      if e.free.count > index { e.free.remove(at: index) }
      if e.offsets_px.count > index { e.offsets_px.remove(at: index) }
      e.seams = []
    }
    images.remove(at: index)
    focused = images.isEmpty ? nil : min(index, images.count - 1)
  }
  /// The focused photo's join: the one after it (before it, for the last).
  /// Only a line's joins are numbered one per neighbouring pair.
  var focusedJoin: Int? {
    guard let plan, let i = focused, edit.arrangement == "line", !plan.joins.isEmpty else { return nil }
    return min(i, plan.joins.count - 1)
  }
  func moveSeam(_ delta: Double) {
    guard let k = focusedJoin else { return }
    change { $0 = Self.seamMoved($0, plan: plan, join: k, by: delta) }
  }
  /// Dragging a seam: no Undo step per move (`beginDrag`/`endDrag` make one).
  func dragSeam(_ k: Int, by delta: Double) {
    edit = Self.seamMoved(edit, plan: plan, join: k, by: delta)
  }
  /// The seam of join `k` moved `delta` output pixels along its overlap, kept inside it.
  static func seamMoved(_ e: GlueConfiguration, plan: GluePlan?, join k: Int, by delta: Double) -> GlueConfiguration {
    guard let plan, plan.joins.indices.contains(k), plan.joins[k].join_px < 0 else { return e }
    let overlap = Double(-plan.joins[k].join_px)
    var e = e
    while e.seams.count <= k { e.seams.append(.init()) }
    e.seams[k].position = max(0, min(1, e.seams[k].position + delta / overlap))
    return e
  }
  /// The join whose seam is within `reach` of `p` (output pixels), on a line with an overlap.
  static func seamHit(_ plan: GluePlan, at p: CGPoint, reach: Double, line: Bool) -> Int? {
    guard line else { return nil }
    var best: (Int, Double)?
    for (k, join) in plan.joins.enumerated() where join.join_px < 0 {
      let d = abs((join.axis == "x" ? p.x : p.y) - join.seam_px)
      if d <= reach, d < (best?.1 ?? .infinity) { best = (k, d) }
    }
    return best?.0
  }
  /// The fade at join `k`: its own, or the shared one.
  func fade(atJoin k: Int) -> Int { edit.seams.indices.contains(k) ? edit.seams[k].fade_px ?? edit.fade_px : edit.fade_px }
  func hasOwnFade(_ k: Int) -> Bool { edit.seams.indices.contains(k) && edit.seams[k].fade_px != nil }
  /// Join `k`'s own fade; nil goes back to the shared one.
  func setJoinFade(_ k: Int, _ value: Int?) {
    change { e in
      while e.seams.count <= k { e.seams.append(.init()) }
      e.seams[k].fade_px = value.map { max(0, min(4000, $0)) }
    }
  }
  /// For the slider: no Undo step per move.
  func dragJoinFade(_ k: Int, _ value: Int) {
    while edit.seams.count <= k { edit.seams.append(.init()) }
    edit.seams[k].fade_px = max(0, min(4000, value))
  }
  func offset(_ delta: Int) {
    guard let i = focused, edit.arrangement == "line" else { return }
    change { e in
      if e.offsets_px.count != e.sources.count { e.offsets_px = Array(repeating: 0, count: e.sources.count) }
      e.offsets_px[i] += delta
    }
    if validation != nil { undo() }
  }
  func moveFree(_ index: Int, dx: Double, dy: Double) {
    guard edit.free.indices.contains(index) else { return }
    edit.free[index].x += dx
    edit.free[index].y += dy
  }
  func nudgeFree(dx: Int, dy: Int) {
    guard let i = focused, isFree else { return }
    change { e in
      e.free[i].x += Double(dx)
      e.free[i].y += Double(dy)
    }
  }
  func focusStep(_ delta: Int) {
    guard !images.isEmpty else { return }
    focused = ((focused ?? (delta > 0 ? -1 : 0)) + delta + images.count) % images.count
  }

  func lineUp() {
    guard !busy, images.count >= 2 else { return }
    let edit = edit
    let images = images
    busy = true
    phase = "Lining up…"
    task = Task {
      defer { busy = false }
      do {
        let lined = try await Task.detached(priority: .userInitiated) { try GlueBridge.lineUp(edit, images: images) }.value
        if let lined {
          change { $0 = lined }
          notice = "Lined up."
        } else {
          notice = "Couldn't line these up."
        }
      } catch { notice = "Couldn't line these up." }
    }
  }

  // MARK: - Keys

  /// One editor command, from the keyboard on the phone, the Mac or the monitor.
  /// False when it does nothing here (Esc with nothing to close).
  @discardableResult
  func perform(_ command: GlueCommand) -> Bool {
    switch command {
    case .flipLayout: flipLayout()
    case .cycleArrangement: cycleArrangement()
    case .cycleSize: cycleSize()
    case .next: focusStep(1)
    case .previous: focusStep(-1)
    case .seam(let d): moveSeam(d)
    case .offset(let d): offset(d)
    case .move(let dx, let dy): nudgeFree(dx: dx, dy: dy)
    case .moveEarlier: if let i = focused { move(i, by: -1) }
    case .moveLater: if let i = focused { move(i, by: 1) }
    case .join(let d): setJoin(edit.join_px + d)
    case .fade(let d): setFade(edit.fade_px + d)
    case .joinFade(let d):
      guard let k = focusedJoin else { return true }
      setJoinFade(k, fade(atJoin: k) + d)
    case .before(let on): before = on ?? !before
    case .turn(let d): turn(d)
    case .remove: if let i = focused { removePhoto(i) }
    case .lineUp: lineUp()
    case .glue: glue()
    case .undo: undo()
    case .redo: redo()
    case .zoom(let z): zoom = ZoomCanvas<EmptyView>.step(zoom, z)
    case .escape:
      if before {
        before = false
      } else if focused != nil {
        focused = nil
      } else if let onClose {
        onClose()
      } else {
        return false
      }
    }
    return true
  }

  // MARK: - Opening

  /// Adds photos (up to 10). `origins` names where each came from.
  func add(_ urls: [URL], origins: [URL]? = nil, keywords: [[String]] = [], removeAfter: Bool = false, stageCopy: Bool = true) {
    guard !busy, !urls.isEmpty else { return }
    busy = true
    error = nil
    phase = "Opening \(urls.count == 1 ? "photo" : "\(urls.count) photos")…"
    let room = Self.maxPhotos - images.count
    task = Task {
      defer { busy = false }
      do {
        let workspace = try self.workspace ?? MediaWorkspace()
        self.workspace = workspace
        let chosen = Array(urls.prefix(room))
        let opened = try await Task.detached(priority: .userInitiated) { () throws -> [ToolImage] in
          defer { if removeAfter { chosen.forEach(ToolPickedFile.remove) } }
          return try chosen.enumerated().map { i, url in
            let readable = stageCopy ? try workspace.stage(url) : url
            return try ToolImaging.inspect(readable, origin: origins?[i] ?? url, extraKeywords: keywords.indices.contains(i) ? keywords[i] : [])
          }
        }.value
        let old = edit
        images.append(contentsOf: opened)
        edit.sources.append(contentsOf: opened.map { .init(ref: $0.name, width: $0.width, height: $0.height) })
        if edit.free.count == edit.sources.count - opened.count, edit.arrangement == "free" {
          let right = (plan?.width).map(Double.init) ?? 0
          for (n, image) in opened.enumerated() {
            edit.free.append(.init(x: right + Double(n) * 40, y: 0, w: Double(image.width)))
          }
        }
        if old.sources.isEmpty { history.clear() } else { history.record(old, now: edit) }
        result = nil
        if urls.count > room { notice = "Glue takes up to \(Self.maxPhotos) photos; the rest were left out." }
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }

  func addPhotos(_ items: [PhotosPickerItem]) {
    guard !busy, !items.isEmpty else { return }
    busy = true
    error = nil
    phase = "Downloading selected photos…"
    task = Task {
      do {
        var urls: [URL] = []
        for item in items {
          guard let picked = try await item.loadTransferable(type: ToolPickedFile.self) else {
            throw MediaToolError.message("Photos could not provide a photo. Try exporting it to Files first.")
          }
          urls.append(picked.url)
        }
        busy = false
        add(urls, removeAfter: true)
      } catch {
        busy = false
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }

  // MARK: - Making the file

  func glue() {
    guard !busy, let workspace, images.count >= 2, plan != nil else { return }
    let snapshot = edit
    let images = images
    let format = format
    let beside = beside
    let first = images[0]
    let name = mediaGlueName(stem: first.stem, ext: format.ext, existing: beside.map(ToolImaging.names(in:)) ?? [])
    let job = MediaRenderJob()
    self.job = job
    busy = true
    progress = 0
    phase = "Gluing…"
    error = nil
    result = nil
    task = Task {
      defer {
        busy = false
        self.job = nil
      }
      do {
        let worker = Task.detached(priority: .userInitiated) { () throws -> URL in
          let made = try GlueBridge.export(
            config: snapshot, images: images, format: format, name: name, workspace: workspace, job: job
          ) { value in Task { @MainActor [weak self] in self?.progress = value } }
          guard let beside else { return made }
          return try ToolImaging.publish(made, as: name, in: beside)
        }
        let url = try await withTaskCancellationHandler { try await worker.value } onCancel: {
          job.cancel()
          worker.cancel()
        }
        result = url
        let text = "Glued · \(url.lastPathComponent)"
        notice = text
        onMade?([url], text)
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }

  func cancel() {
    job?.cancel()
    task?.cancel()
  }
}
