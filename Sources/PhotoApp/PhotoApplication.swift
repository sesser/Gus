import PhotoCore
import SwiftUI

@main
struct PhotoApplication: App {
    var body: some Scene {
        WindowGroup(AppBranding.displayName) {
            Text("Welcome to \(AppBranding.displayName)")
                .frame(minWidth: 640, minHeight: 400)
        }
    }
}
