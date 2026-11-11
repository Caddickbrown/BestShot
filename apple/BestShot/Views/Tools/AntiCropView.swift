import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AntiCropView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var session = AntiCropSession()
  @State private var photo: PhotosPickerItem?
  @State private var importing = false
  @State private var openingSettings = false
  @State private var savingSettings = false
  @State private var after = false
  @State private var zoom = 1.0
  var body: some View {
    @Bindable var session = session
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Remove a middle band and join the retained pixels without resizing.").font(.note)
        HStack {
          Button("Open image in Files") { importing = true }
          PhotosPicker("Photos", selection: $photo, matching: .images)
          ToolProjectPicker(kind: .image) { session.open($0) }
        }.disabled(session.busy)
        if let source = session.source {
          Text("Original: \(source.width) × \(source.height) px").font(.caption.monospaced())
          Picker(
            "Remove band",
            selection: Binding(
              get: { session.edit.axis },
              set: {
                session.edit.axis = $0
                session.reset()
              })
          ) {
            Text("Horizontal").tag("horizontal")
            Text("Vertical").tag("vertical")
          }.pickerStyle(.segmented).disabled(session.busy)
          HStack {
            TextField("Start pixel", value: $session.edit.remove_start_px, format: .number)
              .accessibilityLabel("First removed pixel, inclusive")
            TextField("End pixel", value: $session.edit.remove_end_px, format: .number)
              .accessibilityLabel("First retained pixel after band, exclusive")
          }.textFieldStyle(.roundedBorder).disabled(session.busy)
          Toggle("After Hard Join", isOn: $after)
          HStack {
            Text("Zoom")
            Slider(value: $zoom, in: 1...4).accessibilityLabel("Preview zoom")
          }
          ScrollView([.horizontal, .vertical]) {
            AntiCropCanvas(source: source, edit: $session.edit, after: after)
              .frame(width: 330 * zoom, height: 330 * zoom)
              .disabled(session.busy)
          }.frame(height: 350)
          if let geometry = session.geometry {
            Text("Output: \(geometry.width) × \(geometry.height) px · PNG").font(
              .caption.monospaced())
          }
          if let validation = session.validation {
            Label(validation, systemImage: "exclamationmark.triangle")
          }
          Text(
            "Hard Join keeps retained sRGB pixels without resampling. Exports convert to 8-bit sRGB and preserve alpha; HDR and wide gamut are converted. Location and other source metadata are omitted. Images above 64 megapixels are rejected before decoding."
          )
          .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button("Undo") { session.undo() }.disabled(!session.canUndo)
            Button("Reset band") { session.reset() }
            Button("Export PNG") { session.export() }.disabled(session.geometry == nil)
          }.disabled(session.busy)
          HStack {
            Button("Save settings") { savingSettings = true }
            Button("Reopen settings") { openingSettings = true }
          }.disabled(session.busy)
        }
        if session.busy {
          Text(session.phase)
          ProgressView(value: session.phase.hasPrefix("Exporting") ? session.progress : nil)
          Button("Cancel") { session.cancel() }
        }
        if let error = session.error {
          Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
        }
        if let url = session.result { MediaResultView(url: url, isVideo: false) }
      }.padding()
    }
    .tableSurface()
    .navigationTitle("Anti-Crop")
    .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
      switch result {
      case .success(let url): session.open(url)
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
      document: MediaSettingsDocument((try? JSONEncoder().encode(session.edit)) ?? Data()),
      contentType: .json, defaultFilename: "BestShot-AntiCrop"
    ) { result in
      if case .failure(let error) = result { session.error = error.localizedDescription }
    }
    .onChange(of: photo) { _, item in
      if let item {
        session.openPhoto(item)
        photo = nil
      }
    }
    .onChange(of: session.edit) { old, _ in session.record(old) }
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

struct AntiCropCanvas: View {
  let source: AntiCropBridge.Source
  @Binding var edit: AntiCropConfiguration
  let after: Bool
  var body: some View {
    GeometryReader { geometry in
      let scale = min(
        geometry.size.width / CGFloat(source.width), geometry.size.height / CGFloat(source.height))
      let w = CGFloat(source.width) * scale
      let h = CGFloat(source.height) * scale
      ZStack {
        if after, let plan = try? edit.plan(width: source.width, height: source.height) {
          Canvas { context, _ in
            let image = source.preview
            let sx = CGFloat(image.width) / CGFloat(source.width)
            let sy = CGFloat(image.height) / CGFloat(source.height)
            let horizontal = edit.axis == "horizontal"
            let first =
              horizontal
              ? CGRect(
                x: 0, y: 0, width: image.width, height: Int(CGFloat(edit.remove_start_px) * sy))
              : CGRect(
                x: 0, y: 0, width: Int(CGFloat(edit.remove_start_px) * sx), height: image.height)
            let second =
              horizontal
              ? CGRect(
                x: 0, y: Int(CGFloat(edit.remove_end_px) * sy), width: image.width,
                height: image.height - Int(CGFloat(edit.remove_end_px) * sy))
              : CGRect(
                x: Int(CGFloat(edit.remove_end_px) * sx), y: 0,
                width: image.width - Int(CGFloat(edit.remove_end_px) * sx), height: image.height)
            if let top = image.cropping(to: first), let bottom = image.cropping(to: second) {
              let a =
                horizontal
                ? CGRect(x: 0, y: 0, width: w, height: CGFloat(edit.remove_start_px) * scale)
                : CGRect(x: 0, y: 0, width: CGFloat(edit.remove_start_px) * scale, height: h)
              let b =
                horizontal
                ? CGRect(
                  x: 0, y: a.maxY, width: w,
                  height: CGFloat(source.height - edit.remove_end_px) * scale)
                : CGRect(
                  x: a.maxX, y: 0, width: CGFloat(source.width - edit.remove_end_px) * scale,
                  height: h)
              context.draw(Image(decorative: top, scale: 1), in: a)
              context.draw(Image(decorative: bottom, scale: 1), in: b)
            }
          }.frame(width: CGFloat(plan.width) * scale, height: CGFloat(plan.height) * scale)
        } else {
          ZStack(alignment: .topLeading) {
            Image(decorative: source.preview, scale: 1).resizable().frame(width: w, height: h)
            let start = CGFloat(edit.remove_start_px) * scale
            let end = CGFloat(edit.remove_end_px) * scale
            let horizontal = edit.axis == "horizontal"
            Rectangle().fill(.black.opacity(0.45))
              .frame(
                width: horizontal ? w : max(0, end - start),
                height: horizontal ? max(0, end - start) : h
              )
              .offset(x: horizontal ? 0 : start, y: horizontal ? start : 0)
              .allowsHitTesting(false)
            guide(start: true, scale: scale, width: w, height: h)
            guide(start: false, scale: scale, width: w, height: h)
          }.frame(width: w, height: h).coordinateSpace(name: "cutCanvas").clipped()
        }
      }.frame(width: geometry.size.width, height: geometry.size.height)
    }.accessibilityLabel(
      after
        ? "After removing the selected band" : "Image with removable band and two boundary guides")
  }
  private func guide(start: Bool, scale: CGFloat, width: CGFloat, height: CGFloat) -> some View {
    let horizontal = edit.axis == "horizontal"
    let value = start ? edit.remove_start_px : edit.remove_end_px
    return ZStack {
      Rectangle().fill(.white).frame(width: horizontal ? width : 2, height: horizontal ? 2 : height)
      Image(
        systemName: horizontal
          ? "arrow.up.and.down.circle.fill" : "arrow.left.and.right.circle.fill"
      )
      .font(.title2).foregroundStyle(.black, .white)
    }
    .frame(width: horizontal ? width : 44, height: horizontal ? 44 : height)
    .contentShape(Rectangle())
    .position(
      x: horizontal ? width / 2 : CGFloat(value) * scale,
      y: horizontal ? CGFloat(value) * scale : height / 2
    )
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .named("cutCanvas")).onChanged { drag in
        let dimension = horizontal ? source.height : source.width
        let pixel = Int(((horizontal ? drag.location.y : drag.location.x) / scale).rounded())
        if start {
          edit.remove_start_px = min(max(1, pixel), edit.remove_end_px - 1)
        } else {
          edit.remove_end_px = max(edit.remove_start_px + 1, min(dimension - 1, pixel))
        }
      }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(start ? "Removal start" : "Removal end")
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
