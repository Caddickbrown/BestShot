import Foundation

// MARK: - Every key the monitor answers to
//
// One table per situation. A press runs the first entry that takes it and the
// hint bar draws the same entries, so the bar can only list keys that work.
// Pure, so it's tested on the Mac without a window or a monitor.
//
// The shared keys are `kit/specs/KEYS.md`, and none means anything else here:
// ↑↓ jk move, ↵ open, esc back, x done, n new, / search, ⌘Z undo, ? all keys,
// ⌥⌘= − size, ⌥⌘P pause. KEYS.md puts sections on ⌘1–9 on a desktop, which leaves
// 1–5 for stars, and BestShot's own letters are all ones it leaves free. That's why
// Folders' k (keywords), p (keep) and r (rank) are t, 8 and ⌘2 on the monitor.

enum KeyName: Equatable {
    case up, down, left, right, enter, tab, escape, backspace, home, end, pageUp, pageDown
    case char(Character)
}

struct KeyMods: OptionSet {
    let rawValue: Int
    static let command = KeyMods(rawValue: 1)
    static let option = KeyMods(rawValue: 2)
    static let control = KeyMods(rawValue: 4)
    static let shift = KeyMods(rawValue: 8)
}

struct MonitorPress {
    let key: KeyName
    let mods: KeyMods
    /// What the key types. Empty for chords and named keys.
    let text: String
    /// Sent by a held key rather than a press.
    var isRepeat = false

    init(_ key: KeyName, _ mods: KeyMods = [], text: String = "") {
        self.key = key
        self.mods = mods
        self.text = text
    }

    /// A plain character, as a keyboard sends it.
    static func typed(_ character: Character) -> MonitorPress {
        MonitorPress(.char(character), text: String(character))
    }

    func matches(_ key: KeyName, _ mods: KeyMods = []) -> Bool {
        self.key == key && self.mods == mods
    }

    var isText: Bool { !text.isEmpty && mods.isDisjoint(with: [.command, .control]) }
}

enum MonitorSection: Int, CaseIterable, Identifiable {
    case triage = 1, rank, organise, allMedia, projects, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .triage: return "Triage"
        case .rank: return "Rank"
        case .organise: return "Organise"
        case .allMedia: return "All Media"
        case .projects: return "Projects"
        case .settings: return "Settings"
        }
    }
}

/// All a key can do. Nothing here deletes: `.finish` opens the panel, and only a
/// row chosen in that panel goes on to the confirmation.
enum MonitorAction: Equatable {
    case escape, pause, textSize(Int), menu, help, section(MonitorSection), undo
    case move(Int), moveRow(Int), page(Int), first, last, open
    case rate(Int), label(LabelColour), clearMark, favourite, tag, zoom, pan(x: Int, y: Int)
    case compare, swapCompare, grid, filters, info, finish, nextUnreviewed(Int)
    case choose(RankChoice), compareUndo, startCompare
    case nextPhoto, skipPhoto, newAlbum
    case type(String), deleteLetter, complete, submit

    /// Held down, these keep going. A mark never does: one press, one mark.
    var repeats: Bool {
        switch self {
        case .move, .page, .pan, .type, .deleteLetter: return true
        default: return false
        }
    }
}

/// What's on the monitor, as far as the keys care.
struct MonitorSituation: Equatable {
    enum Surface: Equatable {
        case locked, paused, phoneSheet
        case palette, help, entry, finish
        case list, loupe, grid, rankCompare, mediaPhoto
    }

    var surface = Surface.list
    /// Esc has somewhere to go.
    var canStepBack = false
    var hasPhoto = false
    var canUndo = false
    var zoomed = false
    var comparing = false
    /// Triage is open, so there's something to finish.
    var inTriage = false
    /// The list's lit row does something on ↵.
    var rowOpens = false
    var rowCount = 0
    /// Rank's list: the lit row is a photo, which can go up and down.
    var ranking = false
    var canCompare = false
    /// Organise's photo and albums.
    var organising = false
    /// The entry has something to add, and a suggestion to complete to.
    var entryHasText = false
    var entryCanComplete = false
    /// In the finish panel, a row has been chosen with the keys.
    var finishChosen = false
    /// Deleting: the phone is asking, and no key does anything until it's answered.
    var finishBusy = false
    var hasMediaNeighbours = false
}

struct MonitorBinding: Identifiable {
    /// As the hint bar shows it.
    let keys: String
    let label: String
    let resolve: (MonitorPress) -> MonitorAction?

    var id: String { keys + label }

    init(_ keys: String, _ label: String, resolve: @escaping (MonitorPress) -> MonitorAction?) {
        self.keys = keys
        self.label = label
        self.resolve = resolve
    }

    init(_ keys: String, _ label: String, _ action: MonitorAction, matches: @escaping (MonitorPress) -> Bool) {
        self.init(keys, label) { matches($0) ? action : nil }
    }
}

enum MonitorKeymap {
    /// The first entry that takes the press.
    static func action(for press: MonitorPress, in situation: MonitorSituation) -> MonitorAction? {
        for binding in bindings(for: situation) {
            if let action = binding.resolve(press) { return action }
        }
        return nil
    }

    /// The keys that work right now, and all of them.
    static func bindings(for s: MonitorSituation) -> [MonitorBinding] {
        switch s.surface {
        case .locked: return []
        case .paused:
            return [MonitorBinding("esc ⌥⌘P", "Resume", .pause) { $0.matches(.escape) || isPause($0) }, textSize]
        case .phoneSheet:
            return [MonitorBinding("esc", "Close what's on the phone", .escape) { $0.matches(.escape) }]
        case .palette: return palette + monitorKeys
        case .help:
            return [move("↑↓ jk", "Scroll"),
                    MonitorBinding("esc ?", "Close", .escape) { $0.matches(.escape) || isHelp($0) }] + monitorKeys
        case .entry: return entry(s)
        case .finish: return finish(s)
        case .list: return list(s) + everywhere(s)
        case .loupe: return loupe(s) + everywhere(s)
        case .grid: return grid(s) + everywhere(s)
        case .mediaPhoto: return mediaPhoto(s) + everywhere(s)
        case .rankCompare: return rankCompare + everywhere(s)
        }
    }

    // MARK: Always there

    private static let textSize = MonitorBinding("⌥⌘= −", "Text size") { k in
        if k.matches(.char("="), [.command, .option]) || k.matches(.char("="), [.command, .option, .shift])
            || k.matches(.char("+"), [.command, .option, .shift]) { return .textSize(1) }
        if k.matches(.char("-"), [.command, .option]) { return .textSize(-1) }
        return nil
    }

    private static func isPause(_ k: MonitorPress) -> Bool { k.matches(.char("p"), [.command, .option]) }

    private static func isHelp(_ k: MonitorPress) -> Bool {
        k.text == "?" || k.matches(.char("/"), .command) || k.matches(.char("?"), [.command, .shift])
            || k.matches(.char("/"), [.command, .shift])
    }

    private static var monitorKeys: [MonitorBinding] {
        [MonitorBinding("⌥⌘P", "Pause", .pause, matches: isPause), textSize]
    }

    private static func everywhere(_ s: MonitorSituation) -> [MonitorBinding] {
        var keys: [MonitorBinding] = []
        if s.canUndo {
            keys.append(MonitorBinding("⌘Z", "Undo", .undo) { $0.matches(.char("z"), .command) })
        }
        keys.append(MonitorBinding("⌘K /", "Menu", .menu) { $0.matches(.char("k"), .command) || $0.text == "/" })
        keys.append(MonitorBinding("⌘1–6 ⌘,", "Sections") { k in
            guard k.mods == .command else { return nil }
            if k.key == .char(",") { return .section(.settings) }
            guard case .char(let c) = k.key, let n = c.wholeNumberValue,
                  let section = MonitorSection(rawValue: n) else { return nil }
            return .section(section)
        })
        keys.append(MonitorBinding("?", "All keys", .help, matches: isHelp))
        if s.canStepBack {
            keys.append(MonitorBinding("esc", "Back", .escape) { $0.matches(.escape) })
        }
        return keys + monitorKeys
    }

    private static func move(_ keys: String, _ label: String) -> MonitorBinding {
        MonitorBinding(keys, label) { k in
            if k.matches(.down) || k.matches(.char("j")) { return .move(1) }
            if k.matches(.up) || k.matches(.char("k")) { return .move(-1) }
            return nil
        }
    }

    // MARK: Overlays

    private static let palette: [MonitorBinding] = [
        MonitorBinding("↑↓ ⇥", "Move") { k in
            if k.matches(.down) || k.matches(.tab) { return .move(1) }
            if k.matches(.up) || k.matches(.tab, .shift) { return .move(-1) }
            return nil
        },
        MonitorBinding("↵", "Run", .submit) { $0.matches(.enter) },
        MonitorBinding("⌫", "Delete a letter", .deleteLetter) { $0.matches(.backspace) },
        MonitorBinding("Type", "To find") { $0.isText ? .type($0.text) : nil },
        MonitorBinding("esc ⌘K", "Close", .escape) { $0.matches(.escape) || $0.matches(.char("k"), .command) },
    ]

    private static func entry(_ s: MonitorSituation) -> [MonitorBinding] {
        var keys: [MonitorBinding] = []
        if s.entryCanComplete {
            keys.append(MonitorBinding("⇥", "Complete", .complete) { $0.matches(.tab) })
        }
        if s.entryHasText {
            keys.append(MonitorBinding("↵", "Save", .submit) { $0.matches(.enter) })
            keys.append(MonitorBinding("⌫", "Delete a letter", .deleteLetter) { $0.matches(.backspace) })
        }
        keys.append(MonitorBinding("Type", "A word") { $0.isText ? .type($0.text) : nil })
        keys.append(MonitorBinding("esc", "Close", .escape) { $0.matches(.escape) })
        return keys
    }

    private static func finish(_ s: MonitorSituation) -> [MonitorBinding] {
        if s.finishBusy { return [] }
        var keys = [move("↑↓ jk", "Choose")]
        if s.finishChosen {
            keys.append(MonitorBinding("↵", "Go", .submit) { $0.matches(.enter) })
        }
        keys.append(MonitorBinding("esc", "Keep triaging", .escape) { $0.matches(.escape) })
        return keys
    }

    // MARK: Lists

    private static func list(_ s: MonitorSituation) -> [MonitorBinding] {
        var keys: [MonitorBinding] = []
        if s.rowCount > 0 {
            keys.append(move("↑↓ jk", "Move"))
            keys.append(MonitorBinding("PgUp PgDn", "Page") { k in
                if k.matches(.pageDown) { return .page(1) }
                if k.matches(.pageUp) { return .page(-1) }
                return nil
            })
            keys.append(MonitorBinding("Home End", "Top, end") { k in
                if k.matches(.home) { return .first }
                if k.matches(.end) { return .last }
                return nil
            })
        }
        if s.rowOpens {
            keys.append(MonitorBinding("↵", "Open", .open) { $0.matches(.enter) })
        }
        if s.ranking {
            keys.append(MonitorBinding("⌥↑↓", "Move in the ranking") { k in
                if k.matches(.up, .option) { return .moveRow(-1) }
                if k.matches(.down, .option) { return .moveRow(1) }
                return nil
            })
        }
        if s.canCompare {
            keys.append(MonitorBinding("c", "Compare", .startCompare) { $0.matches(.char("c")) })
        }
        if s.organising {
            keys.append(MonitorBinding("→", "Next photo", .nextPhoto) { $0.matches(.right) })
            keys.append(MonitorBinding("Space", "Skip", .skipPhoto) { $0.matches(.char(" ")) })
            keys.append(MonitorBinding("n", "New album", .newAlbum) { $0.matches(.char("n")) })
        }
        return keys
    }

    // MARK: Photos

    /// Stars and colours, wherever there's a current photo.
    private static let marks: [MonitorBinding] = [
        MonitorBinding("1–5 0", "Stars") { k in
            guard k.mods.isEmpty, case .char(let c) = k.key, let n = c.wholeNumberValue, n <= 5 else { return nil }
            return .rate(n)
        },
        MonitorBinding("8", "Green keep", .label(.green)) { $0.matches(.char("8")) },
        MonitorBinding("7", "Yellow maybe", .label(.yellow)) { $0.matches(.char("7")) },
        MonitorBinding("6", "Red delete", .label(.red)) { $0.matches(.char("6")) },
        MonitorBinding("9", "Blue", .label(.blue)) { $0.matches(.char("9")) },
        MonitorBinding("u", "Clear colour", .clearMark) { $0.matches(.char("u")) },
        MonitorBinding("t", "Tag", .tag) { $0.matches(.char("t")) },
        MonitorBinding("h", "Favourite", .favourite) { $0.matches(.char("h")) },
    ]

    /// Back and on through the photos, and the keys that open the rest.
    private static func walking(_ s: MonitorSituation) -> [MonitorBinding] {
        var keys: [MonitorBinding] = []
        if s.hasPhoto {
            keys.append(MonitorBinding("[ ]", "Not decided") { k in
                if k.text == "]" { return .nextUnreviewed(1) }
                if k.text == "[" { return .nextUnreviewed(-1) }
                return nil
            })
        }
        keys.append(MonitorBinding("f", "Filters", .filters) { $0.matches(.char("f")) })
        keys.append(MonitorBinding("x ⌘⌫", "Finish", .finish) { $0.matches(.char("x")) || $0.matches(.backspace, .command) })
        return keys
    }

    private static func loupe(_ s: MonitorSituation) -> [MonitorBinding] {
        var keys: [MonitorBinding] = []
        if s.zoomed {
            keys.append(MonitorBinding("←→↑↓", "Pan") { k in
                guard k.mods.isEmpty else { return nil }
                switch k.key {
                case .left: return .pan(x: -1, y: 0)
                case .right: return .pan(x: 1, y: 0)
                case .up: return .pan(x: 0, y: -1)
                case .down: return .pan(x: 0, y: 1)
                default: return nil
                }
            })
            keys.append(MonitorBinding("jk Space", "Next, previous") { k in
                if k.matches(.char("j")) || k.matches(.char(" ")) { return .move(1) }
                if k.matches(.char("k")) { return .move(-1) }
                return nil
            })
        } else {
            keys.append(MonitorBinding("←→ jk", "Previous, next") { k in
                if k.matches(.right) || k.matches(.down) || k.matches(.char("j")) || k.matches(.char(" ")) { return .move(1) }
                if k.matches(.left) || k.matches(.up) || k.matches(.char("k")) { return .move(-1) }
                return nil
            })
        }
        keys.append(MonitorBinding("Home End", "First, last") { k in
            if k.matches(.home) { return .first }
            if k.matches(.end) { return .last }
            return nil
        })
        if s.hasPhoto {
            keys += marks
            keys.append(MonitorBinding("z", "Zoom", .zoom) { $0.matches(.char("z")) })
            keys.append(MonitorBinding("c", s.comparing ? "Stop comparing" : "Compare", .compare) { $0.matches(.char("c")) })
            if s.comparing {
                keys.append(MonitorBinding("⇥", "Swap sides", .swapCompare) { $0.matches(.tab) })
            }
            keys.append(MonitorBinding("i", "Info", .info) { $0.matches(.char("i")) })
        }
        keys.append(MonitorBinding("g", "Grid", .grid) { $0.matches(.char("g")) })
        if s.canUndo {
            keys.append(MonitorBinding("⌫", "Undo", .undo) { $0.matches(.backspace) })
        }
        return keys + walking(s)
    }

    private static func grid(_ s: MonitorSituation) -> [MonitorBinding] {
        var keys = [MonitorBinding("←→↑↓ jk", "Move") { k in
            if k.matches(.left) { return .move(-1) }
            if k.matches(.right) { return .move(1) }
            if k.matches(.up) || k.matches(.char("k")) { return .page(-1) }
            if k.matches(.down) || k.matches(.char("j")) { return .page(1) }
            return nil
        }]
        if s.hasPhoto {
            keys.append(MonitorBinding("↵", "Open", .open) { $0.matches(.enter) })
            keys += marks
        }
        keys.append(MonitorBinding("g", "Photo", .grid) { $0.matches(.char("g")) })
        return keys + walking(s)
    }

    private static func mediaPhoto(_ s: MonitorSituation) -> [MonitorBinding] {
        var keys: [MonitorBinding] = []
        if s.hasMediaNeighbours {
            keys.append(MonitorBinding("←→ jk", "Previous, next") { k in
                if k.matches(.right) || k.matches(.down) || k.matches(.char("j")) || k.matches(.char(" ")) { return .move(1) }
                if k.matches(.left) || k.matches(.up) || k.matches(.char("k")) { return .move(-1) }
                return nil
            })
        }
        return keys
    }

    private static let rankCompare: [MonitorBinding] = [
        MonitorBinding("← 1", "Left", .choose(.left)) { $0.matches(.left) || $0.matches(.char("1")) },
        MonitorBinding("→ 2", "Right", .choose(.right)) { $0.matches(.right) || $0.matches(.char("2")) },
        MonitorBinding("Space", "Skip", .choose(.skip)) { $0.matches(.char(" ")) },
        MonitorBinding("⌫", "Undo", .compareUndo) { $0.matches(.backspace) },
    ]
}
