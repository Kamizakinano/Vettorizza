import SwiftUI
import Charts

struct BestHoursView: View {
    @StateObject private var hs = HourlyStore()
    @State private var metric: HourlyStore.Metric = .download
    @State private var selToday: Date?
    @State private var selAvg: Int?
    private let days = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $metric) {
                    ForEach(HourlyStore.Metric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                if let s = hs.startDate, s > Date() {
                    Label("Il conteggio parte dalla mezzanotte del \(s.formatted(.dateTime.day().month(.wide))). Le medie diventano affidabili dopo 1–2 settimane.",
                          systemImage: "hourglass")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if hs.daysCovered < 1 {
                    Label("Sto raccogliendo i dati: il controllo avviene ogni ora. Le medie diventano affidabili dopo 1–2 settimane.",
                          systemImage: "hourglass")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Dati di \(Int(hs.daysCovered)) giorni · \(hs.samples.count) controlli")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let b = hs.bestWindow(metric) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Momento migliore", systemImage: "star.fill").font(.subheadline.bold()).foregroundStyle(.yellow)
                        Text("Tra le \(b.start):00 e le \((b.start + 3) % 24):00")
                            .font(.title2.bold())
                        Text("In media \(b.value.formatted(.number.precision(.fractionLength(0...1)))) \(metric.rawValue.lowercased()) in queste 3 ore")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.yellow.opacity(0.1)))
                }

                let color = metric == .download ? Color.green : Color.orange
                let today = hs.today(metric)
                HStack {
                    Text("Oggi ora per ora").font(.headline)
                    Spacer()
                    Text("Totale \(today.map(\.value).reduce(0, +))").font(.caption).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(today) { b in
                        BarMark(x: .value("Ora", b.start, unit: .hour), y: .value(metric.rawValue, b.value))
                            .foregroundStyle(barColor(color, on: selToday == nil || sameHour(b.start, selToday)))
                    }
                    if let b = today.first(where: { sameHour($0.start, selToday) }) {
                        RuleMark(x: .value("Ora", b.start, unit: .hour)).foregroundStyle(.clear)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                tip("\(b.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))–\(b.start.addingTimeInterval(3600).formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))):00", "\(b.value) \(metric.rawValue.lowercased())")
                            }
                    }
                }
                .chartXScale(domain: Calendar.current.startOfDay(for: Date())...Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400))
                .chartXSelection(value: $selToday)
                .frame(height: 170)
                Text("Tieni premuto e scorri sul grafico per vedere ogni ora.").font(.caption2).foregroundStyle(.secondary)

                Text("Media per ora").font(.headline)
                let hours = hs.byHour(metric)
                Chart {
                    ForEach(0..<24, id: \.self) { h in
                        BarMark(x: .value("Ora", h), y: .value(metric.rawValue, hours[h]))
                            .foregroundStyle(barColor(color, on: selAvg == nil || selAvg == h))
                    }
                    if let h = selAvg, (0..<24).contains(h) {
                        RuleMark(x: .value("Ora", h)).foregroundStyle(.clear)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                tip(String(format: "%02d–%02d:00", h, (h + 1) % 24), "media \(hours[h].formatted(.number.precision(.fractionLength(0...1))))")
                            }
                    }
                }
                .chartXSelection(value: $selAvg)
                .chartXAxis { AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)") } } }
                .frame(height: 180)

                Text("Giorno e ora").font(.headline)
                heatmap(hs.heatmap(metric))

                if let e = hs.error { Text(e).font(.caption).foregroundStyle(.red) }
                Text("I dati pubblici del profilo Kamy29 vengono letti ogni ora da GitHub, anche a telefono spento. Gli orari sono quelli del tuo iPhone.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Orari migliori")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await hs.load() }
        .task { await hs.load() }
    }

    private func sameHour(_ a: Date, _ b: Date?) -> Bool {
        guard let b else { return false }
        return Calendar.current.isDate(a, equalTo: b, toGranularity: .hour)
    }
    private func barColor(_ c: Color, on: Bool) -> Color { on ? c : c.opacity(0.35) }

    private func tip(_ a: String, _ b: String) -> some View {
        VStack(spacing: 1) {
            Text(a).font(.caption2).foregroundStyle(.secondary)
            Text(b).font(.caption.bold())
        }
        .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.2)))
    }

    private func heatmap(_ m: [[Double]]) -> some View {
        let mx = max(m.flatMap { $0 }.max() ?? 0, 0.0001)
        let color: Color = metric == .download ? .green : .orange
        return VStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { d in
                HStack(spacing: 2) {
                    Text(days[d]).font(.system(size: 9)).frame(width: 26, alignment: .leading).foregroundStyle(.secondary)
                    ForEach(0..<24, id: \.self) { h in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(m[d][h] > 0 ? color.opacity(0.15 + 0.85 * m[d][h] / mx) : Color(white: 0.15))
                            .frame(height: 14)
                    }
                }
            }
            HStack(spacing: 0) {
                Text("").frame(width: 28)
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text("\(h)").font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
