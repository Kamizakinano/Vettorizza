import Foundation

/// Campioni orari raccolti da GitHub Actions (branch stats-data) per capire gli orari migliori.
struct HourlySample: Codable { let t: Int; let d: Int; let p: Int; let l: Int; let c: Int; let f: Int; var b: Int?; var m: [String: [Int]]? }
struct HourlyFile: Codable { let handle: String; let samples: [HourlySample] }

@MainActor
final class HourlyStore: ObservableObject {
    @Published private(set) var samples: [HourlySample] = []
    @Published private(set) var loading = false
    @Published var error: String?
    private let cacheKey = "hourly.Kamy29"

    static let url = URL(string: "https://raw.githubusercontent.com/kamizakinano/vettorizza/stats-data/hourly/Kamy29.json")!

    init() {
        if let d = UserDefaults.standard.data(forKey: cacheKey),
           let f = try? JSONDecoder().decode(HourlyFile.self, from: d) { samples = f.samples }
    }

    func load() async {
        loading = true; defer { loading = false }
        do {
            var req = URLRequest(url: Self.url); req.cachePolicy = .reloadIgnoringLocalCacheData
            let (d, _) = try await URLSession.shared.data(for: req)
            let f = try JSONDecoder().decode(HourlyFile.self, from: d)
            samples = f.samples.sorted { $0.t < $1.t }
            UserDefaults.standard.set(d, forKey: cacheKey)
            error = nil
        } catch { self.error = "Impossibile scaricare i dati orari" }
    }

    enum Metric: String, CaseIterable { case download = "Download", stampe = "Stampe" }

    struct Bucket: Identifiable { let start: Date; let value: Int; var id: Date { start } }

    /// Valore interpolato a un istante (nil se i campioni attorno distano più di 3 ore).
    private func value(_ m: Metric, at t: TimeInterval) -> Double? {
        func f(_ x: HourlySample) -> Double { Double(m == .download ? x.d : x.p) }
        guard let a = samples.last(where: { TimeInterval($0.t) <= t }),
              let b = samples.first(where: { TimeInterval($0.t) >= t }),
              t - TimeInterval(a.t) <= 3 * 3600, TimeInterval(b.t) - t <= 3 * 3600 else { return nil }
        if a.t == b.t { return f(a) }
        return f(a) + (f(b) - f(a)) * (t - TimeInterval(a.t)) / TimeInterval(b.t - a.t)
    }

    /// Prima mezzanotte da cui i dati sono completi.
    var startDate: Date? {
        guard let f = samples.first else { return nil }
        let cal = Calendar.current, d = Date(timeIntervalSince1970: TimeInterval(f.t))
        let mid = cal.startOfDay(for: d)
        return mid == d ? mid : cal.date(byAdding: .day, value: 1, to: mid)
    }

    /// Incrementi ora per ora (orologio esatto: 00:00-01:00, 01:00-02:00...) a partire da mezzanotte.
    func buckets(_ m: Metric) -> [Bucket] {
        guard let start = startDate, let last = samples.last else { return [] }
        var out: [Bucket] = []
        var t = start.timeIntervalSince1970
        let end = TimeInterval(last.t)
        while t + 3600 <= end {
            if let a = value(m, at: t), let b = value(m, at: t + 3600) {
                out.append(Bucket(start: Date(timeIntervalSince1970: t), value: max(0, Int((b - a).rounded()))))
            }
            t += 3600
        }
        return out
    }

    /// Ore di oggi (dalla mezzanotte), con l'ora in corso parziale.
    func today(_ m: Metric) -> [Bucket] {
        let mid = Calendar.current.startOfDay(for: Date())
        var out = buckets(m).filter { $0.start >= mid }
        if let last = samples.last {
            let t = (out.last.map { $0.start.timeIntervalSince1970 + 3600 }) ?? mid.timeIntervalSince1970
            if TimeInterval(last.t) > t, let a = value(m, at: t), let b = value(m, at: TimeInterval(last.t)) {
                out.append(Bucket(start: Date(timeIntervalSince1970: t), value: max(0, Int((b - a).rounded()))))
            }
        }
        return out
    }

    private func deltas(_ m: Metric) -> [(date: Date, value: Double)] {
        buckets(m).map { ($0.start, Double($0.value)) }
    }

    /// Media per ora del giorno (0...23).
    func byHour(_ m: Metric) -> [Double] {
        var sum = Array(repeating: 0.0, count: 24), n = Array(repeating: 0.0, count: 24)
        let cal = Calendar.current
        for x in deltas(m) { let h = cal.component(.hour, from: x.date); sum[h] += x.value; n[h] += 1 }
        return (0..<24).map { n[$0] > 0 ? sum[$0] / n[$0] : 0 }
    }

    /// Media per giorno della settimana (0 = lunedì) e ora.
    func heatmap(_ m: Metric) -> [[Double]] {
        var sum = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        var n = sum
        let cal = Calendar.current
        for x in deltas(m) {
            let wd = (cal.component(.weekday, from: x.date) + 5) % 7
            let h = cal.component(.hour, from: x.date)
            sum[wd][h] += x.value; n[wd][h] += 1
        }
        return (0..<7).map { d in (0..<24).map { h in n[d][h] > 0 ? sum[d][h] / n[d][h] : 0 } }
    }

    /// Fascia di 3 ore con la media più alta.
    func bestWindow(_ m: Metric) -> (start: Int, value: Double)? {
        let h = byHour(m)
        guard h.contains(where: { $0 > 0 }) else { return nil }
        func win(_ a: Int) -> Double { h[a % 24] + h[(a + 1) % 24] + h[(a + 2) % 24] }
        var best = 0
        for a in 1..<24 where win(a) > win(best) { best = a }
        return (best, win(best))
    }

    var daysCovered: Double {
        guard let f = startDate, let l = samples.last else { return 0 }
        return max(0, (TimeInterval(l.t) - f.timeIntervalSince1970) / 86400)
    }
}
