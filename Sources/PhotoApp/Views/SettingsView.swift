import PhotoCore
import SwiftUI

/// The app's Settings window.
struct SettingsView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        Form {
            Section("Importing") {
                Toggle("Open the import window when a card is inserted", isOn: $model.opensImportOnCard)
            }
            Section("Metadata") {
                Toggle("Write XMP sidecar files when photos change", isOn: $model.writesSidecars)
                Text("Ratings, labels, keywords and copyright go into an .xmp file next to each original, so other apps can read them. Originals are never changed. Sidecars another app changed are listed under Changed on Disk instead of being overwritten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        // Check boxes, not switches (section 8 of docs/UI_REDESIGN.md, Form
        // conventions; design.md I10).
        .toggleStyle(.checkbox)
        .frame(width: 480)
    }
}
