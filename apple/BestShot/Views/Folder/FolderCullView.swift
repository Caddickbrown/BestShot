#if os(macOS)
import SwiftUI
import AVKit

/// Culling a folder: the loupe (viewfinder), the grid and Rank (light table),
/// and Clear out. Keys match BestShot for Linux; see `FolderKeymap`.
struct FolderCullView: View {
    @Bindable var session: FolderCullSession
    let onClose: () -> Void
    @FocusState private var focused: Bool
    private let labels = LabelStore.shared

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if session.mode != .rank { FolderFilterBar(session: session, palette: palette) }
            notices
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
        // Clicks on the filter bar or leaving the keyword field can drop focus.
        .onChange(of: session.typingKeyword) { _, typing in if !typing { focused = true } }
        .onChange(of: session.filter) { focused = true }
        .onChange(of: session.sort) { focused = true }
        .onChange(of: labels.revision) { session.settingsChanged() }
        .sheet(isPresented: $session.showFinish) {
            FolderFinishView(session: session)
        }
        .sheet(isPresented: $session.showProblems) {
            FolderProblemsView(session: session)
        }
    }

    /// Anything that went wrong, where it can't be missed.
    @ViewBuilder
    private var notices: some View {
        if let warning = session.warning {
            HStack {
                Text(warning).font(.mono(12)).lineLimit(3).textSelection(.enabled)
                Spacer()
                Button("Dismiss") { session.warning = nil }
                    .buttonStyle(TextButtonStyle(palette: palette))
            }
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .background(palette.background)
        }
        if !session.problems.isEmpty {
            HStack {
                Text("\(session.problems.count) file\(session.problems.count == 1 ? "" : "s") with unreadable metadata won't be written.")
                    .font(.mono(12))
                Spacer()
                Button("Show") { session.showProblems = true }
                    .buttonStyle(TextButtonStyle(palette: palette))
            }
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .background(palette.background)
        }
    }

    // MARK: - Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Typing a keyword is text, and Rank has its own keys inside Compare.
        if session.typingKeyword { return .ignored }
        if session.mode == .rank, session.rankBoard?.compare != nil { return .ignored }
        let surface: FolderSurface
        switch session.mode {
        case .loupe: surface = .loupe
        case .grid: surface = .grid
        case .rank: surface = .rank
        }
        guard let command = FolderKeymap.command(key: press.key, characters: press.characters, modifiers: press.modifiers, on: surface) else {
            return .ignored
        }
        session.perform(command)
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
                    Text("\(session.position.map { String($0 + 1) } ?? "–") / \(session.visible.count) · \(item.rel)")
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
                    Rectangle().fill(palette.muted).frame(width: geo.size.width * CGFloat(c.other) / CGFloat(total))
                    Spacer(minLength: 0)
                }
                .background(palette.rule)
            }
            .frame(height: 2)
            HStack(spacing: 12) {
                Text("✓ \(c.keep)")
                Text("✕ \(c.reject)").foregroundStyle(palette.accent)
                if c.other > 0 { Text("? \(c.other)").foregroundStyle(palette.muted) }
                Text("○ \(c.left)").foregroundStyle(palette.muted)
            }
            .font(.mono(12))
            HStack(spacing: 14) {
                modeButton("Grid", .grid)
                modeButton("Rank", .rank)
                if session.mode == .loupe {
                    Button("Info") { session.showInfo.toggle() }.buttonStyle(TextButtonStyle(palette: palette))
                    Button("Keywords") { session.toggleKeywords() }.buttonStyle(TextButtonStyle(palette: palette))
                }
                if c.reject > 0 {
                    Button("Trash all red…") { session.confirmTrashRed() }
                        .buttonStyle(TextButtonStyle(palette: palette, destructive: true))
                        .help("⌘⌫")
                }
                Button("Clear out…") { session.confirmFinish() }
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
                if session.showKeywords, let item = session.current, let row = session.rows[item.rel] {
                    FolderKeywordPanel(session: session, row: row)
                        .frame(width: 280)
                }
                if session.showInfo, let item = session.current {
                    FolderInfoPanel(item: item, url: session.url(for: item), companions: session.companions(of: item))
                        .frame(width: 280)
                }
            }
            filmstrip
        }
        .viewfinder()
    }

    private var stage: some View {
        ZStack {
            if session.noMatches {
                VStack(spacing: 12) {
                    Text("Nothing matches these filters").font(.display(26, weight: 800, width: 70))
                    Button("Clear filters") { session.filter = .all }.buttonStyle(.viewfinderText)
                }
            } else if let item = session.current {
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
                if let row = session.rows[item.rel], hasMeta(row) {
                    LoupeMetaBadge(row: row)
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, session.zoomed ? 0 : 84)
                }
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

    private func hasMeta(_ row: MetaRow) -> Bool {
        row.colour != nil || row.label != nil || row.rating != 0 || !row.keywords.isEmpty || row.problem != nil
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
                Button("Clear out…") { session.confirmFinish() }.buttonStyle(.viewfinderPill)
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
                        ForEach(session.visible, id: \.self) { i in
                            Button { session.show(i) } label: {
                                FolderImage(url: session.url(for: session.items[i]), maxPixel: 160)
                                    .frame(width: 56, height: 56)
                                    .clipped()
                                    .opacity(i == session.index ? 1 : 0.55)
                                    .overlay(alignment: .bottom) {
                                        if let colour = session.row(at: i)?.colour {
                                            Rectangle().fill(Theme.label(colour)).frame(height: 5)
                                        } else if let d = session.decision(at: i) {
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
        let start = session.position ?? 0
        let urls = session.visible.dropFirst(start + 1).prefix(3)
            .filter { !session.items[$0].isVideo }
            .map { session.url(for: session.items[$0]) }
        Task.detached(priority: .utility) { await FolderImageCache.shared.preload(urls, maxPixel: 2400) }
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Click a photo to review it · arrows move · 1-5 stars · 6-9 label · G or Esc to go back")
                    .font(.mono(11))
                    .foregroundStyle(Theme.table.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            HairlineRule()
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        ContactSheet(data: session.visible.map(GridTile.init), minimum: 150) { tile in
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
                                    .overlay { if let row = session.row(at: tile.id) { TileMetaBadge(row: row) } }
                                    .overlay { Rectangle().stroke(tile.id == session.index ? Theme.table.ink : .clear, lineWidth: 3) }
                            }
                            .buttonStyle(.plain)
                            .id(tile.id)
                        }
                        .padding(4)
                    }
                    .onChange(of: session.index) { _, i in proxy.scrollTo(i) }
                    .onAppear { proxy.scrollTo(session.index, anchor: .center) }
                }
                // Matches ContactSheet's adaptive columns, for up and down.
                .onChange(of: geo.size.width, initial: true) { _, width in
                    session.gridColumns = max(Int((width - 8 + 4) / 154), 1)
                }
            }
        }
        .tableSurface()
    }

    private struct GridTile: Identifiable { let id: Int }
}

/// EXIF details for the loupe's Info panel.
private struct FolderInfoPanel: View {
    let item: FolderItem
    let url: URL
    let companions: [String]
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
        .task(id: [item.rel] + companions) { rows = Self.details(for: item, url: url, companions: companions) }
    }

    private static func details(for item: FolderItem, url: URL, companions: [String]) -> [Row] {
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
        if !companions.isEmpty {
            rows.append(Row(label: "Moves with", value: companions.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")))
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
            Text(session.finishTrashOnly ? "Trash all red" : "Clear out").font(.display(30, weight: 800, width: 70))
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
        .tableSurface()
    }

    @ViewBuilder
    private var summary: some View {
        let rejects = session.rejects
        let c = session.counts
        if rejects.isEmpty {
            Text("Nothing is marked for the bin yet. Press 6, ← or X on a photo to mark it.")
                .font(.mono(13))
                .foregroundStyle(Theme.table.muted)
            HStack { Spacer(); Button("Close") { dismiss() }.buttonStyle(.text) }
        } else {
            let bytes = rejects.reduce(UInt64(0)) { $0 + $1.size }
            let extras = rejects.reduce(0) { $0 + session.companions(of: $1).count }
            Text("\(rejects.count) red photo\(rejects.count == 1 ? "" : "s") marked for the bin (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))"
                 + (extras > 0 ? ", plus \(extras) Live Photo / sidecar file\(extras == 1 ? "" : "s") that go with them." : "."))
                .font(.mono(13))
            if session.filter.isActive {
                Text("This covers every red in the folder, not only the ones your filters are showing.")
                    .font(.mono(12))
                    .foregroundStyle(Theme.table.muted)
            }
            if c.left + c.other > 0 {
                Text("\(c.left + c.other) that aren't red will be left alone.")
                    .font(.mono(12))
                    .foregroundStyle(Theme.table.muted)
            }
            HStack(spacing: 18) {
                Button("Keep reviewing") { dismiss() }.buttonStyle(.text)
                Spacer()
                if !session.finishTrashOnly {
                    Button("Move to “_Rejected”") { run(.folder) }.buttonStyle(.text).disabled(working)
                }
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
/// Files whose metadata couldn't be read, and why.
private struct FolderProblemsView: View {
    let session: FolderCullSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unreadable metadata").font(.display(30, weight: 800, width: 70))
            Text("BestShot won't write to these, so nothing in them can be lost. Fix or remove the file, then reopen the folder.")
                .font(.mono(12))
                .foregroundStyle(Theme.table.muted)
            ScrollView {
                Text(session.problems.map(\.message).joined(separator: "\n"))
                    .font(.mono(11))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            HStack { Spacer(); Button("Close") { dismiss() }.buttonStyle(.pill) }
        }
        .padding(28)
        .frame(width: 520)
        .tableSurface()
    }
}
#endif
