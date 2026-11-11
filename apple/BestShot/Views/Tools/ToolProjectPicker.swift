import SwiftData
import SwiftUI

/// Uses the project's existing on-disk files without the Data-based import path.
struct ToolProjectPicker: View {
  let kind: MediaType
  let choose: (URL) -> Void
  @Query(sort: \MediaItem.importedAt, order: .reverse) private var items: [MediaItem]
  @State private var showing = false
  var body: some View {
    Button("Project") { showing = true }
      .sheet(isPresented: $showing) {
        NavigationStack {
          List {
            ForEach(items.filter { $0.mediaType == kind }) { item in
              Button {
                choose(item.fileURL)
                showing = false
              } label: {
                VStack(alignment: .leading) {
                  Text(item.filename)
                  Text(item.project?.name ?? "Project").font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
          .overlay {
            if !items.contains(where: { $0.mediaType == kind }) {
              Text("No matching media in your projects.")
            }
          }
          .navigationTitle("Project media")
          .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { showing = false } }
          }
        }
      }
  }
}
