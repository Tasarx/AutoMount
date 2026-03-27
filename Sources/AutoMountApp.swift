import SwiftUI

@main
struct AutoMountApp: App {
    var body: some Scene {
        Window("AutoMount", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize) // Keep it tidy and small
        .windowStyle(.hiddenTitleBar)     // Modern macOS app aesthetic
    }
}
