#if os(macOS)
import SwiftUI
import AVKit

/// Culling a folder: the loupe (viewfinder), the grid and Rank (light table),
/// and Clear out. Keys match BestShot for Linux.
struct FolderCullView: View {
    @Bindable var session: FolderCullSession
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            switch session.mode {
            case .loupe: loupe
            case .grid: grid
            case .rank:
                if let board = session.rankBoard { RankBoardView(board: board) }
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in handle(press) }
        .sheet(isPresented: $session.showFinish) {
            FolderFinishView(session: session)
        }
    }

    // MARK: - Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Rank has its own keys inside Compare.
        if session.mode == .rank, session.rankBoard?.compare != nil { return .ignored }
        let command = press.modifiers.contains(.command)
        if command && press.characters == "z" { session.undo(); return .handled }
        if command { return .ignored }

        switch (session.mode, press.key) {
        case (.loupe, .rightArrow): session.decide(.keep)
        case (.loupe, .leftArrow): session.decide(.reject)
        case (.loupe, .downArrow), (.loupe, .space): session.next()
        case (.loupe, .upArrow): session.previous()
        case (_, .delete): session.undo()
        case (.loupe, .home): session.show(0)
        case (.loupe, .end): session.show(session.items.count - 1)
        case (_, .escape):
            if session.zoomed { session.zoomed = false } else if session.mode != .loupe { session.mode = .loupe } else { session.showDone = false }
        default:
            switch (session.mode, press.characters.lowercased()) {
            case (.loupe, "p"): session.decide(.keep)
            case (.loupe, "x"): session.decide(.reject)
            case (.loupe, "u"): session.clearDecision()
            case (.loupe, "n"): session.jumpToNextUnreviewed()
            case (.loupe, "z"): session.zoomed.toggle()
            case (.loupe, "i"): session.showInfo.toggle()
            case (_, "g"): session.mode = session.mode == .grid ? .loupe : .grid
            case (_, "r"): session.mode = session.mode == .rank ? .loupe : .rank
            default: return .ignored
            }
        }
        return .handled
    }

    // MARK: - Top bar

    private var palette: Theme.Palette { session.mode == .loupe ? Theme.viewfinder : Theme.table }

    private var topBar: some View {
        let c = session.counts
        let total = max(session.items.count, 1)
        return HStack(spacing: 20) {
            Button("‹ Folders", action: onClose)
                .buttonStyle(TextButtonStyle(palette: palette))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.display(22, weight: 800, width: 70))
                if let item = session.current {
                    Text("\(session.index + 1) / \(session.items.count) · \(item.rel)")
                        .font(.mono(11))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(palette.ink).frame(width: geo.size.width * CGFloat(c.keep) / CGFloat(total))
                    Rectangle().fill(palette.accent).frame(width: geo.size.width * CGFloat(c.reject) / CGFloat(total))
                    Spacer(minLength: 0)
                }
                .background(palette.rule)
            }
            .frame(height: 2)
            HStack(spacing: 12) {
                Text("✓ \(c.keep)")
                Text("✕ \(c.reject)").foregroundStyle(palette.accent)
                Text("○ \(c.left)").foregroundStyle(palette.muted)
            }
            .font(.mono(12))
            HStack(spacing: 14) {
                modeButton("Grid", .grid)
                modeButton("Rank", .rank)
                if session.mode == .loupe {
                    Button("Info") { session.showInfo.toggle() }.buttonStyle(TextButtonStyle(palette: palette))
                }
                Button("Clear out…") { session.showFinish = true }
                    .buttonStyle(PillButtonStyle(palette: palette))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .foregroundStyle(palette.ink)
        .background(session.mode == .loupe ? Color.black : Theme.table.background)
    }

    private func modeButton(_ title: String, _ mode: FolderCullSession.Mode) -> some View {
        Button(title) { session.mode = session.mode == mode ? .loupe : mode }
            .buttonStyle(TextButtonStyle(palette: palette))
            .overlay(alignment: .bottom) {
                if session.mode == mode {
                    GreasePencilMark(shape: .underline, color: palette.accent, lineWidth: 2)
                        .frame(height: 6)
                        .offset(y: 6)
                }
            }
    }

    // MARK: - Loupe

    private var loupe: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                stage
                if session.showInfo, let item = session.current {
                    FolderInfoPanel(item: item, url: session.url(for: item))
                        .frame(width: 280)
                }
            }
            filmstrip
        }
        .viewfinder()
    }

    private var stage: some View {
        ZStack {
            if let item = session.current {
                let url = session.url(for: item)
                if item.isVideo {
                    VideoPlayer(player: AVPlayer(url: url))
                        .id(url)
                } else if session.zoomed {
                    ScrollView([.horizontal, .vertical]) {
                        FolderImage(url: url, maxPixel: 8000, contentMode: .fit)
                    }
                } else {
                    FolderImage(url: url, maxPixel: 2400, contentMode: .fit)
                        .padding(.horizontal, 84)
                        .onTapGesture { session.zoomed = true }
                }
                decisionMark(session.decision(at: session.index))
            }
            HStack {
                edge("← BIN", rotate: true) { session.decide(.reject) }
                Spacer()
                edge("KEEP →", rotate: false) { session.decide(.keep) }
            }
            if session.showDone { doneCard }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: session.index) { preloadNeighbours() }
    }

    @ViewBuilder
    private func decisionMark(_ decision: Decision?) -> some View {
        switch decision {
        case .keep:
            GreasePencilMark(shape: .stageCircle, color: Theme.viewfinder.accent, lineWidth: 5)
                .padding(40)
        case .reject:
            GreasePencilMark(shape: .stageCross, color: Theme.viewfinder.accent, lineWidth: 5)
                .padding(40)
        case nil:
            EmptyView()
        }
    }

    private func edge(_ label: String, rotate: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.mono(12))
                .tracking(2)
                .fixedSize()
                .rotationEffect(.degrees(rotate ? -90 : 90))
                .frame(width: 84)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.viewfinder.muted)
        .opacity(session.zoomed ? 0 : 1)
    }

    private var doneCard: some View {
        let c = session.counts
        return VStack(spacing: 12) {
            Text("All reviewed").font(.display(30, weight: 800, width: 70))
            Text("\(session.items.count) photos: \(c.keep) kept, \(c.reject) for the bin.")
                .font(.mono(13))
                .foregroundStyle(Theme.viewfinder.muted)
            HStack(spacing: 18) {
                Button("Rank keepers") { session.mode = .rank }.buttonStyle(.viewfinderText)
                Button("Clear out…") { session.showFinish = true }.buttonStyle(.viewfinderPill)
            }
        }
        .padding(28)
        .background(Color.black.opacity(0.85))
    }

    private var filmstrip: some View {
        HStack(spacing: 14) {
            Button("Undo") { session.undo() }.buttonStyle(.viewfinderText)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 4) {
                        ForEach(session.items.indices, id: \.self) { i in
                            Button { session.show(i) } label: {
                                FolderImage(url: session.url(for: session.items[i]), maxPixel: 160)
                                    .frame(width: 56, height: 56)
                                    .clipped()
                                    .opacity(i == session.index ? 1 : 0.55)
                                    .overlay(alignment: .bottom) {
                                        if let d = session.decision(at: i) {
                                            Rectangle().fill(d == .keep ? Theme.viewfinder.ink : Theme.viewfinder.accent).frame(height: 3)
                                        }
                                    }
                                    .overlay(Rectangle().stroke(i == session.index ? Theme.viewfinder.ink : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .id(i)
                        }
                    }
                }
                .onChange(of: session.index) { _, i in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(i, anchor: .center) } }
                .onAppear { proxy.scrollTo(session.index, anchor: .center) }
            }
            .frame(height: 56)
            Button("Skip") { session.next() }.buttonStyle(.viewfinderText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { HairlineRule(palette: Theme.viewfinder) }
    }

    private func preloadNeighbours() {
        let urls = (session.index + 1...session.index + 3)
            .filter { session.items.indices.contains($0) && !session.items[$0].isVideo }
            .map { session.url(for: session.items[$0]) }
        Task.detached(priority: .utility) { await FolderImageCache.shared.preload(urls, maxPixel: 2400) }
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                ForEach(FolderCullSession.Filter.allCases) { f in
                    Button { session.filter = f } label: {
                        Text(f.rawValue)
                            .font(.mono(13, medium: session.filter == f))
                            .foregroundStyle(session.filter == f ? Theme.table.ink : Theme.table.muted)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Click a photo to review it · G or Esc to go back")
                    .font(.mono(11))
                    .foregroundStyle(Theme.table.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            HairlineRule()
            ScrollView {
                ContactSheet(data: session.filteredIndices.map(GridTile.init), minimum: 150) { tile in
                    Button {
                        session.show(tile.id)
                        session.mode = .loupe
                    } label: {
                        FolderImage(url: session.url(for: session.items[tile.id]), maxPixel: 480)
                            .overlay {
                                switch session.decision(at: tile.id) {
                                case .keep: GreasePencilMark(shape: .circle, lineWidth: 3).padding(8)
                                case .reject: GreasePencilMark(shape: .cross, lineWidth: 3).padding(8)
                                case nil: EmptyView()
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
            }
        }
        .lightTable()
    }

    private struct GridTile: Identifiable { let id: Int }
}

/// EXIF details for the loupe's Info panel.
private struct FolderInfoPanel: View {
    let item: FolderItem
    let url: URL
    @State private var rows: [Row] = []

    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetLabel("Details", palette: Theme.viewfinder)
            Text(item.filename).font(.mono(13, medium: true))
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label).font(.mono(10)).foregroundStyle(Theme.viewfinder.muted)
                    Text(row.value).font(.mono(12))
                }
            }
            Spacer()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .buttonStyle(.viewfinderText)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.viewfinder.rule).frame(width: 1) }
        .task(id: item.rel) { rows = Self.details(for: item, url: url) }
    }

    private static func details(for item: FolderItem, url: URL) -> [Row] {
        var rows: [Row] = []
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            if let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String { rows.append(Row(label: "Taken", value: taken)) }
            let camera = [tiff[kCGImagePropertyTIFFMake] as? String, tiff[kCGImagePropertyTIFFModel] as? String]
                .compactMap { $0 }.joined(separator: " ")
            if !camera.isEmpty { rows.append(Row(label: "Camera", value: camera)) }
            var exposure: [String] = []
            if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
                exposure.append(t < 1 ? "1/\(Int((1 / t).rounded())) s" : "\(t) s")
            }
            if let f = exif[kCGImagePropertyExifFNumber] as? Double { exposure.append(String(format: "f/%.1f", f)) }
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { exposure.append("ISO \(iso)") }
            if !exposure.isEmpty { rows.append(Row(label: "Exposure", value: exposure.joined(separator: " · "))) }
            if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
                rows.append(Row(label: "Dimensions", value: "\(w) × \(h)"))
            }
        }
        rows.append(Row(label: "File size", value: ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)))
        if !item.companions.isEmpty {
            rows.append(Row(label: "Moves with", value: item.companions.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")))
        }
        return rows
    }
}

/// Clear out: send the rejects to the Trash or a `_Rejected` folder.
private struct FolderFinishView: View {
    let session: FolderCullSession
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var outcome: CullOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clear out").font(.display(30, weight: 800, width: 70))
            if let outcome {
                Text("Moved \(outcome.items) photo\(outcome.items == 1 ? "" : "s") (\(ByteCountFormatter.string(fromByteCount: Int64(outcome.bytes), countStyle: .file))).")
                    .font(.mono(13))
                if !outcome.failed.isEmpty {
                    Text("\(outcome.failed.count) couldn't be moved and are still marked:")
                        .font(.mono(12))
                        .foregroundStyle(Theme.table.accent)
                    ScrollView {
                        Text(outcome.failed.map { "\($0.rel): \($0.error)" }.joined(separator: "\n"))
                            .font(.mono(11))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                }
                HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.pill) }
            } else {
                summary
            }
        }
        .padding(28)
        .frame(width: 520)
        .lightTable()
    }

    @ViewBuilder
    private var summary: some View {
        let rejects = session.rejects
        let c = session.counts
        if rejects.isEmpty {
            Text("Nothing is marked for the bin yet. Press ← or X on a photo to mark it.")
                .font(.mono(13))
                .foregroundStyle(Theme.table.muted)
            HStack { Spacer(); Button("Close") { dismiss() }.buttonStyle(.text) }
        } else {
            let bytes = rejects.reduce(UInt64(0)) { $0 + $1.size }
            let extras = rejects.reduce(0) { $0 + $1.companions.count }
            Text("\(rejects.count) photo\(rejects.count == 1 ? "" : "s") marked for the bin (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))"
                 + (extras > 0 ? ", plus \(extras) Live Photo / sidecar file\(extras == 1 ? "" : "s") that go with them." : "."))
                .font(.mono(13))
            if c.left > 0 {
                Text("\(c.left) haven't been reviewed and will be left alone.")
                    .font(.mono(12))
                    .foregroundStyle(Theme.table.muted)
            }
            HStack(spacing: 18) {
                Button("Keep reviewing") { dismiss() }.buttonStyle(.text)
                Spacer()
                Button("Move to “_Rejected”") { run(.folder) }.buttonStyle(.text).disabled(working)
                Button("Move to Trash") { run(.trash) }.buttonStyle(.pill).disabled(working)
            }
        }
    }

    private func run(_ mode: CullMode) {
        working = true
        Task {
            outcome = await session.applyCull(mode: mode)
            working = false
        }
    }
}
#endif
