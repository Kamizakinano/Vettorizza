import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var store: StatsStore
    @State private var range = 7
    @State private var metric = 0
    @State private var selected: Date?

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

    @ViewBuilder private var chart: some View {
        let m = metrics[metric]
        let pts = store.dailyGains(m.1, days: range)
        let total = pts.map(\.value).reduce(0, +)
        let sel = pts.first { selected != nil && Calendar.current.isDate($0.date, inSameDayAs: selected!) }
        VStack(alignment: .leading, spacing: 4) {
            if let sel {
                Text("\(sel.date.formatted(date: .abbreviated, time: .omitted)): +\(sel.value) \(m.0.lowercased())")
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
                    BarMark(x: .value("Giorno", p.date, unit: .day), y: .value(m.0, p.value))
                        .foregroundStyle(sel == nil || sel?.date == p.date ? m.2 : m.2.opacity(0.3))
                }
                .chartXSelection(value: $selected)
                .frame(height: 200)
            }
        }
    }
}
