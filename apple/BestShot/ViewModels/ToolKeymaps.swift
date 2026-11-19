import SwiftUI

// The keys inside the Glue and Multi Crop editors. Pure, so they're tested
// without a window (ToolKeymapTests). Single letters apply only in the editor
// and only when no field has focus; kit keys keep their meaning (↵ go, Esc
// back, ⌘Z undo).

/// Zoom keys both editors share: ⌘+ / ⌘− and ⌘0 to fit.
enum CanvasZoomCommand: Equatable { case zoomIn, zoomOut, fit }

/// An arrow key as a unit step, x right and y down.
private func arrow(_ key: KeyEquivalent) -> (Int, Int)? {
  switch key {
  case .leftArrow: return (-1, 0)
  case .rightArrow: return (1, 0)
  case .upArrow: return (0, -1)
  case .downArrow: return (0, 1)
  default: return nil
  }
}

private func zoom(_ text: String, _ modifiers: EventModifiers) -> CanvasZoomCommand? {
  guard modifiers.contains(.command) else { return nil }
  switch text {
  case "=", "+": return .zoomIn
  case "-", "_": return .zoomOut
  case "0": return .fit
  default: return nil
  }
}

enum MultiCropCommand: Equatable {
  case find, add, duplicate, next, previous
  case move(dx: Double, dy: Double)
  case resize(dw: Double, dh: Double)
  case rotate(Double)
  case turn(Int)
  case toggleCorners, remove, useLast, make, escape, undo, redo
  case zoom(CanvasZoomCommand)
}

enum MultiCropKeymap {
  static func command(key: KeyEquivalent, characters: String, modifiers: EventModifiers) -> MultiCropCommand? {
    let text = characters.lowercased()
    if let z = zoom(characters, modifiers) { return .zoom(z) }
    let shift = modifiers.contains(.shift)
    if modifiers.contains(.command) {
      switch text {
      case "z": return shift ? .redo : .undo
      case "d": return .duplicate
      case "[", "{": return .turn(-90)
      case "]", "}": return .turn(90)
      default: break
      }
      if key == .return { return .make }
      return nil
    }
    let step = shift ? 10.0 : 1.0
    if let (ix, iy) = arrow(key) {
      let (x, y) = (Double(ix), Double(iy))
      return modifiers.contains(.option) ? .resize(dw: x * step, dh: y * step) : .move(dx: x * step, dy: y * step)
    }
    switch key {
    case .return: return .make
    case .escape: return .escape
    case .delete, .deleteForward: return .remove
    case .tab: return shift ? .previous : .next
    default: break
    }
    switch text {
    case "f": return .find
    case "n": return .add
    case "[", "{": return .rotate(shift ? -1 : -0.1)
    case "]", "}": return .rotate(shift ? 1 : 0.1)
    case "r": return .turn(shift ? -90 : 90)
    case "p": return .toggleCorners
    case "l": return .useLast
    default: return nil
    }
  }
}

enum GlueCommand: Equatable {
  case flipLayout, cycleArrangement, cycleSize
  case next, previous
  case seam(Double)
  case offset(Int)
  /// Free layout: move the focused photo.
  case move(dx: Int, dy: Int)
  case moveEarlier, moveLater
  case join(Int)
  case fade(Int)
  case turn(Int)
  case remove, lineUp, glue, escape, undo, redo
  case zoom(CanvasZoomCommand)
}

enum GlueKeymap {
  static func command(key: KeyEquivalent, characters: String, modifiers: EventModifiers, vertical: Bool, free: Bool) -> GlueCommand? {
    let text = characters.lowercased()
    if let z = zoom(characters, modifiers) { return .zoom(z) }
    let shift = modifiers.contains(.shift)
    if modifiers.contains(.command) {
      if text == "z" { return shift ? .redo : .undo }
      if key == .leftArrow || key == .upArrow { return .moveEarlier }
      if key == .rightArrow || key == .downArrow { return .moveLater }
      if key == .return { return .glue }
      return nil
    }
    let step = shift ? 10 : 1
    if let (x, y) = arrow(key) {
      if free { return .move(dx: x * step, dy: y * step) }
      // Along the join moves the seam; across it slides the photo.
      let along = vertical ? y : x
      let across = vertical ? x : y
      return along != 0 ? .seam(Double(along * step)) : .offset(across * step)
    }
    switch key {
    case .return: return .glue
    case .escape: return .escape
    case .delete, .deleteForward: return .remove
    case .tab: return shift ? .previous : .next
    default: break
    }
    switch text {
    case "o": return .flipLayout
    case "a": return .cycleArrangement
    case "m": return .cycleSize
    case "-", "_": return .join(10)
    case "=", "+": return .join(-10)
    case "[", "{": return .fade(-10)
    case "]", "}": return .fade(10)
    case "r": return .turn(shift ? -90 : 90)
    case "l": return .lineUp
    default: return nil
    }
  }
}
