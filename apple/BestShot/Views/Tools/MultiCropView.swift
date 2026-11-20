import PhotosUI
import SwiftUI
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

/// Multi Crop: several new photos out of one image. Find places boxes; drag
/// to draw, move, resize, rotate or set four corners; Make writes one new
/// photo per box. The source is never written.
struct MultiCropView: View {
    /// A photo to open straight away (a project, the viewer, Folders).
    var initial: URL?
    /// Folders: files go beside the source, which is read in place.
    var beside: URL?
    var keywords: [String] = []
    var onMade: (([URL], String) -> Void)?
    var onClose: (() -> Void)?

    @Environment(\.scenePhase) private var scenePhase
    @State private var session = MultiCropSession()
    @State private var photo: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var choosingFile = false
    @State private var choosingProject = false
    @State private var panning = false
    @State private var drag: DragMode = .none
    /// The box as it was when a move began, so snapping never drifts.
    @State private var dragOriginal: CropBoxModel?
    /// Bumped when a drag snaps onto something, for a light haptic on touch.
    @State private var snapTick = 0
    @State private var snapped = false
    @FocusState private var keys: Bool

    enum DragMode: Equatable {
        case none
        case draw(CGPoint)
        case move(String, CGPoint)
        case corner(String, Int)
        case rotate(String)
    }

    // Built in stages so each part type-checks on its own: one long
    // modifier chain was too slow for CI's compiler.
    var body: some View {
        withLifecycle(withPickers(screen))
    }

    private var screen: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "Tools", title: "Multi Crop", status: status)
            if let source = session.source {
                editor(source)
            } else {
                empty
            }
        }
        .tableSurfaceList()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if session.source != nil && beside == nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("From Photos") { choosingPhoto = true }
                        Button("From Files") { choosingFile = true }
                        Button("From a project") { choosingProject = true }
                    } label: { Label("Another Photo", systemImage: "photo.badge.plus") }
                    .disabled(session.busy)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { if session.source != nil || session.busy { bottomBar } }
    }

    private func withPickers<V: View>(_ base: V) -> some View {
        base
            .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
                switch result {
                case .success(let url): session.open(url)
                case .failure(let error): session.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $choosingProject) {
                ToolProjectPicker(kind: .image) { urls in if let url = urls.first { session.open(url) } }
            }
            .onChange(of: photo) { _, item in
                if let item {
                    session.openPhoto(item)
                    photo = nil
                }
            }
    }

    private func withLifecycle<V: View>(_ base: V) -> some View {
        base
            .onChange(of: session.source?.id) { session.zoom = 1 }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && session.busy {
                    session.cancel()
                    session.error = "Stopped when BestShot went into the background. Keep it open while making photos."
                }
            }
            .task {
                session.beside = beside
                session.onMade = onMade
                session.onClose = onClose
                if let initial, session.source == nil {
                    session.open(initial, extraKeywords: keywords, stageCopy: beside == nil)
                }
            }
            .onAppear { ToolHolder.shared.show(.multiCrop(session)) }
            .onDisappear {
                session.cancel()
                ToolHolder.shared.hide(session)
            }
    }

    private var status: String? {
        guard let source = session.source else { return nil }
        let n = session.edit.boxes.count
        return "\(source.name) · \(n) photo\(n == 1 ? "" : "s") · \(session.format.title)"
    }

    // MARK: - Nothing open

    private var empty: some View {
        EmptyState(title: "Choose an Image",
                   message: "Pull several photos out of one image: a scanned page of prints, a contact sheet, a screenshot. The original stays as it is.") {
            if session.busy {
                ProgressView().controlSize(.small)
            } else if beside == nil {
                ToolSourceButtons(files: { choosingFile = true }, project: { choosingProject = true }) {
                    Button("Choose from Photos") { choosingPhoto = true }.buttonStyle(.pill)
                }
            }
            if let error = session.error { ToolError(text: error) }
        }
    }

    // MARK: - Editing

    private func editor(_ source: ToolImage) -> some View {
        VStack(spacing: 0) {
            ZoomCanvas(size: CGSize(width: source.width, height: source.height), zoom: $session.zoom, panning: panning) { scale in
                canvas(source, scale: scale)
            }
            .layoutPriority(1)
            .sensoryFeedback(.alignment, trigger: snapTick)
            if session.showStrip && !session.edit.boxes.isEmpty {
                MultiCropStrip(session: session)
                    .overlay(alignment: .top) { HairlineRule() }
            }
            toolRow
            VStack(alignment: .leading, spacing: 2) {
                if session.renumbering != nil {
                    FormNote("Press the boxes in their new order. Esc ends; any not pressed keep their order after.")
                } else if let validation = session.validation {
                    ToolError(text: validation)
                } else if session.edit.boxes.isEmpty {
                    FormNote("Drag to draw a box, or press F to find photos.")
                } else if let notice = session.notice, session.results.isEmpty {
                    FormNote(notice)
                } else {
                    FormNote(namesLine(source))
                }
                if let error = session.error { ToolError(text: error) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 6)
        }
        .focusable(interactions: .edit)
        .focused($keys)
        .focusEffectDisabled()
        .onAppear { keys = true }
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .disabled(session.busy)
    }

    private func namesLine(_ source: ToolImage) -> String {
        let n = session.included.count
        let where_ = beside == nil ? "" : "beside the source · "
        return n == 1 ? "\(where_)\(source.stem)-1.\(session.format.ext)" : "\(where_)\(source.stem)-1 … -\(n).\(session.format.ext)"
    }

    private var toolRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                boxButtons
                viewButtons
            }
            .padding(.horizontal, Theme.Space.screen - 12)
        }
        .overlay(alignment: .top) { HairlineRule() }
    }

    // The bar in two groups, so each type-checks on its own.
    @ViewBuilder
    private var boxButtons: some View {
                ToolIcon(label: "Find photos", symbol: "sparkle.magnifyingglass", key: "F") { session.find() }
                ToolIcon(label: "New box", symbol: "plus.square.dashed", key: "N") { session.add() }
                ToolIcon(label: "Duplicate box", symbol: "plus.square.on.square", key: "⌘D") { session.duplicate() }
                    .disabled(session.focused == nil)
                ToolIcon(label: "Remove box", symbol: "minus.square", key: "⌫") { session.remove() }
                    .disabled(session.focused == nil)
                Divider().frame(height: 24).padding(.horizontal, 4)
                ToolIcon(label: "Turn left", symbol: "rotate.left", key: "⇧R") { session.turn(-90) }
                ToolIcon(label: "Turn right", symbol: "rotate.right", key: "R") { session.turn(90) }
                ToolIcon(label: "Four corners", symbol: "skew", key: "P", active: session.box(session.focused).map { !$0.rect } ?? false) { session.toggleCorners() }
                    .disabled(session.focused == nil)
                ToolIcon(label: "Use last crop", symbol: "clock.arrow.circlepath", key: "L") { session.useLast() }
                    .disabled(!session.canUseLast)
                ToolIcon(label: session.focused.map { session.isOff($0) } == true ? "Make this one" : "Leave this one out",
                         symbol: "eye.slash", key: "Space", active: session.focused.map { session.isOff($0) } ?? false) { session.toggleOff() }
                    .disabled(session.focused == nil)
                ToolIcon(label: "Renumber", symbol: "list.number", key: "#", active: session.renumbering != nil) {
                    if session.renumbering == nil { session.startRenumber() } else { session.endRenumber() }
                }
                .disabled(session.included.count < 2)
                ToolIcon(label: session.showStrip ? "Hide what will be saved" : "Show what will be saved", symbol: "rectangle.split.3x1",
                         key: "V", active: session.showStrip) { session.showStrip.toggle() }
                Stepper(value: Binding(get: { session.edit.trim }, set: { v in session.change { $0.trim = max(0, min(30, v)) } }), in: 0...30) {
                    Text("Trim \(session.edit.trim) px").font(.small).monospacedDigit()
                }
                .fixedSize()
                .padding(.horizontal, 8)
                .help("Shave the inside edge of every box")
    }

    @ViewBuilder
    private var viewButtons: some View {
                Divider().frame(height: 24).padding(.horizontal, 4)
                ToolIcon(label: "Zoom out", symbol: "minus.magnifyingglass", key: "⌘−") { session.zoom = ZoomCanvas<EmptyView>.step(session.zoom, .zoomOut) }
                ToolIcon(label: "Zoom to fit", symbol: "arrow.down.right.and.arrow.up.left", key: "⌘0") { session.zoom = 1 }
                ToolIcon(label: "Zoom in", symbol: "plus.magnifyingglass", key: "⌘+") { session.zoom = ZoomCanvas<EmptyView>.step(session.zoom, .zoomIn) }
                #if os(iOS)
                ToolIcon(label: panning ? "Draw boxes" : "Pan", symbol: panning ? "pencil.and.outline" : "hand.raised", active: panning) { panning.toggle() }
                #endif
                ToolOptionsMenu(format: $session.format)
    }

    private var bottomBar: some View {
        BottomBar {
            if session.busy {
                HStack {
                    Text(session.phase).font(.note).foregroundStyle(Theme.table.muted)
                    Spacer()
                    Button("Cancel", action: session.cancel).buttonStyle(.text)
                }
                if session.phase.hasPrefix("Making") { ProgressLine(value: session.progress) }
            } else if !session.results.isEmpty {
                ToolMadeBar(urls: session.results, notice: session.notice, beside: beside != nil) { session.takeBack() }
            } else {
                HStack(spacing: 0) {
                    ToolIcon(label: "Undo", symbol: "arrow.uturn.backward", key: "⌘Z") { session.undo() }
                        .disabled(!session.history.canUndo)
                    ToolIcon(label: "Redo", symbol: "arrow.uturn.forward", key: "⇧⌘Z") { session.redo() }
                        .disabled(!session.history.canRedo)
                    if let onClose {
                        ToolIcon(label: "Close", symbol: "xmark", key: "Esc", action: onClose)
                    }
                    Spacer()
                    let n = session.included.count
                    Button { session.make() } label: { Text(n == 0 ? "Make" : "Make \(n)") }
                        .buttonStyle(.pill)
                        .disabled(session.plan == nil)
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }

    // MARK: - Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let command = MultiCropKeymap.command(key: press.key, characters: press.characters, modifiers: press.modifiers) else {
            return .ignored
        }
        return session.perform(command) ? .handled : .ignored
    }

    // MARK: - Canvas

    private func canvas(_ source: ToolImage, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: source.preview, scale: 1)
                .resizable()
                .interpolation(.high)
            MultiCropBoxesLayer(session: session, scale: scale, drawing: drawingRect)
            if case .corner(let id, let i) = drag, let box = session.box(id) {
                CropLoupe(image: source.preview, imageSize: CGSize(width: source.width, height: source.height),
                          box: box, corner: i, scale: scale)
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(source, scale: scale))
        .simultaneousGesture(SpatialTapGesture().onEnded { tap in
            let p = CGPoint(x: tap.location.x / scale, y: tap.location.y / scale)
            if session.renumbering != nil {
                if let id = hit(p)?.id { session.pick(id) }
            } else {
                session.focused = hit(p)?.id
            }
            keys = true
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The image, with \(session.edit.boxes.count) boxes")
        .accessibilityChildren { boxAccessibility(scale: scale) }
    }

    private var drawingRect: CGRect? {
        guard case .draw(let start) = drag, let current = drawCurrent else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    @State private var drawCurrent: CGPoint?

    private func boxAccessibility(scale: CGFloat) -> some View {
        let numbers: [String: Int] = session.numbers
        return ForEach(session.edit.boxes) { (box: CropBoxModel) in
            boxElement(box, number: numbers[box.id] ?? 0, scale: scale)
        }
    }

    /// "Box 2 of 5, rotated 4 degrees, turned 90".
    private func boxLabel(_ box: CropBoxModel, number: Int) -> String {
        var text: String = "Box \(number) of \(session.edit.boxes.count)"
        if box.rect && box.angle != 0 { text += ", rotated \(box.angle) degrees" }
        if box.turn != 0 { text += ", turned \(box.turn)" }
        return text
    }

    private func boxElement(_ box: CropBoxModel, number: Int, scale: CGFloat) -> some View {
        let bounds: CGRect = box.bounds
        return Rectangle()
            .frame(width: bounds.width * scale, height: bounds.height * scale)
            .position(x: bounds.midX * scale, y: bounds.midY * scale)
            .accessibilityLabel(boxLabel(box, number: number))
            .accessibilityAddTraits(box.id == session.focused ? .isSelected : [])
            .accessibilityAction { session.focused = box.id }
            .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in
                session.focused = box.id
                session.nudge(dx: direction == .increment ? 10 : -10, dy: 0)
            }
    }

    private func inside(_ p: CGPoint, _ q: [CGPoint]) -> Bool {
        var sign: CGFloat = 0
        for i in 0..<4 {
            let (a, b) = (q[i], q[(i + 1) % 4])
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross != 0 {
                if sign == 0 { sign = cross > 0 ? 1 : -1 } else if (cross > 0) != (sign > 0) { return false }
            }
        }
        return true
    }

    private func hit(_ p: CGPoint) -> CropBoxModel? {
        if let f = session.box(session.focused), inside(p, f.quad) { return f }
        return session.edit.boxes.reversed().first { inside(p, $0.quad) }
    }

    private func convex(_ q: [CGPoint]) -> Bool {
        var sign: CGFloat = 0
        for i in 0..<4 {
            let (a, b, c) = (q[i], q[(i + 1) % 4], q[(i + 2) % 4])
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-6 { return false }
            if sign == 0 { sign = cross } else if (cross > 0) != (sign > 0) { return false }
        }
        return true
    }

    private func dragGesture(_ source: ToolImage, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let p = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                guard session.renumbering == nil else { return }
                if drag == .none {
                    drag = begin(at: start, scale: scale)
                    dragOriginal = { if case .move(let id, _) = drag { return session.box(id) } else { return nil } }()
                }
                apply(p, source: source, scale: scale)
            }
            .onEnded { _ in
                if case .draw(let start) = drag, let end = drawCurrent {
                    let r = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                        .intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
                    if r.width >= 16, r.height >= 16 {
                        let id = session.newID()
                        session.change { $0.boxes.append(.rect(id: id, r.integral)) }
                        session.focused = id
                    }
                } else if drag != .none {
                    session.endDrag()
                }
                drag = .none
                drawCurrent = nil
                dragOriginal = nil
                snapped = false
                keys = true
            }
    }

    private func begin(at p: CGPoint, scale: CGFloat) -> DragMode {
        let reach = 22 / scale
        if let f = session.box(session.focused) {
            for (i, c) in f.quad.enumerated() where hypot(c.x - p.x, c.y - p.y) <= reach {
                session.beginDrag()
                return .corner(f.id, i)
            }
            if f.rect {
                let r = MultiCropBoxesLayer.rotateHandle(f, scale: scale)
                if hypot(r.x / scale - p.x, r.y / scale - p.y) <= reach {
                    session.beginDrag()
                    return .rotate(f.id)
                }
            }
        }
        if let b = hit(p) {
            session.focused = b.id
            session.beginDrag()
            return .move(b.id, p)
        }
        return .draw(p)
    }

    /// Snapping is on unless ⌥ is held (Mac); on touch it always is (spec 2.2).
    private var snapping: Bool {
        #if os(macOS)
        return !NSEvent.modifierFlags.contains(.option)
        #else
        return true
        #endif
    }

    /// Marks a snap taking hold, once per hold, for the haptic.
    private func noteSnap(_ now: Bool) {
        if now && !snapped { snapTick += 1 }
        snapped = now
    }

    private func apply(_ raw: CGPoint, source: ToolImage, scale: CGFloat) {
        var p = CGPoint(x: min(max(raw.x, 0), CGFloat(source.width)), y: min(max(raw.y, 0), CGFloat(source.height)))
        let reach = 6 / scale
        let lines: CropSnap.Lines? = {
            guard snapping else { return nil }
            switch drag {
            case .move(let id, _), .corner(let id, _): return CropSnap.lines(boxes: session.edit.boxes, except: id, width: source.width, height: source.height)
            case .draw: return CropSnap.lines(boxes: session.edit.boxes, except: nil, width: source.width, height: source.height)
            default: return nil
            }
        }()
        switch drag {
        case .none: break
        case .draw:
            if let lines {
                let s = CGPoint(x: CropSnap.value(p.x, to: lines.xs, reach: reach), y: CropSnap.value(p.y, to: lines.ys, reach: reach))
                noteSnap(s != p)
                p = s
            }
            drawCurrent = p
        case .move(let id, let start):
            guard let original = dragOriginal else { break }
            var b = original
            b.move(by: CGVector(dx: raw.x - start.x, dy: raw.y - start.y))
            // Keep the centre on the image.
            let c = b.centre
            let fix = CGVector(dx: min(max(c.x, 0), CGFloat(source.width)) - c.x, dy: min(max(c.y, 0), CGFloat(source.height)) - c.y)
            if fix.dx != 0 || fix.dy != 0 { b.move(by: fix) }
            if let lines {
                let shift = CropSnap.shift(b.bounds, to: lines, reach: reach)
                noteSnap(shift != .zero)
                if shift != .zero { b.move(by: shift) }
            }
            session.update(id) { $0 = b }
        case .corner(let id, let i):
            if let lines {
                let s = CGPoint(x: CropSnap.value(p.x, to: lines.xs, reach: reach), y: CropSnap.value(p.y, to: lines.ys, reach: reach))
                noteSnap(s != p)
                p = s
            }
            session.update(id) { b in
                if b.rect {
                    let q = b.quad
                    let opposite = q[(i + 2) % 4]
                    let a = CGFloat(b.angle) * .pi / 180
                    let (dx, dy) = (p.x - opposite.x, p.y - opposite.y)
                    let lx = dx * cos(a) + dy * sin(a)
                    let ly = -dx * sin(a) + dy * cos(a)
                    let sx: CGFloat = (i == 1 || i == 2) ? 1 : -1
                    let sy: CGFloat = (i >= 2) ? 1 : -1
                    var w = max(16, lx * sx), h = max(16, ly * sy)
                    // Straight boxes take the other boxes' sizes too, so a contact sheet's match.
                    if let lines, b.angle == 0 {
                        let (sw, sh) = (CropSnap.value(w, to: lines.widths, reach: reach), CropSnap.value(h, to: lines.heights, reach: reach))
                        if sw != w || sh != h { noteSnap(true) }
                        (w, h) = (sw, sh)
                    }
                    let (hx, hy) = (sx * w / 2, sy * h / 2)
                    b.w = w.rounded()
                    b.h = h.rounded()
                    b.cx = opposite.x + hx * cos(a) - hy * sin(a)
                    b.cy = opposite.y + hx * sin(a) + hy * cos(a)
                } else {
                    var q = b.corners
                    q[i] = p
                    if convex(q) { b.corners = q }
                }
            }
        case .rotate(let id):
            session.update(id) { b in
                var degrees = atan2(raw.y - b.cy, raw.x - b.cx) * 180 / .pi + 90
                if degrees > 180 { degrees -= 360 }
                if abs(degrees) < 1 { degrees = 0 }
                b.angle = (degrees * 10).rounded() / 10
            }
        }
    }
}
