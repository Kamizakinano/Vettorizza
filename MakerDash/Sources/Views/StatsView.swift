import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: StatsStore
    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let err = store.error { Text(err).foregroundStyle(.red).padding() }
                LazyVGrid(columns: cols, spacing: 12) {
                    tile("Followers", "person.2", .cyan, \.followers)
                    tile("Boosts", "bolt", .yellow, \.boosts)
                    tile("Likes", "heart", .pink, \.likes)
                    tile("Downloads", "arrow.down.circle", .green, \.downloads)
                    tile("Prints", "printer", .gray, \.prints)
                }.padding()
            }
            .navigationTitle(store.username.isEmpty ? "Stats" : store.username)
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
        }
    }

    private func tile(_ title: String, _ icon: String, _ color: Color, _ kp: KeyPath<ProfileStats, Int>) -> some View {
        let d = store.delta(kp)
        return VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(color)
            Text(store.today.map { $0[keyPath: kp].formatted() } ?? "—").font(.title2.monospacedDigit().bold())
            HStack {
                Text("Today:").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(d >= 0 ? "+\(d)" : "\(d)").font(.caption.bold()).foregroundStyle(d >= 0 ? .green : .red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.4)))
    }
}
