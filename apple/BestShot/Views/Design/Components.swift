import SwiftUI

/// The single primary action on a screen: a grease-pencil red pill.
struct PillButtonStyle: ButtonStyle {
    var palette: Theme.Palette = Theme.table

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pill)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(palette.accentInk)
            .background(palette.accent.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Secondary actions are plain text, never boxed.
struct TextButtonStyle: ButtonStyle {
    var palette: Theme.Palette = Theme.table
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.note)
            .foregroundStyle(destructive ? palette.accent : palette.ink)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var viewfinderPill: PillButtonStyle { PillButtonStyle(palette: Theme.viewfinder) }
}

extension ButtonStyle where Self == TextButtonStyle {
    static var text: TextButtonStyle { TextButtonStyle() }
    static var viewfinderText: TextButtonStyle { TextButtonStyle(palette: Theme.viewfinder) }
}

/// A small mono caps label, like the section rules on the light table.
struct SheetLabel: View {
    let text: String
    var palette: Theme.Palette = Theme.table

    init(_ text: String, palette: Theme.Palette = Theme.table) {
        self.text = text
        self.palette = palette
    }

    var body: some View {
        Text(text.uppercased())
            .font(.mono(11, medium: true))
            .tracking(1.6)
            .foregroundStyle(palette.dim)
    }
}

/// A hairline rule across the table.
struct HairlineRule: View {
    var palette: Theme.Palette = Theme.table
    var body: some View {
        Rectangle().fill(palette.rule).frame(height: 1)
    }
}

/// An edge-to-edge contact sheet: square cells with 4pt gaps, no rounding.
struct ContactSheet<Data: RandomAccessCollection, Cell: View>: View where Data.Element: Identifiable {
    let data: Data
    var minimum: CGFloat = 150
    @ViewBuilder let cell: (Data.Element) -> Cell

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: Theme.Space.gutter)], spacing: Theme.Space.gutter) {
            ForEach(data) { element in
                cell(element)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
            }
        }
    }
}

/// A print mounted on paper, with room for a caption under the image.
struct PrintMount<Content: View, Caption: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let caption: () -> Caption

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.table.tile)
                .clipped()
            caption()
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 2, trailing: 8))
        .background(Theme.table.paper)
    }
}

// MARK: - Shared parts, from Rank

/// A secondary action that needs an edge: a hairline capsule round plain text.
/// Rank's Compare has one for Save & exit.
struct OutlineButtonStyle: ButtonStyle {
    var palette: Theme.Palette = Theme.table

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.note)
            .foregroundStyle(palette.ink)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .overlay(Capsule().stroke(palette.rule, lineWidth: 1))
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
    static var viewfinderOutline: OutlineButtonStyle { OutlineButtonStyle(palette: Theme.viewfinder) }
}

/// The top of a screen, as Rank's: a small line, the name in Archivo, the counts
/// on the right, anything else under them, then a hairline.
struct ScreenHeader<Accessory: View>: View {
    var eyebrow: String?
    let title: String
    var status: String?
    var palette: Theme.Palette = Theme.table
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        #if os(iOS)
        // The title lives in the navigation bar, centred, in the row with Back
        // and the bar's buttons. Drawn below the bar it either left an empty
        // band or, pulled up into it, was clipped (Dan, 13 Nov). Only what
        // doesn't fit in the bar stays here: the status and any accessory.
        VStack(spacing: 0) {
            if status != nil || Accessory.self != EmptyView.self {
                VStack(alignment: .leading, spacing: Theme.Space.stack) {
                    if let status {
                        Text(status)
                            .font(.eyebrow)
                            .foregroundStyle(palette.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    accessory()
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, Theme.Space.stack)
            }
            HairlineRule(palette: palette)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                BarTitle(eyebrow: eyebrow, title: title, palette: palette)
            }
        }
        #else
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.stack) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: Theme.Space.eyebrowGap) {
                        if let eyebrow {
                            Text(eyebrow)
                                .font(.eyebrow)
                                .lineLimit(1)
                                .foregroundStyle(palette.muted)
                        }
                        Text(title)
                            .font(.screenTitle)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer()
                    if let status {
                        Text(status)
                            .font(.eyebrow)
                            .foregroundStyle(palette.muted)
                    }
                }
                accessory()
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.top, Theme.Space.headerTop)
            .padding(.bottom, Theme.Space.headerBottom)
            HairlineRule(palette: palette)
        }
        #endif
    }
}

/// A screen's name in the navigation bar: the small line over the title, both
/// centred, sized to fit the bar's row.
struct BarTitle: View {
    var eyebrow: String?
    let title: String
    var palette: Theme.Palette = Theme.table

    var body: some View {
        VStack(spacing: 1) {
            if let eyebrow, !eyebrow.isEmpty {
                Text(eyebrow)
                    .font(.eyebrow)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }
            Text(title)
                .font(.barTitle)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: 240)
    }
}

extension ScreenHeader where Accessory == EmptyView {
    init(eyebrow: String? = nil, title: String, status: String? = nil, palette: Theme.Palette = Theme.table) {
        self.init(eyebrow: eyebrow, title: title, status: status, palette: palette) { EmptyView() }
    }
}

/// Nothing to show, or something to ask first: a heading and a line, centred,
/// with any buttons under them.
struct EmptyState<Actions: View>: View {
    let title: String
    var message: String?
    var palette: Theme.Palette = Theme.table
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: Theme.Space.stack) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.note)
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            if Actions.self != EmptyView.self {
                VStack(spacing: Theme.Space.stack) { actions() }
                    .padding(.top, 6)
            }
        }
        .padding(Theme.Space.panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(_ title: String, message: String? = nil, palette: Theme.Palette = Theme.table) {
        self.init(title: title, message: message, palette: palette) { EmptyView() }
    }
}

/// A section of a system Form or List set like the sheet: a mono label over
/// rows on paper.
struct TableSection<Content: View, Footer: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        Section {
            content().listRowBackground(Theme.table.paper)
        } header: {
            if let title { SheetLabel(title) }
        } footer: {
            footer()
        }
    }
}

extension TableSection where Footer == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, content: content) { EmptyView() }
    }
}

/// Small print in a form or under a control.
struct FormNote: View {
    let text: String
    var palette: Theme.Palette = Theme.table

    init(_ text: String, palette: Theme.Palette = Theme.table) {
        self.text = text
        self.palette = palette
    }

    var body: some View {
        Text(text)
            .font(.eyebrow)
            .foregroundStyle(palette.muted)
    }
}

/// A bar along the bottom with the screen's one main action, over a hairline.
struct BottomBar<Content: View>: View {
    var palette: Theme.Palette = Theme.table
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 6) { content() }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, Theme.Space.stack)
            .frame(maxWidth: .infinity)
            .background(palette.background)
            .overlay(alignment: .top) { HairlineRule(palette: palette) }
    }
}

/// How far through: a hairline that fills with ink.
struct ProgressLine: View {
    let value: Double
    var palette: Theme.Palette = Theme.table

    var body: some View {
        GeometryReader { geo in
            Rectangle().fill(palette.rule)
                .overlay(alignment: .leading) {
                    Rectangle().fill(palette.ink).frame(width: geo.size.width * min(1, max(0, value)))
                }
        }
        .frame(height: 2)
        .accessibilityElement()
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

/// A rank, as Rank writes it on a print: the top three in red, the first ringed.
struct RankNumber: View {
    let rank: Int
    var palette: Theme.Palette = Theme.table

    var body: some View {
        Text("\(rank)")
            .font(.heading(rank <= 3 ? 20 : 17))
            .foregroundStyle(rank <= 3 ? palette.accent : palette.ink)
            .background(alignment: .center) {
                if rank == 1 {
                    GreasePencilMark(shape: .circle, color: palette.accent, lineWidth: 2)
                        .frame(width: 34, height: 30)
                }
            }
    }
}
