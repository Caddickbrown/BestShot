import SwiftUI

/// The light-table Rank sheet: photos in rank order (drag to reorder), the
/// ones not ranked yet below, and the way into Compare.
struct RankBoardView: View {
    @Bindable var board: RankBoard
    /// Extra toolbar action, e.g. "Save as album" for the Photos library.
    var extraAction: (title: String, run: () -> Void)?
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(eyebrow: board.title, title: "Rank", status: status) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.tabs) { poolTabs; Spacer(); actions }
                    VStack(alignment: .leading, spacing: Theme.Space.stack) { poolTabs; actions }
                }
            }
            if board.pool.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        rankedSheet
                        if !board.unranked.isEmpty {
                            SheetLabel("Not ranked yet · \(board.unranked.count)")
                                .padding(.horizontal, 12)
                                .padding(.top, Theme.Space.section)
                                .padding(.bottom, 8)
                            ContactSheet(data: board.unranked.map(Tile.init), minimum: 140) { tile in
                                mountedPrint(tile.id, rank: nil)
                                    .draggable(tile.id)
                            }
                        }
                    }
                    .padding(Theme.Space.gutter)
                }
            }
        }
        .tableSurface()
        .alert("Clear the ranking?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { board.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every photo goes back to Not ranked yet.")
        }
        .escapeCloses(when: confirmingClear) { confirmingClear = false }
        #if os(iOS)
        .fullScreenCover(item: $board.compare) { run in
            CompareRunView(board: board, run: run)
        }
        #else
        .sheet(item: $board.compare) { run in
            CompareRunView(board: board, run: run)
                .frame(minWidth: 960, minHeight: 640)
        }
        #endif
    }

    private struct Tile: Identifiable {
        let id: String
    }

    // MARK: - Header

    private var status: String {
        let r = board.ranked.count, n = board.unranked.count
        return "\(r) ranked · \(n) new"
    }

    private var poolTabs: some View {
        HStack(spacing: Theme.Space.tabs) {
            ForEach(board.pools) { pool in
                Button {
                    board.poolID = pool.id
                } label: {
                    Text("\(pool.title) \(pool.ids.count)")
                        .font(.mono(13, medium: pool.id == board.poolID))
                        .foregroundStyle(pool.id == board.poolID ? Theme.table.ink : Theme.table.muted)
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            if pool.id == board.poolID {
                                GreasePencilMark(shape: .underline, lineWidth: 2.5)
                                    .frame(height: 7)
                                    .padding(.horizontal, -4)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Space.actions) {
            if let extraAction {
                Button(extraAction.title, action: extraAction.run)
                    .buttonStyle(.text)
                    .disabled(board.ranked.isEmpty)
            }
            // Red, like every removal, and it asks first.
            Button("Clear ranking") { confirmingClear = true }
                .buttonStyle(TextButtonStyle(destructive: true))
                .disabled(board.ranked.isEmpty)
            if board.unranked.isEmpty {
                Button("Compare all") { board.startCompare(scope: .all) }
                    .buttonStyle(.pill)
                    .disabled(board.pool.count < 2)
            } else {
                Button("Compare all") { board.startCompare(scope: .all) }
                    .buttonStyle(.text)
                    .disabled(board.pool.count < 2)
                Button("Compare new (\(board.unranked.count))") {
                    board.startCompare(scope: board.ranked.isEmpty ? .all : .unranked)
                }
                .buttonStyle(.pill)
                .disabled(board.pool.count < 2)
            }
        }
    }

    // MARK: - Sheet

    private var rankedSheet: some View {
        Group {
            if board.ranked.isEmpty {
                Text("Drag photos here, or press Compare.")
                    .font(.note)
                    .foregroundStyle(Theme.table.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .dropDestination(for: String.self) { items, _ in
                        guard let id = items.first else { return false }
                        board.move(id, before: nil)
                        return true
                    }
            } else {
                ContactSheet(data: Array(board.ranked.enumerated()).map { RankedTile(id: $0.element, rank: $0.offset + 1) },
                             minimum: 140) { tile in
                    mountedPrint(tile.id, rank: tile.rank)
                        .draggable(tile.id)
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first else { return false }
                            board.move(id, before: tile.id)
                            return true
                        }
                }
            }
        }
    }

    private struct RankedTile: Identifiable {
        let id: String
        let rank: Int
    }

    private func mountedPrint(_ id: String, rank: Int?) -> some View {
        PrintMount {
            board.media.thumbnail(id)
        } caption: {
            HStack(spacing: 6) {
                if let rank { RankNumber(rank: rank) }
                Spacer(minLength: 0)
                Text(board.media.caption(id))
                    .font(.tiny)
                    .foregroundStyle(Theme.table.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rank.map { "Rank \($0), \(board.media.caption(id))" } ?? board.media.caption(id))
    }

    private var emptyState: some View {
        EmptyState("Nothing to rank yet", message: "Keep some photos first, then rank them best to worst here.")
    }
}
