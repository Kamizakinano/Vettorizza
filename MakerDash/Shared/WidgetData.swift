import Foundation

/// Dati che l'app condivide con il widget (tramite App Group).
struct WidgetData: Codable {
    struct Top: Codable { var title: String; var downloads: Int; var prints: Int }
    var updated: Date
    var handle: String
    var points: Double?
    var pointsToday: Double = 0
    var perDay: Double?
    var downloads = 0, prints = 0, likes = 0, followers = 0, boosts = 0
    var spark7Downloads: [Int] = [], spark7Prints: [Int] = [], spark7Likes: [Int] = []
    var points14: [Double] = []
    var top: [Top] = []
    /// true se il widget non ha ancora il valore di inizio giornata (01:00) e non può dare numeri esatti.
    var waiting = false

    static let perCard = 524.0
    var cards: Int { Int((points ?? 0) / Self.perCard) }
    var toNext: Int { Int((Self.perCard - (points ?? 0).truncatingRemainder(dividingBy: Self.perCard)).rounded(.up)) }
    var progress: Double { ((points ?? 0).truncatingRemainder(dividingBy: Self.perCard)) / Self.perCard }
    var nextVoucher: Date? {
        guard let p = perDay, p > 0.1 else { return nil }
        return Calendar.current.date(byAdding: .day, value: Int((Double(toNext) / p).rounded(.up)), to: Date())
    }

    static let sample = WidgetData(updated: Date(), handle: "Kamy29", points: 1287, pointsToday: 18, perDay: 16,
                                   downloads: 42, prints: 17, likes: 23, followers: 3, boosts: 1,
                                   spark7Downloads: [3, 5, 4, 7, 6, 8, 9], spark7Prints: [2, 3, 3, 5, 4, 6, 7], spark7Likes: [4, 3, 5, 6, 5, 7, 8],
                                   points14: [12, 18, 9, 22, 15, 17, 25, 14, 19, 21, 16, 24, 20, 18],
                                   top: [.init(title: "Supporto cuffie", downloads: 12, prints: 4), .init(title: "Vaso spirale", downloads: 9, prints: 3), .init(title: "Portachiavi", downloads: 6, prints: 2)])

    // MARK: Archiviazione condivisa
    /// Nome dell'App Group letto dal profilo di installazione (Sideloadly può rinominarlo).
    static let groupID: String = {
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let raw = try? Data(contentsOf: url),
           let s = String(data: raw, encoding: .isoLatin1),
           let k = s.range(of: "com.apple.security.application-groups</key>"),
           let a = s.range(of: "<string>", range: k.upperBound..<s.endIndex),
           let b = s.range(of: "</string>", range: a.upperBound..<s.endIndex) {
            return String(s[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "group.com.personal.makerdash"
    }()
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent("widget.json")
    }
    static func load() -> WidgetData? {
        guard let u = fileURL, let d = try? Data(contentsOf: u) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(WidgetData.self, from: d)
    }
    func save() {
        guard let u = Self.fileURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        try? enc.encode(self).write(to: u, options: .atomic)
    }
}

/// Dati pubblici letti direttamente (senza login): incrementi di oggi dai campioni orari su GitHub.
enum PublicStats {
    struct S: Decodable { let t: Int; let d: Int; let p: Int; let l: Int; let f: Int; let b: Int?; let m: [String: [Int]]? }
    struct File: Decodable { let samples: [S] }
    static let url = URL(string: "https://raw.githubusercontent.com/kamizakinano/vettorizza/stats-data/hourly/Kamy29.json")!

    /// Aggiorna i numeri di oggi con i controlli orari arrivati dopo l'ultimo aggiornamento dell'app.
    /// Il giorno è quello di MakerWorld (UTC), come nell'app.
    static func merge(into w: inout WidgetData, standalone: Bool) async {
        var req = URLRequest(url: url, timeoutInterval: 15); req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let f = try? JSONDecoder().decode(File.self, from: d), let last = f.samples.last else { return }
        let lastT = TimeInterval(last.t)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = utc.startOfDay(for: Date()).timeIntervalSince1970
        func around(_ t: TimeInterval, _ pool: [S]) -> (S, S)? {
            guard let a = pool.last(where: { TimeInterval($0.t) <= t }),
                  let b = pool.first(where: { TimeInterval($0.t) >= t }),
                  t - TimeInterval(a.t) <= 3 * 3600, TimeInterval(b.t) - t <= 3 * 3600 else { return nil }
            return (a, b)
        }
        func value(_ t: TimeInterval, _ k: (S) -> Int, _ pool: [S]? = nil) -> Double? {
            guard let (a, b) = around(t, pool ?? f.samples) else { return nil }
            if a.t == b.t { return Double(k(a)) }
            return Double(k(a)) + Double(k(b) - k(a)) * (t - TimeInterval(a.t)) / TimeInterval(b.t - a.t)
        }

        if standalone {
            // Nessun dato dall'app: tutto dai controlli orari pubblici, giorno MakerWorld (UTC)
            w.handle = "Kamy29"; w.points = nil
            guard value(dayStart, { $0.d }) != nil else { w.waiting = true; w.updated = Date(timeIntervalSince1970: lastT); return }
            w.waiting = false
            func g(_ k: @escaping (S) -> Int) -> Int { Int((Double(k(last)) - (value(dayStart, k) ?? Double(k(last)))).rounded()) }
            w.downloads = g { $0.d }; w.prints = g { $0.p }; w.likes = g { $0.l }; w.followers = g { $0.f }
            let withB = f.samples.filter { $0.b != nil }
            if let lb = withB.last?.b, let b0 = value(dayStart, { $0.b ?? 0 }, withB) { w.boosts = Int((Double(lb) - b0).rounded()) }
            // ultimi 7 giorni MakerWorld
            var dl: [Int] = [], pr: [Int] = [], lk: [Int] = []
            for i in (1...6).reversed() {
                let s0 = dayStart - Double(i) * 86400, s1 = s0 + 86400
                if let a = value(s0, { $0.d }), let b = value(s1, { $0.d }), let pa = value(s0, { $0.p }), let pb = value(s1, { $0.p }),
                   let la = value(s0, { $0.l }), let lb = value(s1, { $0.l }) {
                    dl.append(Int(b - a)); pr.append(Int(pb - pa)); lk.append(Int(lb - la))
                }
            }
            w.spark7Downloads = dl + [w.downloads]; w.spark7Prints = pr + [w.prints]; w.spark7Likes = lk + [w.likes]
            // top modelli di oggi
            let withM = f.samples.filter { $0.m != nil }
            if let lm = withM.last?.m, let (a, b) = around(dayStart, withM), let am = a.m, let bm = b.m {
                let k = a.t == b.t ? 0 : (dayStart - TimeInterval(a.t)) / TimeInterval(b.t - a.t)
                var gains: [(String, Int, Int)] = []
                for (id, v) in lm {
                    guard let va = am[id], let vb = bm[id], v.count > 1, va.count > 1, vb.count > 1 else { continue }
                    let d0 = Double(va[0]) + Double(vb[0] - va[0]) * k, p0 = Double(va[1]) + Double(vb[1] - va[1]) * k
                    let gd = Int((Double(v[0]) - d0).rounded()), gp = Int((Double(v[1]) - p0).rounded())
                    if gd > 0 || gp > 0 { gains.append((id, gd, gp)) }
                }
                gains.sort { $0.1 > $1.1 }
                let titles = await designTitles()
                w.top = gains.prefix(3).map { WidgetData.Top(title: titles[$0.0] ?? "Modello", downloads: $0.1, prints: $0.2) }
            }
            w.updated = Date(timeIntervalSince1970: lastT)
            return
        }

        // Dati dall'app: aggiungo la crescita arrivata dopo l'ultimo aggiornamento dell'app
        guard lastT > w.updated.timeIntervalSince1970 else { return }
        let appSameDay = w.updated.timeIntervalSince1970 >= dayStart
        func gain(_ cur: Int, _ k: @escaping (S) -> Int) -> Int {
            let now = Double(k(last))
            if appSameDay, let base = value(w.updated.timeIntervalSince1970, k) { return cur + Int((now - base).rounded()) }
            if let base = value(dayStart, k) { return Int((now - base).rounded()) }
            return appSameDay ? cur : 0
        }
        w.downloads = gain(w.downloads) { $0.d }
        w.prints = gain(w.prints) { $0.p }
        w.likes = gain(w.likes) { $0.l }
        w.followers = gain(w.followers) { $0.f }
        if !appSameDay { w.pointsToday = 0; w.boosts = 0; w.top = [] }
        w.updated = Date(timeIntervalSince1970: lastT)
    }

    /// Titoli dei modelli pubblici (per i top del giorno).
    static func designTitles() async -> [String: String] {
        struct H: Decodable { let id: Int; let title: String; let titleTranslated: String? }
        struct P: Decodable { let total: Int?; let hits: [H]? }
        var out: [String: String] = [:], off = 0
        while off < 300 {
            guard let u = URL(string: "https://makerworld.com/api/v1/design-service/published/1204206395/design?offset=\(off)&limit=50"),
                  let (d, _) = try? await URLSession.shared.data(from: u),
                  let p = try? JSONDecoder().decode(P.self, from: d), let hits = p.hits, !hits.isEmpty else { break }
            for h in hits { out[String(h.id)] = h.title }
            off += hits.count
            if off >= (p.total ?? 0) { break }
        }
        return out
    }
}
