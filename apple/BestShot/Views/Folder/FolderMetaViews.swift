#if os(macOS)
import SwiftUI

/// A photo's stars as text: `★★★☆☆`.
func starText(_ rating: Int8) -> String {
    let filled = Int(max(0, min(rating, 5)))
    return String(repeating: "★", count: filled) + String(repeating: "☆", count: 5 - filled)
}

/// What a row's label should say: its text in the file, or the name of an
/// implied colour.
@MainActor
func labelText(_ row: MetaRow) -> String? {
    if let label = row.label { return label }
    return row.colour.map { LabelStore.shared.name($0) }
}

/// Label and stars over the photo in the loupe.
struct LoupeMetaBadge: View {
    let row: MetaRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let text = labelText(row) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(row.colour.map(Theme.label) ?? .clear)
                            .overlay(Circle().stroke(Theme.viewfinder.muted, lineWidth: row.colour == nil ? 1 : 0))
                            .frame(width: 12, height: 12)
                        Text(row.implied ? "\(text) (saved decision)" : text)
                            .font(.mono(13, medium: true))
                    }
                }
                if row.rating > 0 {
                    Text(starText(row.rating)).font(.system(size: 16))
                } else if row.rating < 0 {
                    Text("Rejected in Bridge").font(.mono(12))
                }
            }
            if !row.keywords.isEmpty {
                Text(row.keywords.joined(separator: " · "))
                    .font(.mono(11))
                    .foregroundStyle(Theme.viewfinder.muted)
                    .lineLimit(1)
            }
            if let problem = row.problem {
                Text("⚠ \(problem)")
                    .font(.mono(11))
                    .foregroundStyle(Theme.viewfinder.accent)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(Theme.viewfinder.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.72))
        .overlay(alignment: .leading) {
            if let colour = row.colour { Rectangle().fill(Theme.label(colour)).frame(width: 4) }
        }
        .allowsHitTesting(false)
    }
}

/// Label band and stars along the bottom of a grid tile.
struct TileMetaBadge: View {
    let row: MetaRow

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if row.problem != nil {
                    Text("⚠").font(.system(size: 12))
                }
                if row.colour == nil, row.label != nil {
                    Text("●").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                if row.rating > 0 {
                    Text(String(repeating: "★", count: Int(row.rating)))
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                if row.rating != 0 || row.problem != nil || row.label != nil { Color.black.opacity(0.6) }
            }
            if let colour = row.colour {
                Rectangle().fill(Theme.label(colour)).frame(height: 7)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Filters and sort, above the grid and the loupe alike. Everything here
/// combines, and next and previous follow it.
struct FolderFilterBar: View {
    @Bindable var session: FolderCullSession
    let palette: Theme.Palette

    private static let statuses: [(ReviewStatus, String)] = [
        (.all, "All"), (.unreviewed, "Unreviewed"), (.keep, "Kept"), (.reject, "Rejected"),
    ]

    private static let sorts: [(FolderSort, String)] = [
        (.name, "Name"), (.newest, "Newest"), (.oldest, "Oldest"), (.stars, "Stars"), (.label, "Label"),
    ]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Self.statuses, id: \.1) { status, title in
                Button { session.filter.status = status } label: {
                    Text(title)
                        .font(.mono(12, medium: session.filter.status == status))
                        .foregroundStyle(session.filter.status == status ? palette.ink : palette.muted)
                }
                .buttonStyle(.plain)
            }
            rule
            starsMenu
            rule
            labelPicks
            rule
            keywordsMenu
            rule
            sortMenu
            Spacer(minLength: 8)
            Text(session.filter.isActive ? "\(session.visible.count) of \(session.items.count)" : "\(session.items.count)")
                .font(.mono(11))
                .foregroundStyle(palette.muted)
            if session.filter.isActive {
                Button("Clear") { session.filter = .all }
                    .buttonStyle(TextButtonStyle(palette: palette))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(palette.background)
        .overlay(alignment: .bottom) { HairlineRule(palette: palette) }
    }

    private var rule: some View {
        Rectangle().fill(palette.rule).frame(width: 1, height: 14)
    }

    private var starsTitle: String {
        switch session.filter.stars {
        case .any: return "Stars: any"
        case .atLeast(let n): return "Stars: \(n)+"
        case .exactly(let n): return n == 0 ? "Stars: none" : "Stars: \(n) only"
        }
    }

    private var starsMenu: some View {
        Menu {
            Button("Any") { session.filter.stars = .any }
            Section("At least") {
                ForEach(1...5, id: \.self) { n in
                    Button(String(repeating: "★", count: n)) { session.filter.stars = .atLeast(stars: UInt8(n)) }
                }
            }
            Section("Exactly") {
                Button("Unrated") { session.filter.stars = .exactly(stars: 0) }
                ForEach(1...5, id: \.self) { n in
                    Button(String(repeating: "★", count: n)) { session.filter.stars = .exactly(stars: UInt8(n)) }
                }
            }
        } label: {
            menuLabel(starsTitle, active: session.filter.stars != .any)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var labelPicks: some View {
        HStack(spacing: 7) {
            ForEach(LabelColour.allCases) { colour in
                let pick = LabelPick.colour(colour: colour)
                let on = session.filter.labels.contains(pick)
                Button { session.toggle(pick) } label: {
                    Circle()
                        .fill(Theme.label(colour))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(palette.ink, lineWidth: on ? 2 : 0).padding(-3))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Show \(LabelStore.shared.name(colour))")
            }
            pickText("None", .unlabelled, help: "Show photos with no label")
            pickText("Other", .other, help: "Show labels that aren't mapped to a colour")
        }
    }

    private func pickText(_ title: String, _ pick: LabelPick, help: String) -> some View {
        let on = session.filter.labels.contains(pick)
        return Button { session.toggle(pick) } label: {
            Text(title)
                .font(.mono(11, medium: on))
                .foregroundStyle(on ? palette.ink : palette.muted)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var keywordsTitle: String {
        switch session.filter.keywords.count {
        case 0: return "Keywords"
        case 1: return "Keyword: \(session.filter.keywords[0])"
        case let n: return "Keywords: \(n)"
        }
    }

    private var keywordsMenu: some View {
        Menu {
            if session.keywords.isEmpty {
                Text("No keywords in this folder yet")
            }
            ForEach(session.keywords, id: \.keyword) { item in
                Toggle(
                    "\(item.keyword) (\(item.count))",
                    isOn: Binding(
                        get: { session.filter.keywords.contains(item.keyword) },
                        set: { _ in session.toggleKeywordFilter(item.keyword) }
                    )
                )
            }
            if session.filter.keywords.count > 1 {
                Divider()
                Toggle("Match any, not all", isOn: $session.filter.anyKeyword)
            }
        } label: {
            menuLabel(keywordsTitle, active: !session.filter.keywords.isEmpty)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var sortMenu: some View {
        Menu {
            ForEach(Self.sorts, id: \.1) { sort, title in
                Button(title) { session.sort = sort }
            }
        } label: {
            menuLabel("Sort: \(Self.sorts.first { $0.0 == session.sort }?.1 ?? "")", active: session.sort != .name)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func menuLabel(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.mono(12, medium: active))
            .foregroundStyle(active ? palette.ink : palette.muted)
    }
}

/// The loupe's Keywords panel: what's on this photo, and quick-add from a
/// field or the folder's other keywords.
struct FolderKeywordPanel: View {
    @Bindable var session: FolderCullSession
    let row: MetaRow
    @State private var draft = ""
    @FocusState private var typing: Bool

    /// Folder keywords not on this photo, narrowed by what's been typed.
    private var suggestions: [String] {
        let onPhoto = Set(row.keywords.map { $0.lowercased() })
        let typed = draft.trimmingCharacters(in: .whitespaces).lowercased()
        return session.keywords
            .map(\.keyword)
            .filter { !onPhoto.contains($0.lowercased()) && (typed.isEmpty || $0.lowercased().contains(typed)) }
            .prefix(24)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetLabel("Keywords", palette: Theme.viewfinder)
            TextField("Add keyword", text: $draft)
                .textFieldStyle(.plain)
                .font(.mono(13))
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { HairlineRule(palette: Theme.viewfinder) }
                .focused($typing)
                .onSubmit(add)
                .onExitCommand { typing = false }
            Text("Return adds, commas separate, Esc goes back to the keys.")
                .font(.mono(10))
                .foregroundStyle(Theme.viewfinder.dim)

            if row.keywords.isEmpty {
                Text("None on this photo.")
                    .font(.mono(12))
                    .foregroundStyle(Theme.viewfinder.muted)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(row.keywords, id: \.self) { keyword in
                        Button { session.removeKeyword(keyword) } label: {
                            Text("\(keyword) ×")
                                .font(.mono(12))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.viewfinder.tile)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(keyword)")
                    }
                }
            }

            if !suggestions.isEmpty {
                SheetLabel("In this folder", palette: Theme.viewfinder)
                ScrollView {
                    FlowLayout(spacing: 6) {
                        ForEach(suggestions, id: \.self) { keyword in
                            Button { session.addKeyword(keyword) } label: {
                                Text("+ \(keyword)")
                                    .font(.mono(12))
                                    .foregroundStyle(Theme.viewfinder.muted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .overlay(Rectangle().stroke(Theme.viewfinder.rule, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.viewfinder.rule).frame(width: 1) }
        .onAppear { typing = true }
        .onChange(of: session.keywordFocusRequest) { typing = true }
        .onChange(of: typing) { _, now in session.typingKeyword = now }
        .onDisappear { session.typingKeyword = false }
    }

    private func add() {
        for keyword in draft.split(separator: ",") {
            session.addKeyword(String(keyword))
        }
        draft = ""
        typing = true
    }
}
#endif
