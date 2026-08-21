import SwiftUI

@main
struct eudamed_mobileApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.light)
        }
    }
}
