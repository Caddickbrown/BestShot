import Observation
import SwiftUI

/// The Glue or Multi Crop editor that's open, held above any one screen as
/// Triage's session is, so the monitor can draw it and its keys can reach it.
/// With a monitor in, the phone's key catcher sends every key to the desk,
/// and the desk hands them here while an editor is up (spec 0.6, Monitor Mode).
@Observable
@MainActor
final class ToolHolder {
    static let shared = ToolHolder()

    enum Open {
        case glue(GlueSession)
        case multiCrop(MultiCropSession)

        var kind: MonitorSituation.Tool {
            switch self {
            case .glue: return .glue
            case .multiCrop: return .multiCrop
            }
        }

        var session: AnyObject {
            switch self {
            case .glue(let s): return s
            case .multiCrop(let s): return s
            }
        }
    }

    private(set) var open: Open?

    /// An editor came on screen.
    func show(_ tool: Open) { open = tool }

    /// An editor went. Only its own: another may have opened since.
    func hide(_ session: AnyObject) {
        if open?.session === session { open = nil }
    }

    /// A key from the monitor's keyboard, in the open editor's keymap. False
    /// when the editor doesn't take it.
    func handle(_ press: MonitorPress) -> Bool {
        let k = ToolKeyPress(press)
        switch open {
        case .glue(let s):
            guard let command = GlueKeymap.command(
                key: k.key, characters: k.characters, modifiers: k.modifiers, vertical: s.vertical, free: s.isFree)
            else { return false }
            return s.perform(command)
        case .multiCrop(let s):
            if let id = Self.numberedBox(press, in: s) {
                s.pick(id)
                return true
            }
            guard let command = MultiCropKeymap.command(key: k.key, characters: k.characters, modifiers: k.modifiers)
            else { return false }
            return s.perform(command)
        case nil:
            return false
        }
    }

    /// While renumbering on the monitor, a digit picks the box with that number:
    /// there's no pointer there to click boxes with.
    private static func numberedBox(_ press: MonitorPress, in s: MultiCropSession) -> String? {
        guard s.renumbering != nil, press.mods.isEmpty, case .char(let c) = press.key, let n = c.wholeNumberValue, n > 0
        else { return nil }
        return s.numbers.first { $0.value == n }?.key
    }
}

/// A monitor key as the editors' keymaps read a SwiftUI key press.
struct ToolKeyPress {
    let key: KeyEquivalent
    let characters: String
    let modifiers: EventModifiers

    init(_ press: MonitorPress) {
        switch press.key {
        case .up: key = .upArrow
        case .down: key = .downArrow
        case .left: key = .leftArrow
        case .right: key = .rightArrow
        case .enter: key = .return
        case .tab: key = .tab
        case .escape: key = .escape
        case .backspace: key = .delete
        case .home: key = .home
        case .end: key = .end
        case .pageUp: key = .pageUp
        case .pageDown: key = .pageDown
        case .char(let c): key = KeyEquivalent(c)
        }
        if case .char(let c) = press.key {
            characters = press.text.isEmpty ? String(c) : press.text
        } else {
            characters = ""
        }
        var m: EventModifiers = []
        if press.mods.contains(.command) { m.insert(.command) }
        if press.mods.contains(.option) { m.insert(.option) }
        if press.mods.contains(.shift) { m.insert(.shift) }
        if press.mods.contains(.control) { m.insert(.control) }
        modifiers = m
    }
}
