import SwiftUI

/// The ⌘K panel in BestShot's look: the same on the phone and the monitor,
/// sized by `text`. The kit decides what's in it and what the keys do; this
/// only draws `menu`. No cap on the rows: it scrolls, and the lit row stays in view.
struct CommandPanel: View {
    let menu: CommandPalette<BestShotCommandList>
    var palette = Theme.table
    var text: CGFloat = 16
    var caption: CGFloat = 12
    var rowHeight: CGFloat = 48
    /// Opened by touch: rows take taps, with a back and a close button.
    var touch = false
    /// The monitor has its own hint bar for these.
    var showsKeys = false
    var choose: (String) -> Void = { _ in }
    var hover: (String) -> Void = { _ in }
    var back: () -> Void = {}
    var close: () -> Void = {}

    private var red: Color { Theme.label(.red) }

    var body: some View {
        VStack(spacing: 0) {
            field
            HairlineRule(palette: palette)
            if menu.rows.isEmpty {
                Text(menu.nothing).font(.mono(text)).foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(text)
            } else {
                list
            }
            if showsKeys {
                HairlineRule(palette: palette)
                keys
            }
        }
        .background(palette.paper)
        .overlay(Rectangle().stroke(palette.rule, lineWidth: 1))
    }

    private var field: some View {
        HStack(spacing: text * 0.5) {
            if touch && menu.depth > 0 {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: text, weight: .medium))
                        .foregroundStyle(palette.accent).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Image(systemName: menu.isAsking ? "character.cursor.ibeam" : "magnifyingglass")
                    .font(.system(size: text * 0.9)).foregroundStyle(palette.muted)
            }
            if let opener = menu.opener {
                Text(opener.title).font(.mono(text, medium: true)).foregroundStyle(palette.accent)
                    .lineLimit(1).fixedSize()
            }
            HStack(spacing: 1) {
                if !menu.query.isEmpty {
                    Text(menu.query).font(.mono(text * 1.15)).foregroundStyle(palette.ink)
                        .lineLimit(1).truncationMode(.head)
                }
                Caret(font: .mono(text * 1.15), color: palette.accent)
                if menu.query.isEmpty {
                    Text(menu.prompt).font(.mono(text * 1.15)).foregroundStyle(palette.dim).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if touch {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: text * 0.9, weight: .medium))
                        .foregroundStyle(palette.muted).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, text * 0.9)
        .frame(minHeight: text * 3.2)
    }

    /// Tall enough for the capped number of rows and the headings among them.
    private var listHeight: CGFloat {
        let headings: Int = menu.sections.filter { $0.title != nil }.count
        let rows: CGFloat = CGFloat(min(menu.rows.count, CommandPaletteLimit.rows))
        return rows * rowHeight + CGFloat(headings) * caption * 2.4
    }

    private var list: some View {
        ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(menu.sections) { (section: CommandSection<BestShotCommand>) in
                        sectionView(section)
                    }
                }
            }
            .frame(maxHeight: listHeight)
            .onAppear { if let id = menu.selected { proxy.scrollTo(id) } }
            .onChange(of: menu.selected) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: CommandSection<BestShotCommand>) -> some View {
        if let title = section.title {
            Text(title.uppercased()).font(.mono(caption, medium: true)).foregroundStyle(palette.muted)
                .lineLimit(1)
                .padding(.horizontal, text).padding(.top, caption * 0.9).padding(.bottom, caption * 0.3)
                .accessibilityAddTraits(.isHeader)
        }
        ForEach(section.rows) { (row: CommandRow<BestShotCommand>) in
            rowButton(row)
        }
    }

    private func rowButton(_ row: CommandRow<BestShotCommand>) -> some View {
        Button { choose(row.id) } label: {
            rowView(row, lit: row.id == menu.selected).frame(height: rowHeight)
        }
        .buttonStyle(.plain)
        .onHover { (inside: Bool) in if inside { hover(row.id) } }
        .id(row.id)
    }

    private func rowView(_ row: CommandRow<BestShotCommand>, lit: Bool) -> some View {
        let ink = lit ? palette.accentInk : row.destructive ? red : palette.ink
        let quiet = lit ? palette.accentInk : palette.muted
        return HStack(spacing: text * 0.7) {
            Image(systemName: row.symbol).font(.system(size: text * 0.95))
                .foregroundStyle(lit ? palette.accentInk : row.destructive ? red : symbolTint(row))
                .frame(width: text * 1.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.mono(text, medium: lit)).foregroundStyle(ink).lineLimit(1)
                if let detail = row.detail {
                    Text(detail).font(.mono(caption)).foregroundStyle(quiet).lineLimit(1)
                }
            }
            Spacer(minLength: text * 0.5)
            if let state = row.state {
                Text(state).font(.mono(caption)).foregroundStyle(row.isOn == true && !lit ? palette.accent : quiet)
            }
            if row.isCurrent {
                Image(systemName: "checkmark").font(.system(size: text * 0.85, weight: .semibold))
                    .foregroundStyle(lit ? palette.accentInk : palette.accent)
                    .accessibilityLabel("Current")
            }
            if row.leads {
                Image(systemName: "chevron.right").font(.system(size: text * 0.75)).foregroundStyle(quiet)
            }
        }
        .padding(.horizontal, text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(lit ? palette.accent : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.state ?? "")
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    /// A colour label's row shows its colour.
    private func symbolTint(_ row: CommandRow<BestShotCommand>) -> Color {
        if case .run(.colour(let colour)) = row.step { return Theme.label(colour) }
        return palette.muted
    }

    private var keys: some View {
        FlowLayout(spacing: caption * 1.2) {
            ForEach(menu.hints) { hint in
                HStack(spacing: caption * 0.4) {
                    Text(hint.key).foregroundStyle(palette.ink)
                    Text(hint.label).foregroundStyle(palette.muted)
                }
                .font(.mono(caption))
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, text)
        .padding(.vertical, caption * 0.6)
    }
}

/// The text cursor, drawn: a bar a line high in the field's font. A typed "▏"
/// or "|" takes a letter's width and leaves a gap beside the text (kit 0.9.1).
struct Caret: View {
    let font: Font
    let color: Color
    var width: CGFloat = 2

    var body: some View {
        Text("Ag").font(font).hidden()
            .frame(width: width)
            .overlay(Rectangle().fill(color))
            .accessibilityHidden(true)
    }
}
