import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: StatsStore
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                AccountPicker()
                if let err = store.error { Text(err).foregroundStyle(.red).padding(.horizontal) }
                if let s = store.stats {
                    if s.pointsKnown == true { NavigationLink { PointsHistoryView() } label: { pointsCard(s) }.buttonStyle(.plain) } else { Text("Punti: accedi con questo account in Settings → Login per i punti").font(.caption).foregroundStyle(.secondary).padding() }
                    boostCard
                    LazyVGrid(columns: cols, spacing: 8) {
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

    private var boostCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Boost ricevuti", systemImage: "bolt.fill").font(.subheadline.bold()).foregroundStyle(.yellow)
            HStack {
                counter("Oggi", store.total(\.boosts, in: .day))
                counter("Settimana", store.total(\.boosts, in: .weekOfYear))
                counter("Mese", store.total(\.boosts, in: .month))
                counter("Anno", store.total(\.boosts, in: .year))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.yellow.opacity(0.08)))
        .padding(.horizontal).padding(.bottom, 8)
    }

    private func counter(_ t: String, _ v: Int) -> some View {
        VStack {
            Text("+\(v)").font(.headline.monospacedDigit())
            Text(t).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func pointsCard(_ s: ProfileStats) -> some View {
        let d = store.deltaPoints()
        let perCard = 524.0, cardEuro = 40.0, exclRate = 0.066, exclMin = 100.0
        let total = s.pointsRegular + s.pointsExclusive
        let cards = Int(total / perCard)
        let toNext = perCard - total.truncatingRemainder(dividingBy: perCard)
        let regEuro = s.pointsRegular * cardEuro / perCard
        let exclUsd = s.pointsExclusive * exclRate
        func num(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Points").font(.headline)
                Text(num(total)).font(.headline.monospacedDigit()).foregroundStyle(.yellow)
                if d != 0 { Text((d > 0 ? "+" : "") + num(d)).font(.caption.bold()).foregroundStyle(d > 0 ? .green : .red) }
                Spacer()
                Text("Storico").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Regular").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(cards) buoni").font(.caption2.bold()).foregroundStyle(.yellow)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.yellow.opacity(0.15)))
                    }
                    Text(num(s.pointsRegular)).font(.title3.monospacedDigit().bold())
                    Text(regEuro.formatted(.currency(code: "EUR"))).font(.caption.monospacedDigit())
                    Text("\(Int(toNext.rounded(.up))) pt al prossimo buono").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Exclusive").font(.caption).foregroundStyle(.secondary)
                    Text(num(s.pointsExclusive)).font(.title3.monospacedDigit().bold()).foregroundStyle(.yellow)
                    Text(exclUsd.formatted(.currency(code: "USD"))).font(.caption.monospacedDigit())
                    Text(exclUsd >= exclMin ? "Riscattabile" : "\((exclMin - exclUsd).formatted(.currency(code: "USD"))) al riscatto")
                        .font(.caption2).foregroundStyle(exclUsd >= exclMin ? .green : .secondary)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.15)))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.12)))
        .padding(.horizontal).padding(.vertical, 6)
    }

    private func labeled(_ t: String, _ v: Double) -> some View {
        VStack(alignment: .leading) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(v.formatted(.number.precision(.fractionLength(0...2)))).font(.headline.monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ title: String, _ icon: String, _ color: Color, _ kp: KeyPath<ProfileStats, Int>) -> some View {
        let d = store.delta(kp)
        return VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(color).lineLimit(1)
            Text(store.stats.map { $0[keyPath: kp].formatted() } ?? "—")
                .font(.headline.monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: 4) {
                Text(d >= 0 ? "+\(d)" : "\(d)").font(.caption2.bold()).foregroundStyle(d >= 0 ? .green : .red)
                Spacer(minLength: 0)
                if let c = store.weekChange(kp) {
                    Text("\(c >= 0 ? "+" : "")\(Int(c))%").font(.caption2).foregroundStyle(c >= 0 ? .green : .red)
                }
            }
            Sparkline(points: store.dailyGains(kp, days: 14), color: color).frame(height: 22)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.4)))
    }
}
