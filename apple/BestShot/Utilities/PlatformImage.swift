import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}
#endif

extension PlatformImage {
    /// Decode from raw file data on either platform.
    static func fromData(_ data: Data) -> PlatformImage? {
        PlatformImage(data: data)
    }
}
