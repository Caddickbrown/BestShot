import SwiftUI

/// The single primary action on a screen: a grease-pencil red pill.
struct PillButtonStyle: ButtonStyle {
    var palette: Theme.Palette = Theme.table

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(14, medium: true))
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
            .font(.mono(13))
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 4)], spacing: 4) {
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
