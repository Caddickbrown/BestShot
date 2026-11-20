import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Glue: 2–10 photos into one new photo, in a line, a grid or a free
/// ("jagged") layout on a colour or blurred background, with a gap or an
/// overlap and a straight or feathered fade. The originals are never written.
struct GlueView: View {
    var initial: [URL] = []
    /// Folders: the file goes beside the first photo; photos are read in place.
    var beside: URL?
    var keywords: [[String]] = []
    var onMade: (([URL], String) -> Void)?
    var onClose: (() -> Void)?

    @Environment(\.scenePhase) private var scenePhase
    @State private var session = GlueSession()
    @State private var photos: [PhotosPickerItem] = []
    @State private var choosingPhoto = false
    @State private var choosingFile = false
    @State private var choosingProject = false
    @State private var panning = false
    @State private var dragging: (index: Int, last: CGPoint, resize: Bool)?
    /// A seam being dragged: its join and the last point along it.
    @State private var seamDrag: (join: Int, last: CGFloat)?
    @FocusState private var keys: Bool

    // Built in stages so each part type-checks on its own: one long
    // modifier chain was too slow for CI's compiler.
    var body: some View {
        withLifecycle(withPickers(screen))
    }

    private var screen: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "Tools", title: "Glue", status: status)
            if session.images.isEmpty {
                empty
            } else {
                editor
            }
        }
        .tableSurfaceList()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) { if !session.images.isEmpty || session.busy { bottomBar } }
    }

    private func withPickers<V: View>(_ base: V) -> some View {
        base
            .photosPicker(isPresented: $choosingPhoto, selection: $photos, maxSelectionCount: GlueSession.maxPhotos - session.images.count,
                          selectionBehavior: .ordered, matching: .images)
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): session.add(urls)
                case .failure(let error): session.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $choosingProject) {
                ToolProjectPicker(kind: .image, multiple: true) { urls in session.add(urls) }
            }
            .onChange(of: photos) { _, items in
                if !items.isEmpty {
                    session.addPhotos(items)
                    photos = []
                }
            }
    }

    private func withLifecycle<V: View>(_ base: V) -> some View {
        base
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && session.busy {
                    session.cancel()
                    session.error = "Stopped when BestShot went into the background. Keep it open while gluing."
                }
            }
            .task {
                session.beside = beside
                session.onMade = onMade
                session.onClose = onClose
                if !initial.isEmpty, session.images.isEmpty {
                    session.add(initial, keywords: keywords, stageCopy: beside == nil)
                }
            }
            .onAppear { ToolHolder.shared.show(.glue(session)) }
            .onDisappear {
                session.cancel()
                ToolHolder.shared.hide(session)
            }
    }

    private var status: String? {
        guard let plan = session.plan else { return session.images.isEmpty ? nil : "\(session.images.count) photo\(session.images.count == 1 ? "" : "s")" }
        return "\(session.images.count) photos · \(plan.width.formatted()) × \(plan.height.formatted()) · \(session.format.title)"
    }

    // MARK: - Nothing open

    private var empty: some View {
        EmptyState(title: "Choose Photos",
                   message: "Glue two to ten photos together: side by side, stacked, in a grid, or placed freely. The originals stay as they are.") {
            if session.busy {
                ProgressView().controlSize(.small)
            } else {
                addButtons(pill: true)
            }
            if let error = session.error { ToolError(text: error) }
        }
    }

    @ViewBuilder
    private func addButtons(pill: Bool) -> some View {
        #if os(iOS)
        ToolSourceButtons(files: { choosingFile = true }, project: { choosingProject = true }) {
            Button("Choose from Photos") { choosingPhoto = true }.buttonStyle(.pill)
        }
        #else
        Button("Choose Photos…") { choosingFile = true }.buttonStyle(.pill)
        #endif
    }

    // MARK: - Editing

    private var editor: some View {
        VStack(spacing: 0) {
            if let plan = session.shownPlan {
                ZoomCanvas(size: CGSize(width: plan.width, height: plan.height), zoom: $session.zoom, panning: panning) { scale in
                    canvas(plan, scale: scale)
                }
                .layoutPriority(1)
            } else {
                strip.frame(maxHeight: .infinity).layoutPriority(1)
            }
            controls
        }
        .focusable(interactions: .edit)
        .focused($keys)
        .focusEffectDisabled()
        .onAppear { keys = true }
        .onKeyPress(phases: [.down, .repeat, .up]) { press in handle(press) }
        .disabled(session.busy)
    }

    /// Before there are two photos (or when the layout can't be made): the photos in a row.
    private var strip: some View {
        HStack(spacing: 8) {
            ForEach(session.images.indices, id: \.self) { i in
                if let image = session.preview(i) {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .overlay { Rectangle().stroke(session.focused == i ? Theme.table.accent : .clear, lineWidth: 3) }
                        .onTapGesture { session.focused = i }
                }
            }
        }
        .padding(Theme.Space.screen)
        .frame(maxWidth: .infinity)
        .background(Theme.table.tile)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    layoutButtons
                    Divider().frame(height: 24).padding(.horizontal, 4)
                    photoButtons
                    Divider().frame(height: 24).padding(.horizontal, 4)
                    viewButtons
                }
                .padding(.horizontal, Theme.Space.screen - 12)
            }
            .overlay(alignment: .top) { HairlineRule() }
            sliders
        }
    }

    // The bar in three groups, so each type-checks on its own.
    @ViewBuilder
    private var layoutButtons: some View {
            ToolIcon(label: session.vertical ? "Side by side" : "Stacked", symbol: session.vertical ? "rectangle.split.2x1" : "rectangle.split.1x2", key: "O") { session.flipLayout() }
            ToolIcon(label: "In a line", symbol: "rectangle.split.3x1", active: session.edit.arrangement == "line") { session.setArrangement("line") }
            ToolIcon(label: "In a grid", symbol: "square.grid.2x2", active: session.edit.arrangement == "grid") { session.setArrangement("grid") }
            ToolIcon(label: "Free (jagged)", symbol: "square.on.square.dashed", active: session.isFree) { session.setArrangement("free") }
            if session.edit.arrangement == "grid" {
                Stepper(value: Binding(get: { columns }, set: { v in session.change { $0.columns = max(1, min(session.images.count, v)) } }), in: 1...max(1, session.images.count)) {
                    Text("\(columns) across").font(.small).monospacedDigit()
                }
                .fixedSize().padding(.horizontal, 8)
            }
            if !session.isFree {
                Menu {
                    Picker("Size", selection: Binding(get: { session.edit.size }, set: { v in session.change { $0.size = v } })) {
                        Text("Match smaller").tag("match_smaller")
                        Text("Match larger").tag("match_larger")
                        Text("Keep pixels").tag("keep")
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }
                .menuIndicator(.hidden).fixedSize().help("Size (M)").accessibilityLabel("Size")
            }
    }

    @ViewBuilder
    private var photoButtons: some View {
            ToolIcon(label: "Turn left", symbol: "rotate.left", key: "⇧R") { session.turn(-90) }.disabled(session.focused == nil)
            ToolIcon(label: "Turn right", symbol: "rotate.right", key: "R") { session.turn(90) }.disabled(session.focused == nil)
            ToolIcon(label: "Earlier", symbol: "arrow.backward.square", key: "⌘←") { if let i = session.focused { session.move(i, by: -1) } }
                .disabled((session.focused ?? 0) == 0)
            ToolIcon(label: "Later", symbol: "arrow.forward.square", key: "⌘→") { if let i = session.focused { session.move(i, by: 1) } }
                .disabled(session.focused.map { $0 >= session.images.count - 1 } ?? true)
            ToolIcon(label: "Take out of the glue", symbol: "minus.square", key: "⌫") { if let i = session.focused { session.removePhoto(i) } }
                .disabled(session.focused == nil)
            addMenu
            ToolIcon(label: "Line up", symbol: "wand.and.rays", key: "L") { session.lineUp() }
                .disabled(session.edit.arrangement != "line" || session.images.count < 2)
            ToolIcon(label: session.before ? "Show after" : "Show before", symbol: "square.split.2x1", key: "\\", active: session.before) {
                session.before.toggle()
            }
            .disabled(session.images.count < 2)
    }

    @ViewBuilder
    private var viewButtons: some View {
            ToolIcon(label: "Zoom out", symbol: "minus.magnifyingglass", key: "⌘−") { session.zoom = ZoomCanvas<EmptyView>.step(session.zoom, .zoomOut) }
            ToolIcon(label: "Zoom to fit", symbol: "arrow.down.right.and.arrow.up.left", key: "⌘0") { session.zoom = 1 }
            ToolIcon(label: "Zoom in", symbol: "plus.magnifyingglass", key: "⌘+") { session.zoom = ZoomCanvas<EmptyView>.step(session.zoom, .zoomIn) }
            #if os(iOS)
            ToolIcon(label: panning ? "Move photos" : "Pan", symbol: panning ? "hand.point.up.left" : "hand.raised", active: panning) { panning.toggle() }
            #endif
            ToolOptionsMenu(format: $session.format)
    }

    private var columns: Int {
        session.edit.columns > 0 ? session.edit.columns : Int(Double(session.images.count).squareRoot().rounded(.up))
    }

    @ViewBuilder
    private var addMenu: some View {
        #if os(iOS)
        Menu {
            Button("From Photos") { choosingPhoto = true }
            Button("From Files") { choosingFile = true }
            Button("From a project") { choosingProject = true }
        } label: { Image(systemName: "plus.square").frame(width: 44, height: 44) }
        .menuIndicator(.hidden).fixedSize().help("Add photos").accessibilityLabel("Add photos")
        .disabled(session.images.count >= GlueSession.maxPhotos)
        #else
        ToolIcon(label: "Add photos", symbol: "plus.square") { choosingFile = true }
            .disabled(session.images.count >= GlueSession.maxPhotos)
        #endif
    }

    // In parts, each with explicit types, so CI's compiler type-checks them in time.
    private var sliders: some View {
        let plan: GluePlan? = session.plan
        let overlap: Double = Double(max(0, -session.edit.join_px))
        return VStack(alignment: .leading, spacing: 4) {
            if !session.isFree { joinRow(plan) }
            fadeRow(overlap)
            if let k = session.focusedJoin, let plan, plan.joins.indices.contains(k), plan.joins[k].join_px < 0 {
                joinFadeRow(k, overlap: Double(-plan.joins[k].join_px))
            }
            borderRow
            notes(plan)
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.vertical, 6)
    }

    private func editing(_ on: Bool) { if on { session.beginDrag() } else { session.endDrag() } }

    private func joinRow(_ plan: GluePlan?) -> some View {
        let maxOverlap: Double = Double(max(plan?.max_overlap_px ?? 0, 0))
        let join: Int = session.edit.join_px
        let value: Binding<Double> = Binding(get: { Double(-session.edit.join_px) }, set: { session.edit.join_px = -Int($0.rounded()) })
        let label: String = join < 0 ? "\(-join) px" : "\(join) px"
        return HStack(spacing: 10) {
            Text("Gap").font(.small).foregroundStyle(Theme.table.muted)
            Slider(value: value, in: -200...max(maxOverlap, 1), onEditingChanged: editing)
            Text("Overlap").font(.small).foregroundStyle(Theme.table.muted)
            Text(label).font(.small).monospacedDigit().frame(width: 64, alignment: .trailing)
        }
        .help("Gap ↔ overlap (- / =)")
    }

    private func fadeRow(_ overlap: Double) -> some View {
        let free: Bool = session.isFree
        let fade: Int = session.edit.fade_px
        let value: Binding<Double> = Binding(get: { Double(session.edit.fade_px) }, set: { session.edit.fade_px = Int($0.rounded()) })
        let upper: Double = max(free ? 400 : overlap, 1)
        let help: String = free ? "Feather the edges of photos over others ([ / ])" : "0 is a straight edge at the seam ([ / ])"
        return HStack(spacing: 10) {
            Text("Fade").font(.small).foregroundStyle(Theme.table.muted)
            Slider(value: value, in: 0...upper, onEditingChanged: editing)
                .disabled(!free && overlap == 0)
            Text(fade == 0 ? "Straight" : "\(fade) px").font(.small).monospacedDigit().frame(width: 64, alignment: .trailing)
        }
        .help(help)
    }

    private var borderRow: some View {
        let value: Binding<Double> = Binding(get: { Double(session.edit.border_px) }, set: { session.edit.border_px = Int($0.rounded()) })
        return HStack(spacing: 10) {
            Text("Border").font(.small).foregroundStyle(Theme.table.muted)
            Slider(value: value, in: 0...200, onEditingChanged: editing)
                .frame(maxWidth: 160)
            Spacer(minLength: 8)
            background
        }
    }

    @ViewBuilder
    private func notes(_ plan: GluePlan?) -> some View {
        if let validation = session.validation {
            ToolError(text: validation)
        } else if let plan, !plan.upscaled.isEmpty {
            let names: String = plan.upscaled.map { session.images[$0].name }.joined(separator: ", ")
            FormNote("Scaled up past 150%: \(names).")
        } else if let notice = session.notice, session.result == nil {
            FormNote(notice)
        }
        if let error = session.error { ToolError(text: error) }
    }

    /// The focused join's own fade (Dan: a fade per join), or the shared one.
    private func joinFadeRow(_ k: Int, overlap: Double) -> some View {
        let own = session.hasOwnFade(k)
        let value = session.fade(atJoin: k)
        return HStack(spacing: 10) {
            Text("This join").font(.small).foregroundStyle(Theme.table.muted)
            Slider(value: Binding(get: { Double(value) }, set: { session.dragJoinFade(k, Int($0.rounded())) }),
                   in: 0...max(overlap, 1), onEditingChanged: editing)
            Text(value == 0 ? "Straight" : "\(value) px").font(.small).monospacedDigit().frame(width: 64, alignment: .trailing)
            ToolIcon(label: "Same fade as the others", symbol: "link", active: !own) { session.setJoinFade(k, nil) }
                .disabled(!own)
        }
        .help("The fade at the join after the focused photo (⌥[ / ⌥])")
    }

    private var background: some View {
        HStack(spacing: 4) {
            swatch("#FFFFFF", "White")
            swatch("#000000", "Black")
            ColorPicker("Background colour", selection: Binding(get: { Color(hexString: session.edit.background.colour) ?? .white }, set: { colour in
                session.change {
                    $0.background.kind = "colour"
                    $0.background.colour = hex(colour)
                }
            }), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 44, height: 44)
            ToolIcon(label: "Blurred fill", symbol: "drop.halffull", active: session.edit.background.kind == "blur") {
                session.change { $0.background.kind = $0.background.kind == "blur" ? "colour" : "blur" }
            }
        }
    }

    private func swatch(_ colour: String, _ name: String) -> some View {
        Button {
            session.change {
                $0.background.kind = "colour"
                $0.background.colour = colour
            }
        } label: {
            Circle().fill(Color(hexString: colour) ?? .white)
                .overlay { Circle().stroke(Theme.table.rule, lineWidth: 1) }
                .overlay {
                    if session.edit.background.kind == "colour" && session.edit.background.colour.uppercased() == colour {
                        Circle().stroke(Theme.table.accent, lineWidth: 2).padding(-3)
                    }
                }
                .frame(width: 22, height: 22)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel("\(name) background")
    }

    private func hex(_ colour: Color) -> String {
        let r = colour.resolve(in: EnvironmentValues())
        func c(_ v: Float) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r.red), c(r.green), c(r.blue))
    }

    private var bottomBar: some View {
        BottomBar {
            if session.busy {
                HStack {
                    Text(session.phase).font(.note).foregroundStyle(Theme.table.muted)
                    Spacer()
                    Button("Cancel", action: session.cancel).buttonStyle(.text)
                }
                if session.phase.hasPrefix("Gluing") { ProgressLine(value: session.progress) }
            } else if let result = session.result {
                ToolMadeBar(urls: [result], notice: session.notice, beside: beside != nil) {
                    ToolImaging.takeBack([result])
                    session.result = nil
                    session.notice = "Taken back."
                }
            } else {
                HStack(spacing: 0) {
                    ToolIcon(label: "Undo", symbol: "arrow.uturn.backward", key: "⌘Z") { session.undo() }.disabled(!session.history.canUndo)
                    ToolIcon(label: "Redo", symbol: "arrow.uturn.forward", key: "⇧⌘Z") { session.redo() }.disabled(!session.history.canRedo)
                    if let onClose { ToolIcon(label: "Close", symbol: "xmark", key: "Esc", action: onClose) }
                    Spacer()
                    Button("Glue") { session.glue() }
                        .buttonStyle(.pill)
                        .disabled(session.plan == nil)
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }

    // MARK: - Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let command = GlueKeymap.command(key: press.key, characters: press.characters, modifiers: press.modifiers,
                                               vertical: session.vertical, free: session.isFree)
        else { return .ignored }
        // `\` is held for before; every other key acts on its press.
        if case .before = command {
            if press.phase == .repeat { return .handled }
            return session.perform(.before(press.phase == .down)) ? .handled : .ignored
        }
        guard press.phase != .up else { return .ignored }
        return session.perform(command) ? .handled : .ignored
    }

    // MARK: - Canvas

    private func canvas(_ plan: GluePlan, scale: CGFloat) -> some View {
        GlueCanvasPicture(session: session, plan: plan, scale: scale, activeSeam: seamDrag?.join)
            .contentShape(Rectangle())
            .gesture(dragGesture(plan, scale: scale))
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                guard !session.before else { return }
                session.focused = hit(plan, CGPoint(x: tap.location.x / scale, y: tap.location.y / scale))
                keys = true
            })
    }

    private func hit(_ plan: GluePlan, _ p: CGPoint) -> Int? {
        plan.items.reversed().first { $0.frame.contains(p) }?.index
    }

    private func dragGesture(_ plan: GluePlan, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let p = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                guard !session.before else { return }
                if let drag = seamDrag {
                    let along = plan.joins[drag.join].axis == "x" ? p.x : p.y
                    session.dragSeam(drag.join, by: along - drag.last)
                    seamDrag = (drag.join, along)
                    return
                }
                if dragging == nil {
                    let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                    // A seam, dragged where it is (a line with an overlap).
                    if let k = GlueSession.seamHit(plan, at: start, reach: 14 / scale, line: session.edit.arrangement == "line") {
                        session.beginDrag()
                        let along = plan.joins[k].axis == "x" ? start.x : start.y
                        session.dragSeam(k, by: (plan.joins[k].axis == "x" ? p.x : p.y) - along)
                        seamDrag = (k, plan.joins[k].axis == "x" ? p.x : p.y)
                        if session.focusedJoin != k { session.focused = plan.items.indices.contains(k) ? plan.items[k].index : session.focused }
                        return
                    }
                    // The free resize handle on the focused photo's corner.
                    if session.isFree, let i = session.focused, let item = plan.items.first(where: { $0.index == i }),
                       hypot(start.x - item.frame.maxX, start.y - item.frame.maxY) <= 22 / scale {
                        dragging = (i, start, true)
                    } else if let i = hit(plan, start) {
                        session.focused = i
                        dragging = (i, start, false)
                    } else {
                        return
                    }
                    session.beginDrag()
                }
                guard let d = dragging else { return }
                let (dx, dy) = (p.x - d.last.x, p.y - d.last.y)
                if session.isFree {
                    if d.resize {
                        session.edit.free[d.index].w = max(16, session.edit.free[d.index].w + dx)
                    } else {
                        session.moveFree(d.index, dx: dx, dy: dy)
                    }
                    dragging = (d.index, p, d.resize)
                } else if session.edit.arrangement == "line" {
                    // Across the join slides the photo (to line up a horizon).
                    let across = Int((session.vertical ? dx : dy).rounded())
                    if across != 0 {
                        if session.edit.offsets_px.count != session.edit.sources.count {
                            session.edit.offsets_px = Array(repeating: 0, count: session.edit.sources.count)
                        }
                        let before = session.edit.offsets_px[d.index]
                        session.edit.offsets_px[d.index] += across
                        if (try? session.edit.plan()) == nil { session.edit.offsets_px[d.index] = before }
                        dragging = (d.index, CGPoint(x: session.vertical ? p.x : d.last.x, y: session.vertical ? d.last.y : p.y), false)
                    }
                }
            }
            .onEnded { _ in
                if dragging != nil || seamDrag != nil { session.endDrag() }
                dragging = nil
                seamDrag = nil
                keys = true
            }
    }
}
