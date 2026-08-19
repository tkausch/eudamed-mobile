import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            NavigationStack {
                DeviceSearchView(repository: appState.deviceRepository)
            }
            .tabItem {
                Label("Devices", systemImage: "shippingbox")
            }

            NavigationStack {
                ActorSearchView(repository: appState.actorRepository)
            }
            .tabItem {
                Label("Actors", systemImage: "building.2")
            }

            NavigationStack {
                ScannerView(repository: appState.deviceRepository)
            }
            .tabItem {
                Label("Scan", systemImage: "barcode.viewfinder")
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
