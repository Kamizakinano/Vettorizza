import Foundation

/// Campioni orari raccolti da GitHub Actions (branch stats-data) per capire gli orari migliori.
struct HourlySample: Codable { let t: Int; let d: Int; let p: Int; let l: Int; let c: Int; let f: Int }
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

    /// Incrementi tra campioni consecutivi, attribuiti all'ora (locale) del campione finale.
    /// Gli intervalli più lunghi di 3 ore vengono scartati (dati mancanti).
    private func deltas(_ m: Metric) -> [(date: Date, value: Double)] {
        guard samples.count > 1 else { return [] }
        var out: [(Date, Double)] = []
        for (a, b) in zip(samples, samples.dropFirst()) {
            let gap = Double(b.t - a.t)
            guard gap > 0, gap <= 3 * 3600 else { continue }
            let v = Double(m == .download ? b.d - a.d : b.p - a.p)
            guard v >= 0 else { continue }
            // normalizza a "per ora" se l'intervallo non è di un'ora esatta
            out.append((Date(timeIntervalSince1970: TimeInterval(b.t) - gap / 2), v * 3600 / gap))
        }
        return out
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
        guard let f = samples.first, let l = samples.last else { return 0 }
        return Double(l.t - f.t) / 86400
    }
}
