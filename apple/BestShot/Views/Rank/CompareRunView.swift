import SwiftUI

/// Compare in the black viewfinder: two photos, pick the better one. Keys
/// match the Linux app: ← / 1 left, → / 2 right, Space skip, ⌫ undo, Esc save
/// and exit. On touch, tap a photo.
struct CompareRunView: View {
    let board: RankBoard
    @Bindable var run: CompareRun
    @FocusState private var focused: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var stacked: Bool { sizeClass == .compact }
    #else
    private let stacked = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            bar
            HairlineRule(palette: Theme.viewfinder)
            if let pair = run.pair {
                pairView(pair)
            } else {
                results
            }
        }
        .viewfinder()
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .space, .delete, .escape, .return]) { press in
            handle(press.key)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "12sS")) { press in
            switch press.characters {
            case "1": run.choose(.left)
            case "2": run.choose(.right)
            default: run.choose(.skip)
            }
            return .handled
        }
    }

    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .leftArrow: run.choose(.left)
        case .rightArrow: run.choose(.right)
        case .space: run.choose(.skip)
        case .delete: run.undo()
        case .escape: board.finishCompare(save: true)
        case .return:
            guard run.isFinished else { return .ignored }
            board.finishCompare(save: true)
        default: return .ignored
        }
        return .handled
    }

    // MARK: - Pieces

    private var bar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.isFinished ? "Ranking ready" : "Which is better?")
                    .font(.display(22, weight: 800, width: 70))
                Text(progressText)
                    .font(.mono(11))
                    .foregroundStyle(Theme.viewfinder.muted)
            }
            Spacer()
            Button("Undo") { run.undo() }
                .buttonStyle(.viewfinderText)
                .disabled(!run.progress.canUndo)
            if !run.isFinished {
                Button("Skip / tie") { run.choose(.skip) }
                    .buttonStyle(.viewfinderText)
                Button("Save & exit") { board.finishCompare(save: true) }
                    .buttonStyle(.viewfinderText)
                    .padding(.horizontal, 14)
                    .overlay(Capsule().stroke(Theme.viewfinder.rule, lineWidth: 1))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var progressText: String {
        let p = run.progress
        if run.isFinished { return "Done · \(p.asked) comparison\(p.asked == 1 ? "" : "s")" }
        var text = "\(p.percent)% · comparison \(p.asked + 1)"
        if p.inferred > 0 { text += " · \(p.inferred) inferred" }
        return text
    }

    @ViewBuilder
    private func pairView(_ pair: RankPair) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            side(pair.left, choice: .left, hint: stacked ? "Tap · ↑" : "← or 1")
            side(pair.right, choice: .right, hint: stacked ? "Tap · ↓" : "→ or 2")
        }
        .padding(4)
    }

    private func side(_ id: String, choice: RankChoice, hint: String) -> some View {
        Button {
            run.choose(choice)
        } label: {
            VStack(spacing: 0) {
                board.media.fullImage(id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(id)
                HStack(spacing: 16) {
                    Text(board.media.caption(id)).font(.mono(12))
                    Text(hint).font(.mono(12)).foregroundStyle(Theme.viewfinder.muted)
                }
                .padding(.vertical, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(board.media.caption(id))")
    }

    private var results: some View {
        let p = run.progress
        let saved = p.totalPairs > 0 ? Int((1 - Double(p.asked) / Double(p.totalPairs)) * 100) : 0
        return VStack(spacing: 14) {
            Text("Ranking ready")
                .font(.display(30, weight: 800, width: 70))
            Text("\(run.session.order().count) photos ranked in \(p.asked) comparisons"
                 + (p.inferred > 0 ? ", with \(p.inferred) worked out automatically" : "")
                 + (saved > 0 ? " (\(saved)% fewer than comparing every pair)." : "."))
                .font(.mono(13))
                .foregroundStyle(Theme.viewfinder.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            HStack(spacing: 20) {
                Button("Discard") { board.finishCompare(save: false) }
                    .buttonStyle(.viewfinderText)
                Button("Save ranking") { board.finishCompare(save: true) }
                    .buttonStyle(.viewfinderPill)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
