import SwiftUI

/// The light-table Rank sheet: photos in rank order (drag to reorder), the
/// ones not ranked yet below, and the way into Compare.
struct RankBoardView: View {
    @Bindable var board: RankBoard
    /// Extra toolbar action, e.g. "Save as album" for the Photos library.
    var extraAction: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineRule()
            if board.pool.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        rankedSheet
                        if !board.unranked.isEmpty {
                            SheetLabel("Not ranked yet · \(board.unranked.count)")
                                .padding(.horizontal, 12)
                                .padding(.top, 24)
                                .padding(.bottom, 8)
                            ContactSheet(data: board.unranked.map(Tile.init), minimum: 140) { tile in
                                mountedPrint(tile.id, rank: nil)
                                    .draggable(tile.id)
                            }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .tableSurface()
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.title)
                        .font(.mono(12))
                        .foregroundStyle(Theme.table.muted)
                    Text("Rank")
                        .font(.display(38, weight: 800, width: 70))
                }
                Spacer()
                Text(status)
                    .font(.mono(12))
                    .foregroundStyle(Theme.table.muted)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) { poolTabs; Spacer(); actions }
                VStack(alignment: .leading, spacing: 10) { poolTabs; actions }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var status: String {
        let r = board.ranked.count, n = board.unranked.count
        return "\(r) ranked · \(n) new"
    }

    private var poolTabs: some View {
        HStack(spacing: 22) {
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
        HStack(spacing: 18) {
            if let extraAction {
                Button(extraAction.title, action: extraAction.run)
                    .buttonStyle(.text)
                    .disabled(board.ranked.isEmpty)
            }
            Button("Clear ranking") { board.clear() }
                .buttonStyle(.text)
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
                    .font(.mono(13))
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
                if let rank {
                    Text("\(rank)")
                        .font(.display(rank <= 3 ? 20 : 17, weight: 800, width: 70))
                        .foregroundStyle(rank <= 3 ? Theme.table.accent : Theme.table.ink)
                        .background(alignment: .center) {
                            if rank == 1 {
                                GreasePencilMark(shape: .circle, lineWidth: 2)
                                    .frame(width: 34, height: 30)
                            }
                        }
                }
                Spacer(minLength: 0)
                Text(board.media.caption(id))
                    .font(.mono(9))
                    .foregroundStyle(Theme.table.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rank.map { "Rank \($0), \(board.media.caption(id))" } ?? board.media.caption(id))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing to rank yet")
                .font(.display(24, weight: 800, width: 70))
            Text("Keep some photos first, then rank them best to worst here.")
                .font(.mono(13))
                .foregroundStyle(Theme.table.muted)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
