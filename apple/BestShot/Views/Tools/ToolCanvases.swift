import SwiftUI

// What the Glue and Multi Crop editors draw, apart from their gestures, so the
// phone, the Mac and the monitor draw the same thing (Monitor Mode draws these
// from `ToolHolder`, with no gestures at all).

// MARK: - Multi Crop

/// The boxes over the image: outline, number chip, which edge is the top of
/// the output, and the focused box's handles. In canvas points (`scale` points
/// per image pixel).
struct MultiCropBoxesLayer: View {
    let session: MultiCropSession
    let scale: CGFloat
    /// A box being drawn, in image pixels.
    var drawing: CGRect?
    /// The monitor draws bigger chips.
    var chip: CGFloat = 24

    var body: some View {
        Canvas { context, _ in draw(&context) }
            .allowsHitTesting(false)
    }

    private func draw(_ context: inout GraphicsContext) {
        let numbers: [String: Int] = session.numbers
        let picked: [String]? = session.renumbering
        for box in session.edit.boxes {
            drawBox(box, in: &context, numbers: numbers, picked: picked)
        }
        if let r = drawing {
            let rect = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
            context.stroke(Path(rect), with: .color(Theme.table.accent), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }

    private func drawBox(_ box: CropBoxModel, in context: inout GraphicsContext, numbers: [String: Int], picked: [String]?) {
        let off: Bool = session.isOff(box.id)
        let focused: Bool = box.id == session.focused && picked == nil
        let ink: Color = off ? Theme.table.muted : Theme.table.accent
        let s: CGFloat = scale
        let q: [CGPoint] = box.quad.map { (p: CGPoint) -> CGPoint in CGPoint(x: p.x * s, y: p.y * s) }
        let fill: Double = focused ? 0.12 : (off ? 0.18 : 0.06)
        let dash: [CGFloat] = off ? [6, 4] : []
        var path = Path()
        path.addLines(q)
        path.closeSubpath()
        context.fill(path, with: .color(ink.opacity(fill)))
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: focused ? 2.5 : 1.5, dash: dash))
        // Which way is up for the output: a tick on its top edge.
        let top = Self.outputTop(box, q)
        var tick = Path()
        tick.move(to: top.0)
        tick.addLine(to: top.1)
        context.stroke(tick, with: .color(ink), lineWidth: 5)
        // The number it'll be saved as; while renumbering, its new number or "?".
        let (label, lit): (String, Bool) = chipLabel(box.id, off: off, numbers: numbers, picked: picked)
        let at = CGPoint(x: q[0].x + chip * 0.6, y: q[0].y + chip * 0.6)
        let disc = CGRect(x: at.x - chip / 2, y: at.y - chip / 2, width: chip, height: chip)
        if lit {
            context.fill(Path(ellipseIn: disc), with: .color(ink))
        } else {
            context.fill(Path(ellipseIn: disc), with: .color(Theme.table.tile))
            context.stroke(Path(ellipseIn: disc), with: .color(ink), lineWidth: 1.5)
        }
        context.draw(Text(label).font(.mono(chip * 0.55, medium: true)).foregroundColor(lit ? Theme.table.accentInk : ink), at: at)
        if focused {
            for p in q { context.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(ink)) }
            if box.rect {
                let r = Self.rotateHandle(box, scale: scale)
                context.stroke(Path { $0.move(to: Self.midTop(q)); $0.addLine(to: r) }, with: .color(ink), lineWidth: 1)
                context.fill(Path(ellipseIn: CGRect(x: r.x - 8, y: r.y - 8, width: 16, height: 16)), with: .color(ink))
            }
        }
    }

    private func chipLabel(_ id: String, off: Bool, numbers: [String: Int], picked: [String]?) -> (String, Bool) {
        if let picked {
            if let i = picked.firstIndex(of: id) { return ("\(i + 1)", true) }
            return (off ? "–" : "?", false)
        }
        if off { return ("–", true) }
        return (numbers[id].map(String.init) ?? "·", true)
    }

    static func midTop(_ q: [CGPoint]) -> CGPoint { CGPoint(x: (q[0].x + q[1].x) / 2, y: (q[0].y + q[1].y) / 2) }

    /// The handle above the top edge, in canvas points.
    static func rotateHandle(_ box: CropBoxModel, scale: CGFloat) -> CGPoint {
        let q = box.quad.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        let m = midTop(q)
        let a = box.angle * .pi / 180
        return CGPoint(x: m.x + 30 * sin(a), y: m.y - 30 * cos(a))
    }

    /// The edge that will be the top of the output, after its turn.
    static func outputTop(_ box: CropBoxModel, _ q: [CGPoint]) -> (CGPoint, CGPoint) {
        let i = [0: 0, 90: 3, 180: 2, 270: 1][box.turn] ?? 0
        let (a, b) = (q[i], q[(i + 1) % 4])
        let inset: CGFloat = 0.3
        return (CGPoint(x: a.x + (b.x - a.x) * inset, y: a.y + (b.y - a.y) * inset),
                CGPoint(x: a.x + (b.x - a.x) * (1 - inset), y: a.y + (b.y - a.y) * (1 - inset)))
    }
}

/// The outputs as they'll be written (straightened, trimmed, turned), in the
/// order they'll be numbered, at their real proportions. Tap one to leave it
/// out or put it back (spec 2.3: where an upside-down box shows up).
struct MultiCropStrip: View {
    let session: MultiCropSession
    var height: CGFloat = 72
    /// Taps do nothing on the monitor.
    var interactive = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(session.orderedIDs, id: \.self) { (id: String) in
                    tile(id)
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, 6)
        }
        .frame(height: height + 12)
        .background(Theme.table.tile)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What will be saved")
    }

    private func tile(_ id: String) -> some View {
        let off = session.isOff(id)
        let number = session.numbers[id]
        let image = session.thumbnails[id]
        let aspect: CGFloat = image.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? 1
        let width = min(height * 2.4, max(height * 0.4, height * aspect))
        return Button {
            if interactive { session.toggleOff(id) }
        } label: {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().interpolation(.medium)
                    } else {
                        Rectangle().fill(Theme.table.rule)
                    }
                }
                .frame(width: width, height: height)
                .opacity(off ? 0.3 : 1)
                .overlay { Rectangle().stroke(id == session.focused ? Theme.table.accent : Theme.table.rule, lineWidth: id == session.focused ? 2 : 1) }
                Text(off ? "–" : number.map(String.init) ?? "·")
                    .font(.mono(11, medium: true))
                    .foregroundStyle(off ? Theme.table.muted : Theme.table.accentInk)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(off ? Theme.table.tile : Theme.table.accent)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .help(off ? "Left out: tap to make it" : "Tap to leave this one out (Space)")
        .accessibilityLabel(off ? "Box left out" : "Photo \(number ?? 0)")
        .accessibilityHint(off ? "Puts it back" : "Leaves it out")
    }
}

/// The magnifier beside a corner being dragged (spec 2.3), with the box's
/// edges drawn through it so the corner can be set to the pixel.
struct CropLoupe: View {
    let image: CGImage
    /// The image's size in source pixels (the preview may be smaller).
    let imageSize: CGSize
    let box: CropBoxModel
    let corner: Int
    /// Canvas points per source pixel.
    let scale: CGFloat
    var diameter: CGFloat = 124
    var magnify: CGFloat = 4

    var body: some View {
        let c = box.quad[corner]
        let m = scale * magnify
        let d = diameter
        let q = box.quad.map { CGPoint(x: ($0.x - c.x) * m + d / 2, y: ($0.y - c.y) * m + d / 2) }
        // Up and to the outside of the corner, so the finger doesn't hide it.
        let left = c.x * scale > d * 1.3
        let up = c.y * scale > d * 1.3
        let at = CGPoint(x: c.x * scale + (left ? -d * 0.85 : d * 0.85), y: c.y * scale + (up ? -d * 0.85 : d * 0.85))
        return Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.none)
            .frame(width: imageSize.width * m, height: imageSize.height * m)
            .offset(x: d / 2 - c.x * m, y: d / 2 - c.y * m)
            .frame(width: d, height: d, alignment: .topLeading)
            .overlay {
                Canvas { context, _ in
                    var path = Path()
                    path.addLines(q)
                    path.closeSubpath()
                    context.stroke(path, with: .color(Theme.table.accent), lineWidth: 1.5)
                    var cross = Path()
                    cross.move(to: CGPoint(x: d / 2 - 8, y: d / 2))
                    cross.addLine(to: CGPoint(x: d / 2 + 8, y: d / 2))
                    cross.move(to: CGPoint(x: d / 2, y: d / 2 - 8))
                    cross.addLine(to: CGPoint(x: d / 2, y: d / 2 + 8))
                    context.stroke(cross, with: .color(.white), lineWidth: 2.5)
                    context.stroke(cross, with: .color(.black), lineWidth: 1)
                }
            }
            .clipShape(Circle())
            .overlay { Circle().stroke(Theme.table.accent, lineWidth: 2) }
            .shadow(radius: 4)
            .position(at)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Glue

/// The glued picture as the plan lays it out: background, each photo with its
/// fade, the focus ring and the seams.
struct GlueCanvasPicture: View {
    let session: GlueSession
    let plan: GluePlan
    let scale: CGFloat
    /// The seam being dragged, drawn solid.
    var activeSeam: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundLayer
            ForEach(Array(plan.items.enumerated()), id: \.offset) { (_: Int, item: GluePlacement) in
                if let image = session.preview(item.index) {
                    placed(image, item)
                }
            }
            seamMarks
        }
        .frame(width: CGFloat(plan.width) * scale, height: CGFloat(plan.height) * scale, alignment: .topLeading)
        .clipped()
    }

    /// One photo where the plan puts it, with its fade, focus ring and handle.
    private func placed(_ image: CGImage, _ item: GluePlacement) -> some View {
        let f: CGRect = item.frame
        let focused: Bool = session.focused == item.index && !session.before
        let ring: Color = focused ? Theme.table.accent : .clear
        let label: String = "\(session.images[item.index].name), photo \(item.index + 1) of \(plan.items.count)"
        return Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: f.width * scale, height: f.height * scale)
            .mask { Self.rampMask(item) }
            .overlay { Rectangle().stroke(ring, lineWidth: 2) }
            .overlay(alignment: .bottomTrailing) {
                if session.isFree && focused {
                    Circle().fill(Theme.table.accent).frame(width: 16, height: 16).offset(x: 8, y: 8)
                }
            }
            .offset(x: f.minX * scale, y: f.minY * scale)
            .accessibilityLabel(label)
            .accessibilityAddTraits(focused ? .isSelected : [])
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        let size = CGSize(width: CGFloat(plan.width) * scale, height: CGFloat(plan.height) * scale)
        let background = session.shownEdit.background
        if background.kind == "blur", let first = plan.items.first, let image = session.preview(first.index) {
            // A stand-in for the core's blurred fill: the made file uses the real one.
            Image(decorative: image, scale: 1).resizable().scaledToFill()
                .frame(width: size.width, height: size.height)
                .blur(radius: max(size.width, size.height) / 18)
                .clipped()
        } else {
            Rectangle().fill(Color(hexString: background.colour) ?? .white)
                .frame(width: size.width, height: size.height)
        }
    }

    private var seamMarks: some View {
        let joins = plan.joins
        let focusedJoin = session.before ? nil : session.focusedJoin
        let active = activeSeam
        return Canvas { context, size in
            for (k, join) in joins.enumerated() where join.join_px < 0 {
                var path = Path()
                if join.axis == "x" {
                    path.move(to: CGPoint(x: join.seam_px * scale, y: 0))
                    path.addLine(to: CGPoint(x: join.seam_px * scale, y: size.height))
                } else {
                    path.move(to: CGPoint(x: 0, y: join.seam_px * scale))
                    path.addLine(to: CGPoint(x: size.width, y: join.seam_px * scale))
                }
                let lit = k == active || k == focusedJoin
                context.stroke(path, with: .color(Theme.table.accent.opacity(lit ? 1 : 0.7)),
                               style: StrokeStyle(lineWidth: lit ? 2 : 1, dash: k == active ? [] : [5, 5]))
            }
        }
        .allowsHitTesting(false)
    }

    /// The fade as a mask, the same smoothstep the core blends with.
    static func rampMask(_ item: GluePlacement) -> some View {
        LinearGradient(stops: stops(rising: item.ramps.left, falling: item.ramps.right, origin: Double(item.x), length: Double(item.w)),
                       startPoint: .leading, endPoint: .trailing)
            .mask(LinearGradient(stops: stops(rising: item.ramps.top, falling: item.ramps.bottom, origin: Double(item.y), length: Double(item.h)),
                                 startPoint: .top, endPoint: .bottom))
    }

    static func stops(rising: GlueRamp?, falling: GlueRamp?, origin: Double, length: Double) -> [Gradient.Stop] {
        func smooth(_ t: Double) -> Double { let t = min(max(t, 0), 1); return t * t * (3 - 2 * t) }
        func weight(_ x: Double) -> Double {
            var w = 1.0
            if let r = rising { w *= r.b <= r.a ? (x < r.a ? 0 : 1) : smooth((x - r.a) / (r.b - r.a)) }
            if let r = falling { w *= r.b <= r.a ? (x >= r.b ? 0 : 1) : 1 - smooth((x - r.a) / (r.b - r.a)) }
            return w
        }
        var xs: [Double] = [origin, origin + length]
        for r in [rising, falling].compactMap({ $0 }) {
            if r.b <= r.a {
                xs += [r.a - 0.01, r.a]
            } else {
                xs += (0...8).map { r.a + (r.b - r.a) * Double($0) / 8 }
            }
        }
        return xs.filter { $0 >= origin && $0 <= origin + length }.sorted().map { x in
            Gradient.Stop(color: .black.opacity(weight(x)), location: length > 0 ? (x - origin) / length : 0)
        }
    }
}
