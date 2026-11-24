import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var store: StatsStore
    @State private var range = 7
    @State private var metric = 0
    @State private var selected: Date?
    @State private var grouping: StatsStore.Grouping = .giorno

    private let metrics: [(String, KeyPath<ProfileStats, Int>, Color)] = [
        ("Downloads", \.downloads, .green), ("Prints", \.prints, .gray), ("Likes", \.likes, .pink),
        ("Followers", \.followers, .cyan), ("Boosts", \.boosts, .yellow), ("Collections", \.collections, .purple)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                AccountPicker()
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Periodo", selection: $range) {
                        Text("7G").tag(7); Text("30G").tag(30); Text("180G").tag(180); Text("1A").tag(365)
                    }.pickerStyle(.segmented)
                    Picker("Raggruppa", selection: $grouping) {
                        ForEach(StatsStore.Grouping.allCases, id: \.self) { Text($0.rawValue) }
                    }.pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(metrics.indices, id: \.self) { i in
                                Button(metrics[i].0) { metric = i; selected = nil }
                                    .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(metric == i ? metrics[i].2.opacity(0.3) : Color(white: 0.15)))
                                    .foregroundStyle(metric == i ? metrics[i].2 : .secondary)
                            }
                        }
                    }
                    chart
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.1)))
                .padding(.horizontal)

                dayDetail

                VStack(alignment: .leading, spacing: 10) {
                    Text("Insight").font(.title3.bold())
                    ForEach(store.insights) { i in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: i.icon).foregroundStyle(i.positive ? .green : .orange).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(i.title).font(.subheadline.bold())
                                Text(i.text).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.1)))
                    }
                }.padding()
            }
            .navigationTitle("Analytics")
            .refreshable { await store.refresh() }
        }
    }

    @ViewBuilder private var dayDetail: some View {
        let day = grouping == .giorno ? (selected ?? Date()) : Date()
        let list = store.designs(on: day)
        VStack(alignment: .leading, spacing: 10) {
            Text(Calendar.current.isDateInToday(day) ? "Modelli attivi oggi" : "Modelli attivi il \(day.formatted(date: .abbreviated, time: .omitted))")
                .font(.title3.bold())
            Text(grouping == .giorno ? "Tocca una barra del grafico per vedere un altro giorno." : "Seleziona \"Giorno\" per scegliere la data dal grafico.")
                .font(.caption).foregroundStyle(.secondary)
            if list.isEmpty {
                Text("Nessuna attività registrata per questo giorno.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(list) { d in
                HStack(spacing: 10) {
                    AsyncImage(url: d.cover.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() }
                        placeholder: { Color.gray.opacity(0.2) }
                        .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.title).font(.subheadline.bold()).lineLimit(1)
                        HStack(spacing: 10) {
                            gainView("arrow.down.circle", d.gain.downloads, d.total.downloads, .green)
                            gainView("printer", d.gain.prints, d.total.prints, .gray)
                            gainView("heart", d.gain.likes, d.total.likes, .pink)
                            gainView("bookmark", d.gain.collections, d.total.collections, .purple)
                            gainView("bolt", d.gain.boosts, d.total.boosts, .yellow)
                            gainView("text.bubble", d.gain.comments, d.total.comments, .cyan)
                        }
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.1)))
            }
        }.padding(.horizontal).padding(.top)
    }

    private func gainView(_ icon: String, _ g: Int, _ tot: Int, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Image(systemName: icon).font(.caption2).foregroundStyle(c)
            Text(g > 0 ? "+\(g)" : "\(g)").font(.caption.bold().monospacedDigit())
                .foregroundStyle(g > 0 ? c : .secondary)
            Text("\(tot)").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func label(_ d: Date) -> String {
        switch grouping {
        case .giorno: d.formatted(date: .abbreviated, time: .omitted)
        case .settimana: "Settimana del " + d.formatted(.dateTime.day().month())
        case .mese: d.formatted(.dateTime.month(.wide).year())
        case .anno: d.formatted(.dateTime.year())
        }
    }

    @ViewBuilder private var chart: some View {
        let m = metrics[metric]
        let pts = store.grouped(m.1, days: range, by: grouping)
        let total = pts.map(\.value).reduce(0, +)
        let comp: Calendar.Component = grouping == .giorno ? .day : grouping == .settimana ? .weekOfYear : grouping == .mese ? .month : .year
        let sel = pts.first { selected != nil && Calendar.current.isDate($0.date, equalTo: selected!, toGranularity: comp) }
        VStack(alignment: .leading, spacing: 4) {
            if let sel {
                Text("\(label(sel.date)): +\(sel.value) \(m.0.lowercased())")
                    .font(.headline)
            } else {
                Text("+\(total) \(m.0.lowercased())").font(.headline)
                Text("negli ultimi \(range) giorni").font(.caption).foregroundStyle(.secondary)
            }
            if pts.isEmpty {
                Text("Nessuno storico ancora: i dati si accumulano ogni giorno che apri l'app.")
                    .font(.caption).foregroundStyle(.secondary).frame(height: 180)
            } else {
                Chart(pts) { p in
                    BarMark(x: .value("Periodo", p.date, unit: comp), y: .value(m.0, p.value))
                        .foregroundStyle(sel == nil || sel?.date == p.date ? m.2 : m.2.opacity(0.3))
                }
                .chartXSelection(value: $selected)
                .frame(height: 200)
            }
        }
    }
}
