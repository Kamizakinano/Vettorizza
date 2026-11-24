import SwiftUI
import BackgroundTasks

@main
struct MakerDashApp: App {
    @StateObject private var store = StatsStore()
    @Environment(\.scenePhase) private var phase
    static let bgID = "com.personal.makerdash.refresh"

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark)
        }
        .onChange(of: phase) { _, p in if p == .background { Self.schedule() } }
        .backgroundTask(.appRefresh(Self.bgID)) {
            await Self.schedule()
            await MainActor.run { () -> StatsStore in store }.refresh()
        }
    }

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: bgID)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

struct RootView: View {
    @EnvironmentObject var store: StatsStore
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            AnalyticsView().tabItem { Label("Analytics", systemImage: "chart.bar") }.tag(0)
            StatsView().tabItem { Label("Stats", systemImage: "house") }.tag(1)
            ModelsView().tabItem { Label("Models", systemImage: "cube") }.tag(2)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .onAppear { tab = store.defaultTab == 0 ? 1 : store.defaultTab }
    }
}

/// Selettore account mostrato in cima alle schermate.
struct AccountPicker: View {
    @EnvironmentObject var store: StatsStore
    var body: some View {
        if store.accounts.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(store.accounts, id: \.self) { a in
                        Button(a) { store.handle = a; Task { await store.refresh() } }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(a == store.handle ? Color(white: 0.25) : .clear))
                            .foregroundStyle(a == store.handle ? .white : .secondary)
                    }
                }.padding(.horizontal)
            }
        }
    }
}
