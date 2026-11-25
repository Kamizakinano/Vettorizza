import SwiftUI
import Charts

struct PointBill: Codable, Identifiable {
    var title: String; var detail: String; var change: Double; var regular: Double; var exclusive: Double; var time: String
    var id: String { time + title + detail + String(change) }
    var date: Date? { Self.iso.date(from: time) }
    private static let iso = ISO8601DateFormatter()
}
struct PointBillPage: Codable { var total: Int; var income: Double; var expense: Double; var hits: [PointBill] }

struct PointsHistoryView: View {
    @EnvironmentObject var store: StatsStore
    @State private var items: [PointBill] = []
    @State private var total = 0
    @State private var income = 0.0
    @State private var expense = 0.0
    @State private var loading = false
    @State private var failed = false
    @State private var filter = 0
    @State private var period = 0   // 0 giorno, 1 settimana, 2 mese
    @State private var loadingAll = false

    struct Bucket: Identifiable { let start: Date; var income: Double; var expense: Double; var id: Date { start } }

    private var buckets: [Bucket] {
        let cal = Calendar.current
        let comp: Calendar.Component = period == 0 ? .day : period == 1 ? .weekOfYear : .month
        var map: [Date: Bucket] = [:]
        for b in items {
            guard let d = b.date, let st = cal.dateInterval(of: comp, for: d)?.start else { continue }
            var x = map[st] ?? Bucket(start: st, income: 0, expense: 0)
            if b.change > 0 { x.income += b.change } else { x.expense += -b.change }
            map[st] = x
        }
        return map.values.sorted { $0.start > $1.start }
    }

    private func label(_ d: Date) -> String {
        switch period {
        case 0: return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case 1: return "Sett. " + d.formatted(.dateTime.day().month(.abbreviated))
        default: return d.formatted(.dateTime.month(.wide).year())
        }
    }

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
            Section("Riepilogo") {
                Picker("", selection: $period) {
                    Text("Giorno").tag(0); Text("Settimana").tag(1); Text("Mese").tag(2)
                }.pickerStyle(.segmented)
                let bs = buckets
                if !bs.isEmpty {
                    Chart(Array(bs.prefix(period == 0 ? 14 : 12).reversed())) { b in
                        BarMark(x: .value("P", label(b.start)), y: .value("Pt", b.income)).foregroundStyle(.green)
                        BarMark(x: .value("P", label(b.start)), y: .value("Pt", -b.expense)).foregroundStyle(.red)
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 120)
                }
                ForEach(bs.prefix(period == 0 ? 30 : 12)) { b in
                    HStack {
                        Text(label(b.start)).font(.subheadline)
                        Spacer()
                        Text("+\(b.income.formatted(.number.precision(.fractionLength(0...2))))")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.green)
                        if b.expense > 0 {
                            Text("−\(b.expense.formatted(.number.precision(.fractionLength(0...2))))")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.red)
                        }
                    }
                }
                if loadingAll {
                    HStack { ProgressView(); Text("Carico tutto lo storico… \(items.count)/\(total)").font(.caption).foregroundStyle(.secondary) }
                }
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
        .refreshable { items = []; await loadAll() }
        .task { if items.isEmpty { await loadAll() } }
    }

    private func stat(_ t: String, _ v: Double, _ c: Color) -> some View {
        VStack {
            Text(v.formatted(.number.precision(.fractionLength(0...0)))).font(.headline.monospacedDigit()).foregroundStyle(c)
            Text(t).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    /// Scarica tutti i movimenti (servono per il riepilogo per giorno/settimana/mese).
    private func loadAll() async {
        loadingAll = true; defer { loadingAll = false }
        repeat {
            let before = items.count
            await load(limit: 50)
            if items.count == before { break }
        } while items.count < total && items.count < 5000
    }

    private func load(limit: Int = 20) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        if let p = await MakerWorldFetcher.shared.fetchPointBills(handle: store.handle, offset: items.count, limit: limit) {
            total = p.total; income = p.income; expense = p.expense
            items += p.hits; failed = false
        } else { failed = true }
    }
}
