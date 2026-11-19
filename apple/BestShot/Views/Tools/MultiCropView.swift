import PhotosUI
import SwiftUI
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
    @State private var zoom: CGFloat = 1
    @State private var panning = false
    @State private var drag: DragMode = .none
    @FocusState private var keys: Bool

    enum DragMode: Equatable {
        case none
        case draw(CGPoint)
        case move(String, CGPoint)
        case corner(String, Int)
        case rotate(String)
    }

    var body: some View {
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
        .onChange(of: session.source?.id) { zoom = 1 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && session.busy {
                session.cancel()
                session.error = "Stopped when BestShot went into the background. Keep it open while making photos."
            }
        }
        .task {
            session.beside = beside
            session.onMade = onMade
            if let initial, session.source == nil {
                session.open(initial, extraKeywords: keywords, stageCopy: beside == nil)
            }
        }
        .onDisappear { session.cancel() }
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
            ZoomCanvas(size: CGSize(width: source.width, height: source.height), zoom: $zoom, panning: panning) { scale in
                canvas(source, scale: scale)
            }
            .layoutPriority(1)
            toolRow
            VStack(alignment: .leading, spacing: 2) {
                if let validation = session.validation {
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
        let n = session.edit.boxes.count
        let where_ = beside == nil ? "" : "beside the source · "
        return n == 1 ? "\(where_)\(source.stem)-1.\(session.format.ext)" : "\(where_)\(source.stem)-1 … -\(n).\(session.format.ext)"
    }

    private var toolRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
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
                Stepper(value: Binding(get: { session.edit.trim }, set: { v in session.change { $0.trim = max(0, min(30, v)) } }), in: 0...30) {
                    Text("Trim \(session.edit.trim) px").font(.small).monospacedDigit()
                }
                .fixedSize()
                .padding(.horizontal, 8)
                .help("Shave the inside edge of every box")
                Divider().frame(height: 24).padding(.horizontal, 4)
                ToolIcon(label: "Zoom out", symbol: "minus.magnifyingglass", key: "⌘−") { zoom = ZoomCanvas<EmptyView>.step(zoom, .zoomOut) }
                ToolIcon(label: "Zoom to fit", symbol: "arrow.down.right.and.arrow.up.left", key: "⌘0") { zoom = 1 }
                ToolIcon(label: "Zoom in", symbol: "plus.magnifyingglass", key: "⌘+") { zoom = ZoomCanvas<EmptyView>.step(zoom, .zoomIn) }
                #if os(iOS)
                ToolIcon(label: panning ? "Draw boxes" : "Pan", symbol: panning ? "pencil.and.outline" : "hand.raised", active: panning) { panning.toggle() }
                #endif
                ToolOptionsMenu(format: $session.format)
            }
            .padding(.horizontal, Theme.Space.screen - 12)
        }
        .overlay(alignment: .top) { HairlineRule() }
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
                    let n = session.edit.boxes.count
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
        switch command {
        case .find: session.find()
        case .add: session.add()
        case .duplicate: session.duplicate()
        case .next: session.focusStep(1)
        case .previous: session.focusStep(-1)
        case .move(let dx, let dy): session.nudge(dx: dx, dy: dy)
        case .resize(let dw, let dh): session.resize(dw: dw, dh: dh)
        case .rotate(let d): session.rotate(d)
        case .turn(let d): session.turn(d)
        case .toggleCorners: session.toggleCorners()
        case .remove: session.remove()
        case .useLast: session.useLast()
        case .make: session.make()
        case .undo: session.undo()
        case .redo: session.redo()
        case .zoom(let z): zoom = ZoomCanvas<EmptyView>.step(zoom, z)
        case .escape:
            if session.focused != nil { session.focused = nil } else if let onClose { onClose() }
        }
        return .handled
    }

    // MARK: - Canvas

    private func canvas(_ source: ToolImage, scale: CGFloat) -> some View {
        let numbers = session.numbers
        return ZStack(alignment: .topLeading) {
            Image(decorative: source.preview, scale: 1)
                .resizable()
                .interpolation(.high)
            Canvas { context, _ in
                for box in session.edit.boxes {
                    let focused = box.id == session.focused
                    let q = box.quad.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
                    var path = Path()
                    path.addLines(q)
                    path.closeSubpath()
                    context.fill(path, with: .color(Theme.table.accent.opacity(focused ? 0.12 : 0.06)))
                    context.stroke(path, with: .color(Theme.table.accent), lineWidth: focused ? 2.5 : 1.5)
                    // Which way is up for the output: a tick on its top edge.
                    let topEdge = outputTop(box, q)
                    var tick = Path()
                    tick.move(to: topEdge.0)
                    tick.addLine(to: topEdge.1)
                    context.stroke(tick, with: .color(Theme.table.accent), lineWidth: 5)
                    let n = numbers[box.id].map(String.init) ?? "·"
                    let chip = Text(n).font(.mono(13, medium: true)).foregroundColor(Theme.table.accentInk)
                    let at = CGPoint(x: q[0].x + 14, y: q[0].y + 14)
                    context.fill(Path(ellipseIn: CGRect(x: at.x - 12, y: at.y - 12, width: 24, height: 24)), with: .color(Theme.table.accent))
                    context.draw(chip, at: at)
                    if focused {
                        for p in q { context.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(Theme.table.accent)) }
                        if box.rect {
                            let r = rotateHandle(box, scale: scale)
                            context.stroke(Path { $0.move(to: midTop(q)); $0.addLine(to: r) }, with: .color(Theme.table.accent), lineWidth: 1)
                            context.fill(Path(ellipseIn: CGRect(x: r.x - 8, y: r.y - 8, width: 16, height: 16)), with: .color(Theme.table.accent))
                        }
                    }
                }
                if case .draw(let start) = drag, let current = drawCurrent {
                    let r = CGRect(x: min(start.x, current.x) * scale, y: min(start.y, current.y) * scale,
                                   width: abs(current.x - start.x) * scale, height: abs(current.y - start.y) * scale)
                    context.stroke(Path(r), with: .color(Theme.table.accent), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(source, scale: scale))
        .simultaneousGesture(SpatialTapGesture().onEnded { tap in
            let p = CGPoint(x: tap.location.x / scale, y: tap.location.y / scale)
            session.focused = hit(p)?.id
            keys = true
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The image, with \(session.edit.boxes.count) boxes")
        .accessibilityChildren { boxAccessibility(scale: scale) }
    }

    @State private var drawCurrent: CGPoint?

    private func boxAccessibility(scale: CGFloat) -> some View {
        let numbers = session.numbers
        return ForEach(session.edit.boxes) { box in
            Rectangle()
                .frame(width: box.bounds.width * scale, height: box.bounds.height * scale)
                .position(x: box.bounds.midX * scale, y: box.bounds.midY * scale)
                .accessibilityLabel("Box \(numbers[box.id] ?? 0) of \(session.edit.boxes.count)\(box.rect && box.angle != 0 ? ", rotated \(box.angle) degrees" : "")\(box.turn != 0 ? ", turned \(box.turn)" : "")")
                .accessibilityAddTraits(box.id == session.focused ? .isSelected : [])
                .accessibilityAction { session.focused = box.id }
                .accessibilityAdjustableAction { direction in
                    session.focused = box.id
                    session.nudge(dx: direction == .increment ? 10 : -10, dy: 0)
                }
        }
    }

    private func midTop(_ q: [CGPoint]) -> CGPoint { CGPoint(x: (q[0].x + q[1].x) / 2, y: (q[0].y + q[1].y) / 2) }

    /// The handle above the top edge, in canvas points.
    private func rotateHandle(_ box: CropBoxModel, scale: CGFloat) -> CGPoint {
        let q = box.quad.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        let m = midTop(q)
        let a = box.angle * .pi / 180
        return CGPoint(x: m.x + 30 * sin(a), y: m.y - 30 * cos(a))
    }

    /// The edge that will be the top of the output, after its turn.
    private func outputTop(_ box: CropBoxModel, _ q: [CGPoint]) -> (CGPoint, CGPoint) {
        let i = [0: 0, 90: 3, 180: 2, 270: 1][box.turn] ?? 0
        let (a, b) = (q[i], q[(i + 1) % 4])
        let inset: CGFloat = 0.3
        return (CGPoint(x: a.x + (b.x - a.x) * inset, y: a.y + (b.y - a.y) * inset),
                CGPoint(x: a.x + (b.x - a.x) * (1 - inset), y: a.y + (b.y - a.y) * (1 - inset)))
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
                if drag == .none { drag = begin(at: start, scale: scale) }
                apply(p, source: source)
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
                let r = rotateHandle(f, scale: scale)
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

    private func apply(_ raw: CGPoint, source: ToolImage) {
        let p = CGPoint(x: min(max(raw.x, 0), CGFloat(source.width)), y: min(max(raw.y, 0), CGFloat(source.height)))
        switch drag {
        case .none: break
        case .draw: drawCurrent = p
        case .move(let id, let last):
            session.update(id) { b in
                b.move(by: CGVector(dx: raw.x - last.x, dy: raw.y - last.y))
                // Keep the centre on the image.
                let c = b.centre
                let fix = CGVector(dx: min(max(c.x, 0), CGFloat(source.width)) - c.x, dy: min(max(c.y, 0), CGFloat(source.height)) - c.y)
                if fix.dx != 0 || fix.dy != 0 { b.move(by: fix) }
            }
            drag = .move(id, raw)
        case .corner(let id, let i):
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
                    let w = max(16, lx * sx), h = max(16, ly * sy)
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
