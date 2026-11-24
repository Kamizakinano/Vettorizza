import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var store: StatsStore
    var body: some View {
        NavigationStack {
            List(store.models) { m in
                VStack(alignment: .leading) {
                    Text(m.title).font(.headline)
                    Text("⚡\(m.boosts)  ♥︎\(m.likes)  ↓\(m.downloads)  🖨\(m.prints)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .overlay { if store.models.isEmpty { ContentUnavailableView("Nessun modello", systemImage: "cube") } }
            .navigationTitle("Models")
        }
    }
}
