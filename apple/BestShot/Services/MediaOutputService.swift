import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Owns only private session copies and completed exports. Source files are read
/// under their security scope and are never opened for writing.
final class MediaWorkspace: @unchecked Sendable {
  let directory: URL
  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "BestShot-tools-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: directory) }
  func url(_ suffix: String) -> URL {
    directory.appendingPathComponent("\(UUID().uuidString).\(suffix)")
  }
  func stage(_ source: URL) throws -> URL {
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    if let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize {
      try Self.requireSpace(at: directory, bytes: Int64(size) + 32 * 1024 * 1024)
    }
    let target = url(source.pathExtension.isEmpty ? "media" : source.pathExtension)
    var coordinationError: NSError?
    var copyError: Error?
    NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) {
      readable in
      do { try FileManager.default.copyItem(at: readable, to: target) } catch { copyError = error }
    }
    if let coordinationError { throw coordinationError }
    if let copyError {
      try? FileManager.default.removeItem(at: target)
      throw copyError
    }
    return target
  }
  static func requireSpace(at url: URL, bytes: Int64) throws {
    let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    if let free = values.volumeAvailableCapacityForImportantUsage, free < bytes {
      throw MediaToolError.message(
        "Not enough free storage. Free at least \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) and try again."
      )
    }
  }
}

/// PhotosPicker hands out a short-lived URL. Copy it while the transfer is open;
/// consumers remove this staging copy as soon as it enters their workspace.
struct ToolPickedFile: Transferable {
  let url: URL
  static func remove(_ url: URL) {
    let directory = url.deletingLastPathComponent()
    if directory.lastPathComponent.hasPrefix("BestShot-picker-") {
      try? FileManager.default.removeItem(at: directory)
    }
  }
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .data) { received in
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "BestShot-picker-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent(received.file.lastPathComponent)
      do { try FileManager.default.copyItem(at: received.file, to: url) } catch {
        try? FileManager.default.removeItem(at: directory)
        throw error
      }
      return Self(url: url)
    }
  }
}
