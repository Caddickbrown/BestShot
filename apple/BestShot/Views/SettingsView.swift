import SwiftUI

/// App preferences: theme selection (System / Light / Dark), mirroring the web
/// app's theme toggle. Persisted via `@AppStorage`.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ThemePreference.storageKey) private var themeRaw = ThemePreference.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $themeRaw) {
                        ForEach(ThemePreference.allCases) { pref in
                            Text(pref.title).tag(pref.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("About") {
                    LabeledContent("App", value: "BestShot")
                    LabeledContent("Version", value: appVersion)
                    Text("A native, on-device port of the BestShot media-ranking darkroom. All media and rankings stay on your device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 360)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
