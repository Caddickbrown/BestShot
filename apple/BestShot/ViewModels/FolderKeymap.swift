#if os(macOS)
import SwiftUI

/// What a key can do in Folders mode. Keys only ever resolve to one of these
/// and `FolderCullSession.perform` carries it out, so buttons and any later
/// surface (Monitor Mode, say) drive the same actions as the keyboard.
enum FolderCommand: Equatable {
    case keep, reject
    case next, previous, first, last
    case up, down
    case undo, clearDecision, nextUnreviewed
    case rate(UInt8)
    case label(LabelColour)
    case toggleZoom, toggleInfo, toggleKeywords, toggleGrid, toggleRank
    case open, trashRed, escape
}

/// Where the key was pressed. A new mode is a new case here and in `command`.
enum FolderSurface: Equatable {
    case loupe, grid, rank
}

/// The keys, matching BestShot for Linux. Pure, so it can be tested without a
/// window.
enum FolderKeymap {
    static func command(key: KeyEquivalent, characters: String, modifiers: EventModifiers, on surface: FolderSurface) -> FolderCommand? {
        let text = characters.lowercased()
        if modifiers.contains(.command) {
            if text == "z" { return .undo }
            if key == .delete { return .trashRed }
            return nil
        }
        if key == .delete { return .undo }
        if key == .escape { return .escape }
        if text == "g" { return .toggleGrid }
        if text == "r" { return .toggleRank }

        switch surface {
        case .rank:
            return nil
        case .loupe:
            return shared(text) ?? loupe(key, text)
        case .grid:
            return shared(text) ?? grid(key)
        }
    }

    /// Marks: anywhere there's a current photo.
    private static func shared(_ text: String) -> FolderCommand? {
        switch text {
        case "0", "1", "2", "3", "4", "5": return .rate(UInt8(text)!)
        case "6": return .label(.red)
        case "7": return .label(.yellow)
        case "8": return .label(.green)
        case "9": return .label(.blue)
        case "k": return .toggleKeywords
        default: return nil
        }
    }

    private static func loupe(_ key: KeyEquivalent, _ text: String) -> FolderCommand? {
        switch key {
        case .rightArrow: return .keep
        case .leftArrow: return .reject
        case .downArrow, .space: return .next
        case .upArrow: return .previous
        case .home: return .first
        case .end: return .last
        default: break
        }
        switch text {
        case "p": return .keep
        case "x": return .reject
        case "u": return .clearDecision
        case "n": return .nextUnreviewed
        case "z": return .toggleZoom
        case "i": return .toggleInfo
        default: return nil
        }
    }

    private static func grid(_ key: KeyEquivalent) -> FolderCommand? {
        switch key {
        case .rightArrow: return .next
        case .leftArrow: return .previous
        case .downArrow: return .down
        case .upArrow: return .up
        case .return: return .open
        default: return nil
        }
    }
}
#endif
