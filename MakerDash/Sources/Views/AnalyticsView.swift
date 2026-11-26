import SwiftUI
import Charts

struct AnalyticsView: View {
    @State private var showAllModels = false
    @State private var expandedModels: Set<Int> = []
    @EnvironmentObject var store: StatsStore
    @State private var mode: StatsStore.Grouping = .giorno
    @State private var offset = 0          // 0 = periodo attuale, 1 = precedente, ...
    @State private var metric = 0

    private let metrics: [(String, KeyPath<ProfileStats, Int>, Color)] = [
        ("Downloads", \.downloads, .green), ("Prints", \.prints, .gray), ("Likes", \.likes, .pink),
        ("Followers", \.followers, .cyan), ("Boosts", \.boosts, .yellow), ("Collections", \.collections, .purple)
    ]
    private let cal = Calendar.current

    private var comp: Calendar.Component {
        switch mode { case .giorno: .day; case .settimana: .weekOfYear; case .mese: .month; case .anno: .year }
    }
    private func interval(_ off: Int) -> DateInterval {
        let ref = cal.date(byAdding: comp, value: -off, to: Date())!
        return cal.dateInterval(of: comp, for: ref)!
    }
    private var current: DateInterval { interval(offset) }

    private var title: String {
        let d = current.start
        switch mode {
        case .giorno: return offset == 0 ? "Oggi" : offset == 1 ? "Ieri" : d.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .settimana:
            if offset == 0 { return "Questa settimana" }
            if offset == 1 { return "Settimana scorsa" }
            let end = cal.date(byAdding: .day, value: -1, to: current.end)!
            return "\(d.formatted(.dateTime.day().month())) – \(end.formatted(.dateTime.day().month()))"
        case .mese: return offset == 0 ? "Questo mese" : d.formatted(.dateTime.month(.wide).year())
        case .anno: return offset == 0 ? "Quest'anno" : d.formatted(.dateTime.year())
        }
    }

    /// Barre del grafico: gli ultimi N periodi fino a quello selezionato compreso.
    struct Bar: Identifiable { let off: Int; let start: Date; let value: Int; var id: Int { off } }

    /// Barre del grafico: una finestra di periodi che contiene quello selezionato.
    private var bars: [Bar] {
        let n = mode == .giorno ? 14 : mode == .settimana ? 12 : mode == .mese ? 12 : 5
        let newest = max(0, offset - n / 2)
        var out: [Bar] = []
        for off in newest..<(newest + n) {
            let iv = interval(off)
            out.append(Bar(off: off, start: iv.start, value: store.sum(metrics[metric].1, in: iv)))
        }
        return out.sorted { $0.start < $1.start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                AccountPicker()
                if let p = store.historyProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scarico lo storico dal Creator Center… \(Int(p * 100))%").font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: p).tint(.green)
                    }.padding(.horizontal)
                }
                VStack(alignment: .leading, spacing: 14) {
                    NavigationLink { BestHoursView() } label: {
                        HStack {
                            Label("Orari migliori", systemImage: "clock.badge.checkmark").font(.subheadline.bold()).foregroundStyle(.yellow)
                            Spacer()
                            Text("Download e stampe per ora").font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.08)))
                    }.buttonStyle(.plain)
                    Picker("Periodo", selection: $mode) {
                        ForEach(StatsStore.Grouping.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in offset = 0 }

                    HStack {
                        Button { offset += 1 } label: { Image(systemName: "chevron.left").font(.title3.bold()) }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(title).font(.headline)
                            if offset > 0 { Button("Torna a oggi") { offset = 0 }.font(.caption) }
                        }
                        Spacer()
                        Button { offset -= 1 } label: { Image(systemName: "chevron.right").font(.title3.bold()) }
                            .disabled(offset == 0)
                    }

                    LazyVGrid(columns: [GridItem(), GridItem(), GridItem()], spacing: 10) {
                        ForEach(metrics.indices, id: \.self) { i in
                            let v = store.sum(metrics[i].1, in: current)
                            Button { metric = i } label: {
                                VStack(spacing: 2) {
                                    Text("+\(v)").font(.headline.monospacedDigit()).foregroundStyle(metrics[i].2)
                                    Text(metrics[i].0).font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(metric == i ? metrics[i].2.opacity(0.22) : Color(white: 0.15)))
                            }.buttonStyle(.plain)
                        }
                    }

                    Chart(bars) { b in
                        BarMark(x: .value("Periodo", b.start, unit: comp), y: .value(metrics[metric].0, b.value))
                            .foregroundStyle(b.off == offset ? metrics[metric].2 : metrics[metric].2.opacity(0.3))
                    }
                    .chartOverlay { proxy in
                        GeometryReader { g in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onTapGesture { loc in
                                    if let d: Date = proxy.value(atX: loc.x - g[proxy.plotFrame!].origin.x),
                                       let b = bars.min(by: { abs($0.start.timeIntervalSince(d)) < abs($1.start.timeIntervalSince(d)) }) {
                                        offset = b.off
                                    }
                                }
                        }
                    }
                    .frame(height: 170)
                    Text("Tocca una barra o usa le frecce per cambiare periodo.")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let first = store.firstRecordedDay {
                        Text("Prima attività dal Creator Center: \(first.formatted(date: .abbreviated, time: .omitted)). Storico disponibile fino a 1 anno fa.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.1)))
                .padding(.horizontal)

                modelsSection

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

    @ViewBuilder private var modelsSection: some View {
        let list = store.designs(in: current)
        let visible = showAllModels ? list : Array(list.prefix(5))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Modelli attivi · \(title.lowercased())").font(.title3.bold())
                Spacer()
                if !list.isEmpty { Text("\(list.count)").font(.subheadline).foregroundStyle(.secondary) }
            }
            if list.isEmpty {
                Text("Nessuna attività registrata in questo periodo.").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(visible) { d in
                    let open = expandedModels.contains(d.id)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            RemoteImage(url: d.cover.flatMap(URL.init(string:)))
                                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.title).font(.subheadline).lineLimit(1)
                                HStack(spacing: 8) {
                                    chip("arrow.down", d.gain.downloads, .green)
                                    chip("printer", d.gain.prints, .gray)
                                    chip("heart", d.gain.likes, .pink)
                                    chip("bookmark", d.gain.collections, .purple)
                                    chip("bolt", d.gain.boosts, .yellow)
                                    chip("text.bubble", d.gain.comments, .cyan)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                        if open {
                            HStack(spacing: 10) {
                                gainView("arrow.down.circle", d.gain.downloads, d.total.downloads, .green)
                                gainView("printer", d.gain.prints, d.total.prints, .gray)
                                gainView("heart", d.gain.likes, d.total.likes, .pink)
                                gainView("bookmark", d.gain.collections, d.total.collections, .purple)
                                gainView("bolt", d.gain.boosts, d.total.boosts, .yellow)
                                gainView("text.bubble", d.gain.comments, d.total.comments, .cyan)
                            }.padding(.leading, 44)
                        }
                    }
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { if open { expandedModels.remove(d.id) } else { expandedModels.insert(d.id) } }
                    if d.id != visible.last?.id { Divider().padding(.leading, 52) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.1)))
            if list.count > 5 {
                Button(showAllModels ? "Mostra meno" : "Mostra tutti (\(list.count))") {
                    withAnimation { showAllModels.toggle() }
                }.font(.subheadline).frame(maxWidth: .infinity)
            }
        }.padding(.horizontal).padding(.top)
    }

    @ViewBuilder private func chip(_ icon: String, _ g: Int, _ c: Color) -> some View {
        if g != 0 {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 9))
                Text("\(g)").font(.caption2.bold().monospacedDigit())
            }.foregroundStyle(c)
        }
    }

    private func gainView(_ icon: String, _ g: Int, _ tot: Int, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Image(systemName: icon).font(.caption2).foregroundStyle(c)
            Text(g > 0 ? "+\(g)" : "\(g)").font(.caption.bold().monospacedDigit()).foregroundStyle(g > 0 ? c : .secondary)
            Text("\(tot)").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
