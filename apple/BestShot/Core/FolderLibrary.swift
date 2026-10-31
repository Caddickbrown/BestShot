import Foundation

/// One reviewable item in a folder. Mirrors the Linux app's `library::Item`.
struct FolderItem: Identifiable, Hashable {
    /// Path relative to the folder, always `/`-separated. Also the id.
    let rel: String
    let kind: MediaType
    let ext: String
    let size: Int64
    let modified: Date
    /// Files (relative paths) culled together with this one: an iPhone Live
    /// Photo's `.MOV`, `.AAE` edit sidecars, `.xmp` files.
    var companions: [String]

    var id: String { rel }
    var filename: String { (rel as NSString).lastPathComponent }
    var directory: String { (rel as NSString).deletingLastPathComponent }
}

/// Scans a folder into an ordered list of reviewable items. Port of
/// `desktop/src-tauri/src/library.rs`, so both apps agree on what an item is.
enum FolderLibrary {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff", "heic", "heif"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "3gp"]
    static let sidecarExts: Set<String> = ["aae", "xmp"]
    /// Where "move to folder" puts rejects. Never scanned.
    static let rejectDir = "_Rejected"

    private struct Found {
        let rel: String
        let ext: String
        let size: Int64
        let modified: Date
    }

    private struct GroupKey: Hashable {
        let dir: String
        let stem: String
    }

    static func scan(root: URL, recursive: Bool, includeVideos: Bool) throws -> [FolderItem] {
        let fm = FileManager.default
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: root.path])
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: options) else {
            return []
        }

        let rootComponents = root.pathComponents
        var groups: [GroupKey: [Found]] = [:]
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if url.lastPathComponent == rejectDir { walker.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard imageExts.contains(ext) || videoExts.contains(ext) || sidecarExts.contains(ext) else { continue }

            let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            guard components.count > rootComponents.count,
                  Array(components.prefix(rootComponents.count)) == rootComponents else { continue }
            let relParts = components.dropFirst(rootComponents.count)
            let rel = relParts.joined(separator: "/")
            let dir = relParts.dropLast().joined(separator: "/")
            let stem = (relParts.last! as NSString).deletingPathExtension.lowercased()

            groups[GroupKey(dir: dir, stem: stem), default: []].append(Found(
                rel: rel,
                ext: ext,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast
            ))
        }

        var items: [FolderItem] = []
        for files in groups.values {
            let sorted = files.sorted { naturalLess($0.rel, $1.rel) }
            let images = sorted.filter { imageExts.contains($0.ext) }
            let videos = sorted.filter { videoExts.contains($0.ext) }
            let sidecars = sorted.filter { sidecarExts.contains($0.ext) }.map(\.rel)

            func item(_ f: Found, _ kind: MediaType) -> FolderItem {
                FolderItem(rel: f.rel, kind: kind, ext: f.ext, size: f.size, modified: f.modified, companions: [])
            }

            if !images.isEmpty {
                // Live Photo videos and sidecars belong to the first image of the group.
                for (i, image) in images.enumerated() {
                    var it = item(image, .image)
                    if i == 0 { it.companions = videos.map(\.rel) + sidecars }
                    items.append(it)
                }
            } else if includeVideos {
                for (i, video) in videos.enumerated() {
                    var it = item(video, .video)
                    if i == 0 { it.companions = sidecars }
                    items.append(it)
                }
            }
        }
        return items.sorted { naturalLess($0.rel, $1.rel) }
    }

    /// Finder-style ordering: case-insensitive, digit runs compared numerically,
    /// so `IMG_9.jpg` sorts before `IMG_10.jpg`.
    static func naturalLess(_ a: String, _ b: String) -> Bool {
        let r = a.localizedStandardCompare(b)
        return r == .orderedSame ? a < b : r == .orderedAscending
    }
}
