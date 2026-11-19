import Foundation

/// An editor's local Undo and Redo. One drag, one added or removed box, or one
/// setting change is one step: a drag calls `begin` when it starts and
/// `end` when it lets go, and everything in between is a single step.
struct EditHistory<State: Equatable> {
  private(set) var undoStack: [State] = []
  private(set) var redoStack: [State] = []
  private var dragStart: State?
  var limit = 200

  var canUndo: Bool { !undoStack.isEmpty }
  var canRedo: Bool { !redoStack.isEmpty }

  /// Call before a one-shot change with the state as it was.
  mutating func record(_ old: State, now: State) {
    guard dragStart == nil, old != now else { return }
    push(old)
  }
  mutating func begin(_ state: State) {
    if dragStart == nil { dragStart = state }
  }
  mutating func end(_ state: State) {
    if let start = dragStart, start != state { push(start) }
    dragStart = nil
  }
  mutating func undo(_ current: State) -> State? {
    guard let previous = undoStack.popLast() else { return nil }
    redoStack.append(current)
    return previous
  }
  mutating func redo(_ current: State) -> State? {
    guard let next = redoStack.popLast() else { return nil }
    undoStack.append(current)
    return next
  }
  mutating func clear() {
    undoStack = []
    redoStack = []
    dragStart = nil
  }
  private mutating func push(_ state: State) {
    undoStack.append(state)
    if undoStack.count > limit { undoStack.removeFirst() }
    redoStack = []
  }
}
