import Foundation

// MARK: - The command menu
//
// ⌘K: type a few letters and go somewhere. Pippin's CommandPalette, the same
// matching and the same two rules. Esc closes it in one press, from anywhere in
// it. And it can't say yes to anything: `MonitorMenuAction` has no way to delete,
// only to go to the finish panel, where a row has to be chosen by hand.

/// The letters of `query` in order within `text`.
enum MonitorMatch {
    /// Runs and word starts score higher, long titles a little lower. Nil when
    /// the letters aren't all there.
    static func score(_ query: String, _ text: String) -> Int? {
        let t = Array(text.lowercased())
        var score = 0, at = 0, run = 0
        for ch in query.lowercased() where ch != " " {
            var found = false
            while at < t.count {
                let here = at
                at += 1
                if t[here] == ch {
                    run += 1
                    score += 1 + run * 2 + (here == 0 || t[here - 1] == " " ? 6 : 0)
                    found = true
                    break
                }
                run = 0
            }
            if !found { return nil }
        }
        return score - t.count / 8
    }

    /// What matches, best first; equal scores keep the order they came in.
    static func rank<Item>(_ items: [Item], _ query: String, by text: (Item) -> String) -> [Item] {
        let scored = items.enumerated().compactMap { i, item in score(query, text(item)).map { (item, $0, i) } }
        return scored.sorted { ($0.1, $1.2) > ($1.1, $0.2) }.map(\.0)
    }
}

/// Everything the menu can make happen. There's deliberately no case that deletes.
enum MonitorMenuAction: Equatable {
    case section(MonitorSection)
    case project(UUID)
    case filters, clearFilters, grid, help, pause
    case status(MonitorFilter.Status)
    case tag(String)
    /// Opens the finish panel, with nothing chosen in it.
    case finish
}

struct MonitorMenuRow: Identifiable, Equatable {
    let id: String
    let title: String
    var detail: String?
    let action: MonitorMenuAction
}

struct MonitorPalette: Equatable {
    /// The most it ever lists: past this, typing is quicker than looking.
    static let limit = 10

    private(set) var query = ""
    private(set) var rows: [MonitorMenuRow] = []
    /// The row the keys are on, by id, so the highlight follows the row.
    private(set) var selected: String?
    private let all: [MonitorMenuRow]

    init(_ rows: [MonitorMenuRow]) {
        all = rows
        list()
    }

    var lit: MonitorMenuRow? { rows.first { $0.id == selected } }

    mutating func type(_ text: String) {
        let clean = text.filter { !$0.isNewline && !($0.asciiValue.map { $0 < 32 || $0 == 127 } ?? false) }
        guard !clean.isEmpty else { return }
        query = String((query + clean).prefix(60))
        list()
    }

    mutating func backspace() {
        guard !query.isEmpty else { return }
        query.removeLast()
        list()
    }

    /// Down the list as it's drawn, wrapping round.
    mutating func move(_ by: Int) {
        guard !rows.isEmpty else { return }
        guard let i = rows.firstIndex(where: { $0.id == selected }) else {
            selected = rows[0].id
            return
        }
        selected = rows[(i + by + rows.count) % rows.count].id
    }

    private mutating func list() {
        let blank = query.allSatisfy { $0 == " " }
        rows = Array((blank ? all : MonitorMatch.rank(all, query, by: \.title)).prefix(Self.limit))
        selected = rows.first?.id
    }
}
