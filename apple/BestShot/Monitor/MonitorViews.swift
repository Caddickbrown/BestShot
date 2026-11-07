import SwiftUI

/// Sizes come off the panel, so a desk monitor and a TV across the room both read.
struct MonitorMetrics {
    let text: CGFloat
    let title: CGFloat
    let caption: CGFloat
    let padding: CGFloat
    /// The photo's longest side in pixels, for asking Photos for the right size.
    let photoEdge: CGFloat

    init(size: CGSize, scale: Double, pixels: CGFloat) {
        let height = max(size.height, 320)
        text = min(34, max(12, height * 0.0175 * scale))
        title = text * 1.6
        caption = max(10, text * 0.8)
        // TVs overscan and monitors have bezels; keep well inside both.
        padding = max(20, min(size.width, size.height) * 0.03)
        photoEdge = max(size.width, size.height) * pixels
    }
}

/// What the monitor draws. Nothing here can be touched: the keys go through
/// `MonitorDesk`, and this only shows what it says.
struct MonitorRoot: View {
    let desk: MonitorDesk
    @Environment(\.displayScale) private var pixels
    @Environment(\.colorScheme) private var system
    @AppStorage(Appearance.key) private var appearance = Appearance.fallback

    var body: some View {
        GeometryReader { geo in
            let metrics = MonitorMetrics(size: geo.size, scale: desk.textScale, pixels: pixels)
            let palette = desk.isJudging ? Theme.viewfinder : Theme.table
            VStack(spacing: 0) {
                // A photo, a list or a name only ever draw down the last branch.
                if desk.isLocked {
                    MonitorNotice(title: "BestShot", line: "Unlock your phone and open BestShot to continue.",
                                  palette: Theme.viewfinder, metrics: metrics)
                } else if desk.isPaused {
                    MonitorNotice(title: "Paused", line: "esc or ⌥⌘P to resume", palette: Theme.viewfinder, metrics: metrics)
                    MonitorHintBar(keys: desk.keys, palette: Theme.viewfinder, metrics: metrics)
                } else {
                    MonitorScreen(desk: desk, palette: palette, metrics: metrics, size: geo.size)
                        .overlay { MonitorOverlayView(desk: desk, palette: palette, metrics: metrics) }
                    MonitorHintBar(keys: desk.keys, palette: palette, metrics: metrics)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(backdrop(palette).ignoresSafeArea())
            .onChange(of: metrics.photoEdge, initial: true) { _, edge in desk.photoEdge = edge }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, desk.isLocked || desk.isPaused || desk.isJudging ? .dark : appearance.scheme ?? system)
    }

    private func backdrop(_ palette: Theme.Palette) -> Color {
        desk.isLocked || desk.isPaused ? .black : palette.background
    }
}

private struct MonitorNotice: View {
    let title: String
    let line: String
    let palette: Theme.Palette
    let metrics: MonitorMetrics

    var body: some View {
        VStack(spacing: metrics.text * 0.6) {
            Text(title)
                .font(.display(metrics.title * 1.6, weight: 800, width: 70))
                .foregroundStyle(palette.ink)
            Text(line)
                .font(.mono(metrics.text))
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The hint bar. It draws `desk.keys`, the table `handle` runs from, so it can't
/// list a key that doesn't work or leave one out.
struct MonitorHintBar: View {
    let keys: [MonitorBinding]
    let palette: Theme.Palette
    let metrics: MonitorMetrics

    var body: some View {
        VStack(spacing: 0) {
            HairlineRule(palette: palette)
            FlowLayout(spacing: metrics.caption * 1.2) {
                ForEach(keys) { key in
                    HStack(spacing: metrics.caption * 0.4) {
                        Text(key.keys).foregroundStyle(palette.ink)
                        Text(key.label).foregroundStyle(palette.muted)
                    }
                    .font(.mono(metrics.caption))
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.padding)
            .padding(.vertical, metrics.caption * 0.6)
        }
    }
}

private struct MonitorScreen: View {
    let desk: MonitorDesk
    let palette: Theme.Palette
    let metrics: MonitorMetrics
    let size: CGSize

    var body: some View {
        switch desk.pane {
        case .loupe:
            MonitorLoupe(desk: desk, metrics: metrics)
        case .grid:
            MonitorGrid(desk: desk, metrics: metrics, width: size.width)
        case .rankCompare:
            MonitorRankCompare(desk: desk, metrics: metrics)
        case .mediaPhoto:
            MonitorMediaPhoto(desk: desk, metrics: metrics)
        case .organise:
            HStack(spacing: 0) {
                if let photo = desk.library.organisePhoto {
                    desk.library.picture(photo, longEdge: metrics.photoEdge, fill: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(metrics.padding)
                }
                Rectangle().fill(palette.rule).frame(width: 1)
                MonitorList(desk: desk, title: "Organise", caption: desk.library.organiseProgress, palette: palette, metrics: metrics)
                    .frame(width: size.width * 0.32)
            }
        default:
            MonitorList(desk: desk, title: title, caption: caption, palette: palette, metrics: metrics)
        }
    }

    private var title: String {
        switch desk.pane {
        case .filters: return "Filters"
        case .rank: return "Rank"
        case .organiseHome: return "Organise"
        case .media(let project):
            guard let project else { return "All Media" }
            return desk.library.projects.first { $0.id == project }?.name ?? "Project"
        case .projects: return "Projects"
        case .settings: return "Settings"
        default: return "Triage"
        }
    }

    private var caption: String {
        if let notice = desk.notice { return notice }
        if let warning = desk.marks.warning { return warning }
        switch desk.pane {
        case .media: return desk.mediaItems.isEmpty ? "Nothing here yet" : "\(desk.mediaItems.count) items, to look at. Importing and tags are on the phone."
        default: return ""
        }
    }
}

// MARK: - Lists

/// Every list on the monitor. The lit row stays in view however it got there.
struct MonitorList: View {
    let desk: MonitorDesk
    let title: String
    let caption: String
    let palette: Theme.Palette
    let metrics: MonitorMetrics

    var body: some View {
        let rows = desk.rows
        let lit = desk.litRowID
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: metrics.caption * 0.3) {
                Text(title)
                    .font(.display(metrics.title * 1.5, weight: 800, width: 70))
                    .foregroundStyle(palette.ink)
                if !caption.isEmpty {
                    Text(caption).font(.mono(metrics.caption)).foregroundStyle(palette.muted)
                }
            }
            .padding(.horizontal, metrics.padding)
            .padding(.top, metrics.padding)
            .padding(.bottom, metrics.caption)
            HairlineRule(palette: palette)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if let group = row.group, index == 0 || rows[index - 1].group != group {
                                Text(group)
                                    .font(.mono(metrics.caption, medium: true))
                                    .foregroundStyle(palette.dim)
                                    .padding(.horizontal, metrics.padding)
                                    .padding(.top, metrics.text)
                                    .padding(.bottom, metrics.caption * 0.4)
                            }
                            rowView(row, isLit: row.id == lit)
                                .id(row.id)
                        }
                    }
                    .padding(.bottom, metrics.padding)
                }
                .onChange(of: lit, initial: true) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rowView(_ row: MonitorRow, isLit: Bool) -> some View {
        let height = metrics.text * 3
        return HStack(spacing: metrics.text * 0.7) {
            if let isOn = row.isOn {
                Text(isOn ? "●" : "○")
                    .font(.mono(metrics.text))
                    .foregroundStyle(isLit ? palette.accentInk : isOn ? palette.accent : palette.dim)
            }
            if let photo = row.photo {
                desk.library.picture(photo, longEdge: 300, fill: true)
                    .frame(width: height, height: height)
                    .clipped()
            }
            Text(row.title)
                .font(.mono(metrics.text, medium: isLit))
                .foregroundStyle(isLit ? palette.accentInk : palette.ink)
                .lineLimit(1)
            Spacer(minLength: metrics.text)
            if let detail = row.detail {
                Text(detail)
                    .font(.mono(metrics.caption))
                    .foregroundStyle(isLit ? palette.accentInk : palette.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, metrics.padding)
        .padding(.vertical, metrics.caption * 0.45)
        .frame(minHeight: row.photo == nil ? metrics.text * 2.2 : height + metrics.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isLit ? palette.accent : .clear)
    }
}

// MARK: - The photo

private struct MonitorLoupe: View {
    let desk: MonitorDesk
    let metrics: MonitorMetrics

    private var palette: Theme.Palette { Theme.viewfinder }

    var body: some View {
        VStack(spacing: 0) {
            if let current = desk.current {
                GeometryReader { geo in
                    HStack(spacing: metrics.caption) {
                        if let pinned = desk.pinned {
                            photo(pinned, in: CGSize(width: (geo.size.width - metrics.caption) / 2, height: geo.size.height))
                        }
                        photo(current, in: CGSize(width: desk.pinned == nil ? geo.size.width : (geo.size.width - metrics.caption) / 2,
                                                  height: geo.size.height))
                    }
                }
                HairlineRule(palette: palette)
                HStack(alignment: .top, spacing: metrics.padding) {
                    if let pinned = desk.pinned {
                        MonitorMarkStrip(desk: desk, id: pinned, metrics: metrics)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    MonitorMarkStrip(desk: desk, id: current, metrics: metrics)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let line = statusLine {
                        Text(line).font(.mono(metrics.caption)).foregroundStyle(palette.muted)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, metrics.padding)
                .padding(.vertical, metrics.caption * 0.8)
            } else {
                MonitorNotice(title: "Nothing here", line: "No photo matches the filters. f to change them.",
                              palette: palette, metrics: metrics)
            }
        }
    }

    private func photo(_ id: String, in size: CGSize) -> some View {
        let reach = CGSize(width: size.width * (desk.zoom - 1) / 2, height: size.height * (desk.zoom - 1) / 2)
        return desk.library.picture(id, longEdge: metrics.photoEdge * min(desk.zoom, 2), fill: false)
            .frame(width: size.width, height: size.height)
            .scaleEffect(desk.zoom)
            .offset(x: -desk.pan.x * reach.width, y: -desk.pan.y * reach.height)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private var statusLine: String? {
        guard let position = desk.position else { return nil }
        var parts = ["\(position.at) / \(position.of)"]
        let waiting = desk.library.triageWaiting
        if waiting > 0 { parts.append("\(waiting) to delete") }
        if desk.filter.isActive { parts.append("filtered") }
        if desk.zoom > 1 { parts.append("\(Int(desk.zoom))×") }
        if let notice = desk.notice { parts.append(notice) }
        if let warning = desk.marks.warning { parts.append(warning) }
        if desk.showInfo, let current = desk.current { parts += desk.library.details(current) }
        return parts.joined(separator: "  ·  ")
    }
}

/// A photo's stars, colour and tags.
struct MonitorMarkStrip: View {
    let desk: MonitorDesk
    let id: String
    let metrics: MonitorMetrics

    private var palette: Theme.Palette { Theme.viewfinder }

    var body: some View {
        let mark = desk.marks.mark(id)
        let colour = desk.colour(id)
        HStack(spacing: metrics.text) {
            HStack(spacing: metrics.caption * 0.5) {
                Rectangle()
                    .fill(colour.map(Theme.label) ?? .clear)
                    .overlay(Rectangle().stroke(palette.rule, lineWidth: 1))
                    .frame(width: metrics.text, height: metrics.text)
                Text(colour.map { desk.library.labelName($0) } ?? "No colour")
                    .foregroundStyle(colour == nil ? palette.dim : palette.ink)
            }
            Text(starText(mark.rating)).foregroundStyle(mark.rating > 0 ? palette.ink : palette.dim)
            if desk.library.isFavourite(id) { Text("♥").foregroundStyle(palette.accent) }
            if !mark.tags.isEmpty {
                Text(mark.tags.joined(separator: "  ")).foregroundStyle(palette.muted).lineLimit(1)
            }
        }
        .font(.mono(metrics.text))
    }
}

private struct MonitorMediaPhoto: View {
    let desk: MonitorDesk
    let metrics: MonitorMetrics

    var body: some View {
        if desk.mediaItems.indices.contains(desk.mediaIndex) {
            let item = desk.mediaItems[desk.mediaIndex]
            VStack(spacing: 0) {
                desk.library.picture(item.id, longEdge: metrics.photoEdge, fill: false)
                    .id(item.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HairlineRule(palette: Theme.viewfinder)
                HStack {
                    Text(item.title).foregroundStyle(Theme.viewfinder.ink)
                    Text(item.tags.joined(separator: "  ")).foregroundStyle(Theme.viewfinder.muted)
                    Spacer()
                    Text("\(desk.mediaIndex + 1) / \(desk.mediaItems.count)").foregroundStyle(Theme.viewfinder.muted)
                }
                .font(.mono(metrics.text))
                .lineLimit(1)
                .padding(.horizontal, metrics.padding)
                .padding(.vertical, metrics.caption * 0.8)
            }
        }
    }
}

private struct MonitorGrid: View {
    let desk: MonitorDesk
    let metrics: MonitorMetrics
    let width: CGFloat

    var body: some View {
        let columns = max(3, Int(width / (metrics.text * 11)))
        let ids = desk.library.triageIDs
        let shown = desk.visible
        let current = desk.current
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                    ForEach(shown, id: \.self) { index in
                        tile(ids[index], isLit: ids[index] == current)
                            .id(ids[index])
                    }
                }
                .padding(metrics.padding)
            }
            .onChange(of: current, initial: true) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .onChange(of: columns, initial: true) { _, count in desk.gridColumns = count }
    }

    private func tile(_ id: String, isLit: Bool) -> some View {
        Theme.table.tile
            .aspectRatio(1, contentMode: .fit)
            .overlay { desk.library.picture(id, longEdge: 400, fill: true) }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if let colour = desk.colour(id) {
                    Rectangle().fill(Theme.label(colour))
                        .frame(width: metrics.text, height: metrics.text)
                }
            }
            .overlay(alignment: .bottomLeading) {
                let rating = desk.marks.mark(id).rating
                if rating > 0 {
                    Text(String(repeating: "★", count: rating))
                        .font(.mono(metrics.caption))
                        .foregroundStyle(Theme.viewfinder.ink)
                        .padding(.horizontal, 4)
                        .background(Color.black.opacity(0.6))
                }
            }
            .overlay { Rectangle().stroke(isLit ? Theme.table.accent : .clear, lineWidth: 4) }
    }
}

private struct MonitorRankCompare: View {
    let desk: MonitorDesk
    let metrics: MonitorMetrics

    var body: some View {
        if let board = desk.board, let run = board.compare {
            VStack(spacing: 0) {
                if let pair = run.pair {
                    HStack(spacing: metrics.caption) {
                        board.media.fullImage(pair.left).id(pair.left).frame(maxWidth: .infinity, maxHeight: .infinity)
                        board.media.fullImage(pair.right).id(pair.right).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    HairlineRule(palette: Theme.viewfinder)
                    Text("Which is better? \(run.progress.asked) asked")
                        .font(.mono(metrics.text))
                        .foregroundStyle(Theme.viewfinder.muted)
                        .padding(metrics.caption)
                } else {
                    MonitorNotice(title: "Done", line: "esc saves the order.", palette: Theme.viewfinder, metrics: metrics)
                }
            }
        }
    }
}

// MARK: - On top

private struct MonitorOverlayView: View {
    let desk: MonitorDesk
    let palette: Theme.Palette
    let metrics: MonitorMetrics

    var body: some View {
        switch desk.overlay {
        case .palette(let menu): panel(palette(for: menu))
        case .entry(let entry): panel(entryView(entry))
        case .finish(let finish): panel(finishView(finish))
        case .help: panel(helpView)
        case nil: EmptyView()
        }
    }

    private var sheet: Theme.Palette { Theme.viewfinder }

    private func panel(_ content: some View) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.55)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: metrics.text * 44, alignment: .leading)
                .background(sheet.paper)
                .overlay(Rectangle().stroke(sheet.rule, lineWidth: 1))
                .padding(.top, metrics.padding * 2)
                .padding(.horizontal, metrics.padding)
        }
        .environment(\.colorScheme, .dark)
    }

    private func line(_ text: String, detail: String? = nil, isLit: Bool) -> some View {
        HStack {
            Text(text).font(.mono(metrics.text, medium: isLit))
                .foregroundStyle(isLit ? sheet.accentInk : sheet.ink)
            Spacer(minLength: metrics.text)
            if let detail {
                Text(detail).font(.mono(metrics.caption)).foregroundStyle(isLit ? sheet.accentInk : sheet.muted)
            }
        }
        .padding(.horizontal, metrics.text)
        .padding(.vertical, metrics.caption * 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isLit ? sheet.accent : .clear)
    }

    private func palette(for menu: MonitorPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(menu.query.isEmpty ? "Type where to go, or what to do" : menu.query)
                .font(.mono(metrics.title))
                .foregroundStyle(menu.query.isEmpty ? sheet.dim : sheet.ink)
                .padding(metrics.text)
            HairlineRule(palette: sheet)
            if menu.rows.isEmpty {
                Text("Nothing matches").font(.mono(metrics.text)).foregroundStyle(sheet.muted).padding(metrics.text)
            }
            ForEach(menu.rows) { row in
                line(row.title, detail: row.detail, isLit: row.id == menu.selected)
            }
        }
    }

    private func entryView(_ entry: MonitorEntry) -> some View {
        VStack(alignment: .leading, spacing: metrics.caption) {
            Text(entry.title).font(.mono(metrics.caption)).foregroundStyle(sheet.muted)
            Text(entry.text.isEmpty ? " " : entry.text + "▏")
                .font(.mono(metrics.title))
                .foregroundStyle(sheet.ink)
            if !entry.suggestions.isEmpty {
                Text(entry.suggestions.joined(separator: "   "))
                    .font(.mono(metrics.caption))
                    .foregroundStyle(sheet.muted)
                    .lineLimit(1)
            }
        }
        .padding(metrics.text)
    }

    private func finishView(_ finish: MonitorFinish) -> some View {
        let waiting = desk.library.triageWaiting
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: metrics.caption * 0.5) {
                Text("Finish Triage").font(.display(metrics.title * 1.3, weight: 800, width: 70)).foregroundStyle(sheet.ink)
                Text(summary(waiting, finish)).font(.mono(metrics.text)).foregroundStyle(sheet.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(metrics.text)
            HairlineRule(palette: sheet)
            ForEach(Array(finish.choices.enumerated()), id: \.offset) { _, choice in
                line(title(choice, waiting), isLit: choice == finish.chosen)
            }
            Spacer().frame(height: metrics.caption)
        }
    }

    private func summary(_ waiting: Int, _ finish: MonitorFinish) -> String {
        if finish.isDeleting { return "Confirm on your phone. iOS asks there." }
        if let message = finish.message { return message }
        if waiting == 0 { return "Nothing marked to delete." }
        return "\(waiting == 1 ? "1 photo goes" : "\(waiting) photos go") to Recently Deleted, recoverable for 30 days. iOS asks on the phone first."
    }

    private func title(_ choice: MonitorFinish.Choice, _ waiting: Int) -> String {
        switch choice {
        case .delete: return "Delete \(waiting) photo\(waiting == 1 ? "" : "s")"
        case .finish: return "Finish"
        case .keepGoing: return "Keep triaging"
        }
    }

    private var helpView: some View {
        let keys = desk.pageKeys
        return VStack(alignment: .leading, spacing: 0) {
            Text("All keys").font(.display(metrics.title * 1.3, weight: 800, width: 70)).foregroundStyle(sheet.ink)
                .padding(metrics.text)
            HairlineRule(palette: sheet)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                            line(key.keys, detail: key.label, isLit: index == desk.helpRow).id(index)
                        }
                    }
                }
                .frame(maxHeight: metrics.text * 30)
                .onChange(of: desk.helpRow) { _, row in proxy.scrollTo(row, anchor: .center) }
            }
        }
    }
}
