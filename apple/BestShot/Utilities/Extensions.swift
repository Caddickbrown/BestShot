import SwiftUI

extension Date {
    /// Compact, filesystem-safe timestamp for generated filenames.
    static var timestampSlug: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: .now)
    }
}

extension View {
    /// Presents `content` as a full-screen cover on iOS and a sheet on macOS
    /// (which has no full-screen cover), driven by an optional `item`.
    @ViewBuilder
    func fullScreenCoverCompat<Item: Identifiable, C: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> C
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item, content: content)
        #else
        self.sheet(item: item, content: content)
        #endif
    }
}
