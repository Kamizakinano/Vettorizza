import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: StatsStore
    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let err = store.error { Text(err).foregroundStyle(.red).padding(.horizontal) }
                if let s = store.stats {
                    pointsCard(s)
                    LazyVGrid(columns: cols, spacing: 12) {
                        tile("Followers", "person.2", .cyan, \.followers)
                        tile("Boosts", "bolt", .yellow, \.boosts)
                        tile("Likes", "heart", .pink, \.likes)
                        tile("Downloads", "arrow.down.circle", .green, \.downloads)
                        tile("Prints", "printer", .gray, \.prints)
                        tile("Collections", "bookmark", .purple, \.collections)
                    }.padding(.horizontal)
                    if let u = store.snapshot?.updated {
                        Text("Aggiornato \(u.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary).padding()
                    }
                } else if store.loading {
                    ProgressView().padding(40)
                }
            }
            .navigationTitle(store.handle.isEmpty ? "Stats" : store.handle)
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
        }
    }

    private func pointsCard(_ s: ProfileStats) -> some View {
        let d = store.deltaPoints()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Points").font(.headline)
                Text((s.pointsRegular + s.pointsExclusive).formatted(.number.precision(.fractionLength(0...2))))
                    .font(.headline.monospacedDigit()).foregroundStyle(.yellow)
                Text(d >= 0 ? "+\(d.formatted(.number.precision(.fractionLength(0...2))))" : d.formatted())
                    .font(.caption.bold()).foregroundStyle(d >= 0 ? .green : .red)
            }
            HStack {
                labeled("Regular", s.pointsRegular)
                labeled("Exclusive", s.pointsExclusive)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.12)))
        .padding()
    }

    private func labeled(_ t: String, _ v: Double) -> some View {
        VStack(alignment: .leading) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v.formatted(.number.precision(.fractionLength(0...2)))).font(.title3.monospacedDigit().bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ title: String, _ icon: String, _ color: Color, _ kp: KeyPath<ProfileStats, Int>) -> some View {
        let d = store.delta(kp)
        return VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(color)
            Text(store.stats.map { $0[keyPath: kp].formatted() } ?? "—").font(.title2.monospacedDigit().bold())
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
