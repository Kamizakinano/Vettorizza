import SwiftUI
import Charts

struct BestHoursView: View {
    @StateObject private var hs = HourlyStore()
    @State private var metric: HourlyStore.Metric = .download
    private let days = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $metric) {
                    ForEach(HourlyStore.Metric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                if hs.daysCovered < 1 {
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

                Text("Media per ora").font(.headline)
                let hours = hs.byHour(metric)
                Chart {
                    ForEach(0..<24, id: \.self) { h in
                        BarMark(x: .value("Ora", h), y: .value(metric.rawValue, hours[h]))
                            .foregroundStyle(metric == .download ? Color.green : Color.orange)
                    }
                }
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
