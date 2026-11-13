import Foundation
import SwiftData

/// Renaming and removing projects.
///
/// Removing a project never deletes photos. Its photos are BestShot's own
/// imported copies (the originals in Photos or Files are never touched), and
/// even those are moved, not deleted: into Files → On My iPhone → BestShot →
/// Removed Projects, in a folder named after the project.
@MainActor
enum ProjectLibrary {

    /// The name as it will be saved, or nil if there's nothing left once trimmed.
    static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// False, and nothing changed, if the name is blank.
    @discardableResult
    static func rename(_ project: Project, to name: String, context: ModelContext) -> Bool {
        guard let clean = cleanName(name) else { return false }
        project.name = clean
        try? context.save()
        return true
    }

    /// Takes the project out of BestShot and moves its photos to Files. If the
    /// photos can't be moved, throws and keeps the project as it was. Returns
    /// where the photos went, or nil if it had none.
    @discardableResult
    static func remove(_ project: Project, context: ModelContext, store: MediaStore = .shared) throws -> URL? {
        let kept = try store.setAsideProjectFolder(projectID: project.uuid, name: project.name)
        context.delete(project)
        try? context.save()
        return kept
    }

    /// What the confirmation says before removing.
    static func removalMessage(for project: Project) -> String {
        let n = project.itemCount
        guard n > 0 else { return "The project is empty." }
        let items = "\(n) item\(n == 1 ? "" : "s")"
        #if os(iOS)
        return "Its \(items) move to the Files app, in BestShot › Removed Projects. Your Photos library isn't touched."
        #else
        return "Its \(items) move to the Trash. Your Photos library isn't touched."
        #endif
    }
}
