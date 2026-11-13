import SwiftUI

/// BestShot's mark, drawn from the same geometry as the app icon
/// (`scripts/make-icon.py`, a 2048 grid): a print with a hill and a red sun,
/// framed by the viewfinder's corners. In the app it sits on the table, so the
/// icon's own background is left out.
struct BrandMark: View {
    var palette: Theme.Palette = Theme.table

    var body: some View {
        Canvas { context, size in
            let k = min(size.width, size.height) / 2048
            func r(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
                CGRect(x: x0 * k, y: y0 * k, width: (x1 - x0) * k, height: (y1 - y0) * k)
            }
            let (x0, y0, x1, y1): (CGFloat, CGFloat, CGFloat, CGFloat) = (500, 560, 1548, 1488)
            // The print and its picture.
            context.fill(Path(roundedRect: r(x0, y0, x1, y1), cornerRadius: 26 * k), with: .color(palette.paper))
            context.stroke(Path(roundedRect: r(x0, y0, x1, y1), cornerRadius: 26 * k), with: .color(palette.rule), lineWidth: 1)
            context.fill(Path(r(x0 + 62, y0 + 62, x1 - 62, y1 - 62)), with: .color(palette.tile))
            var hill = Path()
            hill.move(to: CGPoint(x: (x0 + 62) * k, y: (y1 - 62) * k))
            for (x, y) in [(x0 + 400, y0 + 400), (x0 + 640, y0 + 610), (x0 + 770, y0 + 500), (x1 - 62, y1 - 62)] {
                hill.addLine(to: CGPoint(x: x * k, y: y * k))
            }
            hill.closeSubpath()
            context.fill(hill, with: .color(palette.ink))
            context.fill(Path(ellipseIn: r(x1 - 370, y0 + 150, x1 - 190, y0 + 330)), with: .color(palette.accent))
            // The viewfinder's corners.
            let (a, b, t, l): (CGFloat, CGFloat, CGFloat, CGFloat) = (300, 2048 - 300, 74, 300)
            for (cx, cy, sx, sy) in [(a, a, 1.0, 1.0), (b, a, -1, 1), (a, b, 1, -1), (b, b, -1, -1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                context.fill(Path(r(min(cx, cx + sx * l), min(cy, cy + sy * t), max(cx, cx + sx * l), max(cy, cy + sy * t))),
                             with: .color(palette.ink))
                context.fill(Path(r(min(cx, cx + sx * t), min(cy, cy + sy * l), max(cx, cx + sx * t), max(cy, cy + sy * l))),
                             with: .color(palette.ink))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The mark and the name, as the top of the main menu: the same parts as a
/// `ScreenHeader`, with the mark beside the name.
struct BrandHeader: View {
    var palette: Theme.Palette = Theme.table

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                BrandMark(palette: palette).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo triage")
                        .font(.eyebrow)
                        .foregroundStyle(palette.muted)
                    Text("BestShot")
                        .font(.screenTitle)
                        .foregroundStyle(palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.top, Theme.Space.headerTop)
            .padding(.bottom, Theme.Space.headerBottom)
            HairlineRule(palette: palette)
        }
        .background(palette.background)
    }
}
