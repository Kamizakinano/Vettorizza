import SwiftUI

@main
struct MakerDashApp: App {
    @StateObject private var store = StatsStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            StatsView().tabItem { Label("Stats", systemImage: "house") }
            ModelsView().tabItem { Label("Models", systemImage: "cube") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
