import SwiftUI

struct PointBill: Codable, Identifiable {
    var title: String; var detail: String; var change: Double; var regular: Double; var exclusive: Double; var time: String
    var id: String { time + title + detail + String(change) }
    var date: Date? { ISO8601DateFormatter().date(from: time) }
}
struct PointBillPage: Codable { var total: Int; var income: Double; var expense: Double; var hits: [PointBill] }

struct PointsHistoryView: View {
    @EnvironmentObject var store: StatsStore
    @State private var items: [PointBill] = []
    @State private var total = 0, income = 0.0, expense = 0.0
    @State private var loading = false, failed = false
    @State private var filter = 0

    private var shown: [PointBill] {
        filter == 0 ? items : items.filter { filter == 1 ? $0.change > 0 : $0.change < 0 }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    stat("Guadagnati", income, .green)
                    stat("Spesi", expense, .red)
                    stat("Movimenti", Double(total), .secondary)
                }
                Picker("", selection: $filter) {
                    Text("Tutti").tag(0); Text("Entrate").tag(1); Text("Uscite").tag(2)
                }.pickerStyle(.segmented)
            }
            if failed && items.isEmpty {
                Text("Impossibile caricare. Accedi con questo account in Settings → Login per i punti.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(shown) { b in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.title).font(.subheadline.bold())
                            if !b.detail.isEmpty { Text(b.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            if let d = b.date { Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text((b.change > 0 ? "+" : "") + b.change.formatted(.number.precision(.fractionLength(0...2))))
                                .font(.headline.monospacedDigit()).foregroundStyle(b.change >= 0 ? .green : .red)
                            if b.exclusive != 0 { Text("excl. \(b.exclusive.formatted(.number.precision(.fractionLength(0...2))))").font(.caption2).foregroundStyle(.yellow) }
                        }
                    }
                }
                if items.count < total {
                    Button(loading ? "Caricamento…" : "Carica altri") { Task { await load() } }.disabled(loading)
                        .onAppear { Task { await load() } }
                }
            }
        }
        .navigationTitle("Storico punti")
        .refreshable { items = []; await load() }
        .task { if items.isEmpty { await load() } }
    }

    private func stat(_ t: String, _ v: Double, _ c: Color) -> some View {
        VStack {
            Text(v.formatted(.number.precision(.fractionLength(0...0)))).font(.headline.monospacedDigit()).foregroundStyle(c)
            Text(t).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        if let p = await MakerWorldFetcher.shared.fetchPointBills(handle: store.handle, offset: items.count) {
            total = p.total; income = p.income; expense = p.expense
            items += p.hits; failed = false
        } else { failed = true }
    }
}
