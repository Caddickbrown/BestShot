import Foundation
import Observation

/// The label names and Bridge mapping, saved as open JSON in Application
/// Support, plus the opt-in for writing into JPEGs.
@Observable
@MainActor
final class LabelStore {
    static let shared = LabelStore()

    private(set) var settings: LabelSettings
    private(set) var warning: String?
    /// Bumped on every change, for open folders to pick up.
    private(set) var revision = 0

    /// Off by default: BestShot writes sidecars and leaves originals alone.
    var writeJPEG: Bool {
        didSet {
            UserDefaults.standard.set(writeJPEG, forKey: Self.writeJPEGKey)
            revision += 1
        }
    }

    private static let writeJPEGKey = "writeXMPIntoJPEG"

    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("BestShot/labels.json")
    }

    private init() {
        let loaded = loadLabelSettings(path: Self.fileURL.path)
        settings = loaded.settings
        warning = loaded.warning
        writeJPEG = UserDefaults.standard.bool(forKey: Self.writeJPEGKey)
    }

    func save(_ new: LabelSettings) throws {
        try saveLabelSettings(path: Self.fileURL.path, settings: new)
        settings = new
        revision += 1
    }

    /// A change to how labels look. Nothing in a file changes, so open folders
    /// have nothing to pick up, and any names being typed stay.
    func saveLook(_ new: LabelSettings) throws {
        try saveLabelSettings(path: Self.fileURL.path, settings: new)
        settings = new
    }

    func name(_ colour: LabelColour) -> String { settings.names[colour] ?? colour.title }
}
