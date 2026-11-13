import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Anti-Crop: cut a band out of the middle of a photo and close the gap, at the
/// original's full size. Opened from Tools in the menu, or on a project photo
/// from the viewer.
struct AntiCropView: View {
    /// A photo to open straight away, when started from a project.
    var initial: URL?

    @Environment(\.scenePhase) private var scenePhase
    @State private var session = AntiCropSession()
    @State private var photo: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var choosingFile = false
    @State private var choosingProject = false
    @State private var after = false
    @State private var zoom: CGFloat = 1
    @State private var pinchStart: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: "Tools", title: "Anti-Crop", status: status)
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
            if session.source != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("From Photos") { choosingPhoto = true }
                        Button("From Files") { choosingFile = true }
                        Button("From a project") { choosingProject = true }
                    } label: {
                        Label("Another Photo", systemImage: "photo.badge.plus")
                    }
                    .disabled(session.busy)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.source != nil || session.busy {
                ToolBottomBar(
                    busy: session.busy, phase: session.phase,
                    progress: session.phase.hasPrefix("Exporting") ? session.progress : nil,
                    cancel: session.cancel, result: session.result, isVideo: false
                ) {
                    Button { session.export() } label: {
                        Text("Export PNG").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill)
                    .disabled(session.geometry == nil)
                }
            }
        }
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
        .onChange(of: session.edit) { old, _ in session.record(old) }
        .onChange(of: session.source?.url) {
            zoom = 1
            after = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && session.busy {
                session.cancel()
                session.error = "Stopped when BestShot went into the background. Keep it open while exporting."
            }
        }
        .task {
            if let initial, session.source == nil { session.open(initial) }
        }
        .onDisappear { session.cancel() }
    }

    private var status: String? {
        session.source.map { "\($0.width) × \($0.height) px" }
    }

    // MARK: - Nothing open

    private var empty: some View {
        EmptyState(title: "Choose a Photo",
                   message: "Cut a band out of the middle of a photo and close the gap, at full size. The original stays as it is.") {
            if !session.busy {
                ToolSourceButtons(files: { choosingFile = true }, project: { choosingProject = true }) {
                    Button("Choose from Photos") { choosingPhoto = true }
                        .buttonStyle(.pill)
                }
            }
            if let error = session.error { ToolError(text: error) }
        }
    }

    // MARK: - Editing

    private func editor(_ source: AntiCropBridge.Source) -> some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            canvas(source)
            Form {
                TableSection(title: "Band") {
                    Picker("Band", selection: Binding(
                        get: { session.edit.axis },
                        set: {
                            session.edit.axis = $0
                            session.reset()
                        }
                    )) {
                        Text("Across").tag("horizontal")
                        Text("Down").tag("vertical")
                    }
                    .pickerStyle(.segmented)
                    Picker("Show", selection: $after) {
                        Text("Before").tag(false)
                        Text("After").tag(true)
                    }
                    .pickerStyle(.segmented)
                    PixelField(label: session.edit.axis == "horizontal" ? "From row" : "From column",
                               value: $session.edit.remove_start_px)
                    PixelField(label: "Up to", value: $session.edit.remove_end_px)
                    HStack(spacing: Theme.Space.actions) {
                        Button("Undo") { session.undo() }.disabled(!session.canUndo)
                        Button("Reset") { session.reset() }
                        Spacer()
                    }
                    .buttonStyle(.text)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let validation = session.validation {
                            ToolError(text: validation)
                        } else if let geometry = session.geometry {
                            FormNote("Comes out at \(geometry.width) × \(geometry.height) px, as a PNG.")
                        }
                        if let error = session.error { ToolError(text: error) }
                    }
                }
                TableSection("The file") {
                    FormNote("Kept pixels are copied exactly, never resized. The PNG is 8-bit sRGB and keeps transparency; HDR and wide colour are converted. Location and other metadata are left out. Photos over 67 megapixels can't be opened.")
                }
            }
            .tableForm()
            .scrollDismissesKeyboard(.interactively)
            .disabled(session.busy)
        }
    }

    /// The photo with its band: drag the two handles, pinch or double-tap to zoom.
    private func canvas(_ source: AntiCropBridge.Source) -> some View {
        GeometryReader { box in
            ScrollView([.horizontal, .vertical], showsIndicators: zoom > 1) {
                AntiCropCanvas(source: source, edit: $session.edit, after: after,
                               onAdjust: session.beginAdjusting, onAdjusted: session.endAdjusting)
                    .frame(width: box.size.width * zoom, height: box.size.height * zoom)
                    .disabled(session.busy)
            }
            .scrollDisabled(zoom <= 1)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let start = pinchStart ?? zoom
                        pinchStart = start
                        zoom = min(max(start * value, 1), 4)
                    }
                    .onEnded { _ in pinchStart = nil }
            )
            .onTapGesture(count: 2) {
                Theme.Motion.run(Theme.Motion.settle) { zoom = zoom > 1 ? 1 : 2.5 }
            }
        }
        .padding(Theme.Space.gutter)
        .frame(maxHeight: .infinity)
        .layoutPriority(1)
        .background(Theme.table.tile)
    }
}

struct AntiCropCanvas: View {
    let source: AntiCropBridge.Source
    @Binding var edit: AntiCropConfiguration
    let after: Bool
    /// A drag of a handle starting and ending: one drag is one step of Undo.
    var onAdjust: () -> Void = {}
    var onAdjusted: () -> Void = {}

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / CGFloat(source.width), geometry.size.height / CGFloat(source.height))
            let w = CGFloat(source.width) * scale
            let h = CGFloat(source.height) * scale
            ZStack {
                if after, let plan = try? edit.plan(width: source.width, height: source.height) {
                    joined(scale: scale, width: w, height: h)
                        .frame(width: CGFloat(plan.width) * scale, height: CGFloat(plan.height) * scale)
                } else {
                    ZStack(alignment: .topLeading) {
                        Image(decorative: source.preview, scale: 1).resizable().frame(width: w, height: h)
                        let start = CGFloat(edit.remove_start_px) * scale
                        let end = CGFloat(edit.remove_end_px) * scale
                        let horizontal = edit.axis == "horizontal"
                        Rectangle().fill(Theme.table.accent.opacity(0.35))
                            .frame(
                                width: horizontal ? w : max(0, end - start),
                                height: horizontal ? max(0, end - start) : h
                            )
                            .offset(x: horizontal ? 0 : start, y: horizontal ? start : 0)
                            .allowsHitTesting(false)
                        guide(start: true, scale: scale, width: w, height: h)
                        guide(start: false, scale: scale, width: w, height: h)
                    }
                    .frame(width: w, height: h)
                    .coordinateSpace(name: "cutCanvas")
                    .clipped()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityLabel(after ? "The photo with the band taken out" : "The photo, with the band to take out between two handles")
    }

    /// The two kept parts of the preview, drawn edge to edge.
    private func joined(scale: CGFloat, width w: CGFloat, height h: CGFloat) -> some View {
        Canvas { context, _ in
            let image = source.preview
            let sx = CGFloat(image.width) / CGFloat(source.width)
            let sy = CGFloat(image.height) / CGFloat(source.height)
            let horizontal = edit.axis == "horizontal"
            let first = horizontal
                ? CGRect(x: 0, y: 0, width: image.width, height: Int(CGFloat(edit.remove_start_px) * sy))
                : CGRect(x: 0, y: 0, width: Int(CGFloat(edit.remove_start_px) * sx), height: image.height)
            let second = horizontal
                ? CGRect(x: 0, y: Int(CGFloat(edit.remove_end_px) * sy), width: image.width,
                         height: image.height - Int(CGFloat(edit.remove_end_px) * sy))
                : CGRect(x: Int(CGFloat(edit.remove_end_px) * sx), y: 0,
                         width: image.width - Int(CGFloat(edit.remove_end_px) * sx), height: image.height)
            guard let top = image.cropping(to: first), let bottom = image.cropping(to: second) else { return }
            let a = horizontal
                ? CGRect(x: 0, y: 0, width: w, height: CGFloat(edit.remove_start_px) * scale)
                : CGRect(x: 0, y: 0, width: CGFloat(edit.remove_start_px) * scale, height: h)
            let b = horizontal
                ? CGRect(x: 0, y: a.maxY, width: w, height: CGFloat(source.height - edit.remove_end_px) * scale)
                : CGRect(x: a.maxX, y: 0, width: CGFloat(source.width - edit.remove_end_px) * scale, height: h)
            context.draw(Image(decorative: top, scale: 1), in: a)
            context.draw(Image(decorative: bottom, scale: 1), in: b)
        }
    }

    private func guide(start: Bool, scale: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        let horizontal = edit.axis == "horizontal"
        let value = start ? edit.remove_start_px : edit.remove_end_px
        return ZStack {
            Rectangle().fill(Theme.table.accent)
                .frame(width: horizontal ? width : 2, height: horizontal ? 2 : height)
            Circle().fill(Theme.table.accent)
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: horizontal ? "arrow.up.and.down" : "arrow.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.table.accentInk)
                }
        }
        .frame(width: horizontal ? width : 44, height: horizontal ? 44 : height)
        .contentShape(Rectangle())
        .position(
            x: horizontal ? width / 2 : CGFloat(value) * scale,
            y: horizontal ? CGFloat(value) * scale : height / 2
        )
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("cutCanvas"))
                .onChanged { drag in
                    onAdjust()
                    let dimension = horizontal ? source.height : source.width
                    let pixel = Int(((horizontal ? drag.location.y : drag.location.x) / scale).rounded())
                    if start {
                        edit.remove_start_px = min(max(1, pixel), edit.remove_end_px - 1)
                    } else {
                        edit.remove_end_px = max(edit.remove_start_px + 1, min(dimension - 1, pixel))
                    }
                }
                .onEnded { _ in onAdjusted() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(start ? "Start of the band" : "End of the band")
        .accessibilityValue("\(value) pixels")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 1 : -1
            let dimension = horizontal ? source.height : source.width
            if start {
                edit.remove_start_px = min(max(1, value + delta), edit.remove_end_px - 1)
            } else {
                edit.remove_end_px = max(edit.remove_start_px + 1, min(dimension - 1, value + delta))
            }
        }
    }
}
