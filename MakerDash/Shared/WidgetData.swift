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
    struct S: Decodable { let t: Int; let d: Int; let p: Int; let l: Int; let f: Int }
    struct File: Decodable { let samples: [S] }
    static let url = URL(string: "https://raw.githubusercontent.com/kamizakinano/vettorizza/stats-data/hourly/Kamy29.json")!

    /// Aggiorna i numeri di oggi con i controlli orari arrivati dopo l'ultimo aggiornamento dell'app.
    /// Il giorno è quello di MakerWorld (UTC), come nell'app.
    static func merge(into w: inout WidgetData) async {
        var req = URLRequest(url: url, timeoutInterval: 15); req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let f = try? JSONDecoder().decode(File.self, from: d), let last = f.samples.last else { return }
        let lastT = TimeInterval(last.t)
        guard lastT > w.updated.timeIntervalSince1970 else { return }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = utc.startOfDay(for: Date()).timeIntervalSince1970
        func value(_ t: TimeInterval, _ k: (S) -> Int) -> Double? {
            guard let a = f.samples.last(where: { TimeInterval($0.t) <= t }),
                  let b = f.samples.first(where: { TimeInterval($0.t) >= t }),
                  t - TimeInterval(a.t) <= 3 * 3600, TimeInterval(b.t) - t <= 3 * 3600 else { return nil }
            if a.t == b.t { return Double(k(a)) }
            return Double(k(a)) + Double(k(b) - k(a)) * (t - TimeInterval(a.t)) / TimeInterval(b.t - a.t)
        }
        let appSameDay = w.updated.timeIntervalSince1970 >= dayStart
        func gain(_ cur: Int, _ k: @escaping (S) -> Int) -> Int {
            let now = Double(k(last))
            if appSameDay, let base = value(w.updated.timeIntervalSince1970, k) {
                return cur + Int((now - base).rounded())          // dato dell'app + crescita successiva
            }
            if let base = value(dayStart, k) { return Int((now - base).rounded()) } // nuovo giorno
            return appSameDay ? cur : 0
        }
        w.downloads = gain(w.downloads) { $0.d }
        w.prints = gain(w.prints) { $0.p }
        w.likes = gain(w.likes) { $0.l }
        w.followers = gain(w.followers) { $0.f }
        if !appSameDay { w.pointsToday = 0; w.boosts = 0; w.top = [] }
        w.updated = Date(timeIntervalSince1970: lastT)
    }
}
