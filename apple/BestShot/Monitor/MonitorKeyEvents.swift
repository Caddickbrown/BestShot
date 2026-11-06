#if os(iOS)
import UIKit

// Hardware keys into `MonitorPress`es. The monitor's scene is shown but never key, so
// its keys arrive on the phone's, at `EscapeCatcherController`. From MarkRead's
// KeyCatcher.swift and MiniOffice:
//
// * Letters, arrows, Space, Return, Delete and the page keys come through
//   `pressesBegan`, which sees them with no Full Keyboard Access and no text field.
//   UIKit doesn't repeat presses, so held keys repeat in `MonitorKeyRepeater`.
// * ⌘ chords, Tab and Esc come through `UIKeyCommand`s instead, because the system
//   would otherwise claim some of them. `pressesBegan` leaves those alone so
//   nothing arrives twice.

extension MonitorPress {
    init?(_ key: UIKey) {
        let mods = KeyMods(key.modifierFlags)
        let name: KeyName
        switch key.keyCode {
        case .keyboardUpArrow: name = .up
        case .keyboardDownArrow: name = .down
        case .keyboardLeftArrow: name = .left
        case .keyboardRightArrow: name = .right
        case .keyboardReturnOrEnter, .keypadEnter, .keyboardReturn: name = .enter
        case .keyboardDeleteOrBackspace: name = .backspace
        case .keyboardHome: name = .home
        case .keyboardEnd: name = .end
        case .keyboardPageUp: name = .pageUp
        case .keyboardPageDown: name = .pageDown
        case .keyboardSpacebar:
            self.init(.char(" "), mods, text: " ")
            return
        default:
            // Digits by position, so they read as digits whatever ⇧ types.
            let digits: [UIKeyboardHIDUsage] = [.keyboard1, .keyboard2, .keyboard3, .keyboard4, .keyboard5,
                                                .keyboard6, .keyboard7, .keyboard8, .keyboard9, .keyboard0]
            let base: Character
            if let i = digits.firstIndex(of: key.keyCode) {
                base = Character(String((i + 1) % 10))
            } else if let c = key.charactersIgnoringModifiers.lowercased().first {
                base = c
            } else {
                return nil
            }
            // ⌃ chords type control characters; the base key is what matters.
            let typed = mods.contains(.control) ? "" : key.characters
            if typed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                self.init(.char(base), mods)
            } else {
                self.init(.char(base), mods, text: typed)
            }
            return
        }
        self.init(name, mods)
    }
}

extension KeyMods {
    init(_ flags: UIKeyModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.alternate) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.shift) { insert(.shift) }
    }
}

enum MonitorChords {
    /// Keys that arrive as key commands instead.
    static func comesAsCommand(_ key: UIKey) -> Bool {
        if key.modifierFlags.contains(.command) { return true }
        switch key.keyCode {
        case .keyboardTab, .keyboardEscape: return true
        default: return false
        }
    }

    private static let backspace = "\u{8}"

    /// The chords the monitor uses and no others, so the rest stay the system's.
    static func commands(action: Selector) -> [UIKeyCommand] {
        var list: [UIKeyCommand] = []
        func add(_ input: String, _ flags: UIKeyModifierFlags, title: String? = nil) {
            let command = UIKeyCommand(input: input, modifierFlags: flags, action: action)
            if let title {
                command.title = title
                command.discoverabilityTitle = title
            } else {
                command.attributes = .hidden
            }
            // The characters printed on the keys, not menu shortcuts to be moved.
            command.allowsAutomaticLocalization = false
            command.allowsAutomaticMirroring = false
            command.wantsPriorityOverSystemBehavior = true
            list.append(command)
        }
        add("k", .command, title: "Menu")
        add("z", .command, title: "Undo")
        add(",", .command, title: "Settings")
        for section in MonitorSection.allCases { add(String(section.rawValue), .command, title: section.title) }
        add(backspace, .command, title: "Finish Triage")
        // ⌘. is Esc on keyboards that have none.
        add(".", .command)
        add("/", .command, title: "All Keys")
        // ⇧ changes what this key types on most layouts, so it's caught both ways.
        add("/", [.command, .shift])
        add("?", [.command, .shift])
        add("p", [.command, .alternate], title: "Pause Monitor")
        add("=", [.command, .alternate])
        add("-", [.command, .alternate])
        add("=", [.command, .alternate, .shift])
        add("+", [.command, .alternate, .shift])
        add("\t", [])
        add("\t", .shift)
        return list
    }

    static func press(for command: UIKeyCommand) -> MonitorPress? {
        guard let input = command.input else { return nil }
        let mods = KeyMods(command.modifierFlags)
        switch input {
        case ".": return MonitorPress(.escape)
        case "\t": return MonitorPress(.tab, mods)
        case backspace: return MonitorPress(.backspace, mods)
        default:
            guard let character = input.first else { return nil }
            return MonitorPress(.char(character), mods)
        }
    }
}

/// Held keys repeat after about half a second, some 28 times a second: close to
/// the system's default. Only keys that say they repeat: a mark is one press.
@MainActor
final class MonitorKeyRepeater {
    private(set) var code: UIKeyboardHIDUsage?
    private var timer: Timer?

    func start(_ press: MonitorPress, code: UIKeyboardHIDUsage, desk: MonitorDesk) {
        stop()
        guard desk.repeats(press) else { return }
        self.code = code
        var held = press
        held.isRepeat = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { _ in
                    MainActor.assumeIsolated { _ = desk.handle(held) }
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        code = nil
    }
}
#endif
