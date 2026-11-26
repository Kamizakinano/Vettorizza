import Foundation
import UserNotifications
import WidgetKit

/// Dati salvati per ogni account.
struct AccountData: Codable {
    var snapshot: DailySnapshot?
    var history: [String: ProfileStats] = [:]     // "yyyy-MM-dd" -> ultimo valore del giorno
    var designHistory: [String: [Int: Int]] = [:] // giorno -> (id modello -> downloads)
    var designDaily: [String: [Int: DesignCounts]]? = [:] // giorno -> (id -> contatori a fine giorno)
    var designDayStart: [String: [Int: DesignCounts]]? = [:] // giorno -> (id -> contatori a inizio giorno)
    var designInfo: [Int: DesignInfo]? = [:]
    var creatorDaily: [String: CreatorDay]? = [:] // storico ufficiale dal Creator Center
    var prevDayEnd: Date? = nil                    // ora dell'ultimo aggiornamento di ieri
}

/// Incrementi giornalieri dal Creator Center (dateList).
struct CreatorDay: Codable {
    var follower, boost, like, download, print, collect: Int
    var point: Double?
    func value(_ kp: KeyPath<ProfileStats, Int>) -> Int? {
        switch kp {
        case \ProfileStats.followers: return follower
        case \ProfileStats.boosts: return boost
        case \ProfileStats.likes: return like
        case \ProfileStats.downloads: return download
        case \ProfileStats.prints: return print
        case \ProfileStats.collections: return collect
        default: return nil
        }
    }
}

struct DesignCounts: Codable, Equatable {
    var downloads, prints, likes, collections, comments, boosts: Int
    init(_ d: Design) {
        downloads = d.downloadCount; prints = d.printCount; likes = d.likeCount
        collections = d.collectionCount; comments = d.commentCount; boosts = d.boostCnt ?? 0
    }
    init(downloads: Int, prints: Int, likes: Int, collections: Int, comments: Int, boosts: Int) {
        self.downloads = downloads; self.prints = prints; self.likes = likes
        self.collections = collections; self.comments = comments; self.boosts = boosts
    }
    static func - (a: Self, b: Self) -> Self {
        .init(downloads: a.downloads - b.downloads, prints: a.prints - b.prints, likes: a.likes - b.likes,
              collections: a.collections - b.collections, comments: a.comments - b.comments, boosts: a.boosts - b.boosts)
    }
    var isZero: Bool { downloads == 0 && prints == 0 && likes == 0 && collections == 0 && comments == 0 && boosts == 0 }
}

struct DesignInfo: Codable { var title: String; var cover: String? }

@MainActor
final class StatsStore: ObservableObject {
    @Published var accounts: [String] = (UserDefaults.standard.stringArray(forKey: "accounts") ?? []) {
        didSet { UserDefaults.standard.set(accounts, forKey: "accounts") }
    }
    @Published var handle: String = UserDefaults.standard.string(forKey: "handle") ?? "" {
        didSet { UserDefaults.standard.set(handle, forKey: "handle") }
    }
    @Published var defaultTab: Int = UserDefaults.standard.integer(forKey: "defaultTab") {
        didSet { UserDefaults.standard.set(defaultTab, forKey: "defaultTab") }
    }
    @Published var notificationsOn: Bool = UserDefaults.standard.bool(forKey: "notificationsOn") {
        didSet { UserDefaults.standard.set(notificationsOn, forKey: "notificationsOn") }
    }
    @Published private(set) var data: [String: AccountData] = [:] { didSet { gainsCache.removeAll() } }
    private var gainsCache: [String: [DayPoint]] = [:]
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    @Published private(set) var designs: [Design] = []
    @Published var error: String?
    @Published var loading = false
    /// Avanzamento dello scaricamento dello storico Creator Center (0...1), nil se fermo.
    @Published var historyProgress: Double?
    private var loadingSince: Date?

    private let key = "accountData.v2"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let v = try? JSONDecoder().decode([String: AccountData].self, from: d) { data = v }
        if let old = UserDefaults.standard.string(forKey: "handle"), !old.isEmpty, !accounts.contains(old) {
            accounts.append(old)
        }
    }

    var current: AccountData { data[handle] ?? AccountData() }
    var snapshot: DailySnapshot? { current.snapshot }
    var stats: ProfileStats? { snapshot?.latest }

    // MARK: Account
    func addAccount(_ h: String) {
        let h = h.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        guard !h.isEmpty else { return }
        if !accounts.contains(h) { accounts.append(h) }
        handle = h
    }
    func removeAccount(_ h: String) {
        accounts.removeAll { $0 == h }
        data[h] = nil; save()
        if handle == h { handle = accounts.first ?? "" }
    }

    // MARK: Delta giornalieri
    /// Campioni orari (GitHub) per fissare esattamente la mezzanotte. Solo per Kamy29.
    @Published var hourly: [HourlySample] = {
        if let d = UserDefaults.standard.data(forKey: "hourly.Kamy29"),
           let f = try? JSONDecoder().decode(HourlyFile.self, from: d) { return f.samples.sorted { $0.t < $1.t } }
        return []
    }() { didSet { gainsCache.removeAll() } }

    func loadHourly() async {
        var req = URLRequest(url: HourlyStore.url); req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let f = try? JSONDecoder().decode(HourlyFile.self, from: d) else { return }
        UserDefaults.standard.set(d, forKey: "hourly.Kamy29")
        hourly = f.samples.sorted { $0.t < $1.t }
    }

    /// Valore orario interpolato a una certa data (nil se non ci sono campioni entro 3 ore prima e dopo).
    private func hourlyValue(_ kp: KeyPath<ProfileStats, Int>, at date: Date) -> Double? {
        let f: (HourlySample) -> Int
        switch kp {
        case \ProfileStats.downloads: f = { $0.d }
        case \ProfileStats.prints: f = { $0.p }
        case \ProfileStats.likes: f = { $0.l }
        case \ProfileStats.collections: f = { $0.c }
        case \ProfileStats.followers: f = { $0.f }
        case \ProfileStats.boosts: f = { $0.b ?? 0 }; if hourly.last?.b == nil { return nil }
        default: return nil
        }
        let t = date.timeIntervalSince1970
        let pool = kp == \ProfileStats.boosts ? hourly.filter { $0.b != nil } : hourly
        guard let a = pool.last(where: { TimeInterval($0.t) <= t }),
              let b = pool.first(where: { TimeInterval($0.t) >= t }),
              t - TimeInterval(a.t) <= 3 * 3600, TimeInterval(b.t) - t <= 3 * 3600 else { return nil }
        if a.t == b.t { return Double(f(a)) }
        return Double(f(a)) + Double(f(b) - f(a)) * (t - TimeInterval(a.t)) / TimeInterval(b.t - a.t)
    }

    /// Il Creator Center di MakerWorld usa giorni in UTC (GMT): in Italia dall'01:00 all'01:00 (02:00 con l'ora legale).
    private static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    /// Inizio (mezzanotte UTC) del giorno con questa etichetta.
    func windowStart(_ label: Date) -> Date {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: label)
        return Self.utc.date(from: c) ?? label
    }
    /// Etichetta (mezzanotte locale) del giorno MakerWorld in corso.
    var todayLabel: Date {
        Calendar.current.date(from: Self.utc.dateComponents([.year, .month, .day], from: Date())) ?? Calendar.current.startOfDay(for: Date())
    }
    /// Inizio del giorno MakerWorld in corso.
    var dayStart: Date { Self.utc.startOfDay(for: Date()) }

    /// Orario italiano a cui inizia il giorno MakerWorld (01:00 o 02:00 con l'ora legale).
    var ccDayDescription: String? { dayStart.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()) }

    /// Contatori di un modello interpolati a mezzanotte di oggi (dai campioni orari).
    func designAtMidnight(_ id: Int) -> DesignCounts? {
        guard handle.lowercased() == "kamy29" else { return nil }
        let t = dayStart.timeIntervalSince1970
        let pool = hourly.filter { $0.m?[String(id)] != nil }
        guard let a = pool.last(where: { TimeInterval($0.t) <= t }), let b = pool.first(where: { TimeInterval($0.t) >= t }),
              t - TimeInterval(a.t) <= 3 * 3600, TimeInterval(b.t) - t <= 3 * 3600,
              let va = a.m?[String(id)], let vb = b.m?[String(id)], va.count >= 5, vb.count >= 5 else { return nil }
        let k = a.t == b.t ? 0 : (t - TimeInterval(a.t)) / TimeInterval(b.t - a.t)
        func v(_ i: Int) -> Int { Int((Double(va[i]) + Double(vb[i] - va[i]) * k).rounded()) }
        return DesignCounts(downloads: v(0), prints: v(1), likes: v(2), collections: v(3), comments: 0, boosts: v(4))
    }

    /// Punti ricevuti oggi (da mezzanotte) dai movimenti punti; nil se non disponibili.
    @Published var pointsTodayIncome: Double?
    private var pointsTodayDay: String?

    /// Incremento di oggi da mezzanotte a ora.
    /// 1) con i campioni orari: valore alla prima apertura di oggi meno quanto è cresciuto da mezzanotte a quel momento;
    /// 2) altrimenti interpolo tra l'ultimo valore di ieri e il primo di oggi;
    /// 3) altrimenti dalla prima apertura di oggi.
    func delta(_ kp: KeyPath<ProfileStats, Int>) -> Int {
        guard let s = snapshot else { return 0 }
        let cal = Calendar.current, midnight = dayStart
        let first = Double(s.startOfDay[keyPath: kp])
        var base = first
        let useHourly = handle.lowercased() == "kamy29"
        if useHourly, let t1 = s.created, let h1 = hourlyValue(kp, at: t1), let h0 = hourlyValue(kp, at: midnight) {
            base = first - (h1 - h0)
        } else if useHourly, s.created == nil, let h0 = hourlyValue(kp, at: midnight), let last = hourly.last,
                  let hl = hourlyValue(kp, at: Date(timeIntervalSince1970: TimeInterval(last.t))) {
            // primo giorno dopo l'aggiornamento: crescita oraria da mezzanotte all'ultimo campione
            return Int((hl - h0).rounded())
        } else if let y = cal.date(byAdding: .day, value: -1, to: midnight),
           let prev = current.history[Self.dayString(y)],
           let t0 = current.prevDayEnd, let t1 = s.created, t1 > t0, t0 < midnight, t1 >= midnight {
            let p = Double(prev[keyPath: kp])
            base = p + (first - p) * midnight.timeIntervalSince(t0) / t1.timeIntervalSince(t0)
        }
        return Int((Double(s.latest[keyPath: kp]) - base).rounded())
    }

    func deltaPoints() -> Double {
        if let p = pointsTodayIncome, pointsTodayDay == Self.dayString(Date()) { return p }
        guard let s = snapshot else { return 0 }
        return (s.latest.pointsRegular + s.latest.pointsExclusive) - (s.startOfDay.pointsRegular + s.startOfDay.pointsExclusive)
    }

    /// Somma dei punti entrati oggi dalle voci dello storico punti (esattamente da mezzanotte).
    func loadPointsToday(_ h: String, enabled: Bool) async {
        guard enabled else { return }
        let midnight = dayStart
        var sum = 0.0, off = 0
        while off < 500 {
            guard let page = await MakerWorldFetcher.shared.fetchPointBills(handle: h, offset: off, limit: 50) else { return }
            var older = false
            for b in page.hits {
                guard let d = b.date else { continue }
                if d < midnight { older = true; break }
                if b.change > 0 { sum += b.change }
            }
            off += page.hits.count
            if older || page.hits.isEmpty || off >= page.total { break }
        }
        if h == handle { pointsTodayIncome = sum; pointsTodayDay = Self.dayString(Date()) }
    }
    func delta(design: Design, _ kp: KeyPath<Design, Int>) -> Int {
        guard let start = snapshot?.designsStart[design.id] else { return 0 }
        return design[keyPath: kp] - start[keyPath: kp]
    }

    // MARK: Storico
    struct DayPoint: Identifiable { let date: Date; let value: Int; var id: Date { date } }

    /// Incremento giornaliero di una metrica per gli ultimi `days` giorni.
    func dailyGains(_ kp: KeyPath<ProfileStats, Int>, days: Int) -> [DayPoint] {
        let key = "\(handle)|\(kp.hashValue)|\(days)|\(Self.dayString(Date()))|\(snapshot?.updated.timeIntervalSince1970 ?? 0)"
        if let c = gainsCache[key] { return c }
        let r = computeGains(kp, days: days)
        gainsCache[key] = r
        return r
    }

    private func computeGains(_ kp: KeyPath<ProfileStats, Int>, days: Int) -> [DayPoint] {
        let cal = Calendar.current
        let today = todayLabel
        let h = current.history
        let cd = current.creatorDaily ?? [:]
        let useHourlyDays = handle.lowercased() == "kamy29"
        return (0..<days).reversed().compactMap { i -> DayPoint? in
            guard let d0 = cal.date(byAdding: .day, value: -i, to: today) else { return nil }
            // oggi: stesso valore mostrato in Stats
            if i == 0 { return snapshot != nil ? DayPoint(date: d0, value: delta(kp)) : nil }
            if i > 0, useHourlyDays, cd[Self.dayString(d0)] == nil,
               let a = hourlyValue(kp, at: windowStart(d0)), let b = hourlyValue(kp, at: windowStart(d0).addingTimeInterval(86400)) {
                // giorno coperto dai controlli orari: esattamente da mezzanotte a mezzanotte (ora italiana)
                return DayPoint(date: d0, value: Int((b - a).rounded()))
            }
            // Creator Center: l'ultimo giorno che restituisce è ancora in corso (cambia a ogni ricarica), lo salto
            if i > 0, let c = cd[Self.dayString(d0)], let v = c.value(kp) { return DayPoint(date: d0, value: v) }
            guard let d = Optional(d0),
                  let prev = cal.date(byAdding: .day, value: -1, to: d),
                  let cur = h[Self.dayString(d)] else { return nil }
            if let p = h[Self.dayString(prev)] {
                return DayPoint(date: d, value: cur[keyPath: kp] - p[keyPath: kp])
            }
            // Primo giorno registrato: usa l'incremento interno al giorno se disponibile
            if Self.dayString(d) == snapshot?.day, let s = snapshot {
                return DayPoint(date: d, value: s.latest[keyPath: kp] - s.startOfDay[keyPath: kp])
            }
            return nil
        }
    }

    struct DesignDay: Identifiable { let id: Int; let title: String; let cover: String?; let gain: DesignCounts; let total: DesignCounts }

    /// Modelli con attività in un giorno: incremento rispetto al giorno precedente registrato
    /// (o all'inizio della giornata se è il primo giorno disponibile).
    func designs(on date: Date) -> [DesignDay] {
        let acc = current
        let day = Self.dayString(date)
        guard let end = acc.designDaily?[day] else { return [] }
        let prevDays = (acc.designDaily ?? [:]).keys.filter { $0 < day }.sorted()
        let prev = prevDays.last.flatMap { acc.designDaily?[$0] }
        let start = acc.designDayStart?[day] ?? [:]
        let isToday = day == Self.dayString(Date())
        return end.compactMap { id, e -> DesignDay? in
            guard let base = (isToday ? designAtMidnight(id) : nil) ?? prev?[id] ?? start[id] else { return nil }
            let g = e - base
            guard !g.isZero else { return nil }
            let i = acc.designInfo?[id]
            return DesignDay(id: id, title: i?.title ?? "#\(id)", cover: i?.cover, gain: g, total: e)
        }.sorted { ($0.gain.downloads, $0.gain.prints) > ($1.gain.downloads, $1.gain.prints) }
    }

    /// Modelli attivi in un intervallo (somma dei giorni).
    func designs(in interval: DateInterval) -> [DesignDay] {
        let cal = Calendar.current
        var d = cal.startOfDay(for: interval.start)
        var acc: [Int: DesignDay] = [:]
        while d < interval.end && d <= Date() {
            for x in designs(on: d) {
                if let o = acc[x.id] {
                    acc[x.id] = DesignDay(id: x.id, title: x.title, cover: x.cover,
                                          gain: DesignCounts(downloads: o.gain.downloads + x.gain.downloads, prints: o.gain.prints + x.gain.prints,
                                                             likes: o.gain.likes + x.gain.likes, collections: o.gain.collections + x.gain.collections,
                                                             comments: o.gain.comments + x.gain.comments, boosts: o.gain.boosts + x.gain.boosts),
                                          total: x.total)
                } else { acc[x.id] = x }
            }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return acc.values.sorted { ($0.gain.downloads, $0.gain.prints) > ($1.gain.downloads, $1.gain.prints) }
    }

    /// Somma degli incrementi di una metrica in un intervallo.
    func sum(_ kp: KeyPath<ProfileStats, Int>, in interval: DateInterval) -> Int {
        dailyGains(kp, days: 800).filter { $0.date >= interval.start && $0.date < interval.end }.map(\.value).reduce(0, +)
    }

    /// Media punti al giorno degli ultimi `days` giorni completi (dal Creator Center).
    func pointsPerDay(days: Int) -> Double? {
        let cd = current.creatorDaily ?? [:]
        let cal = Calendar.current, today = todayLabel
        let vals = (1...days).compactMap { i in
            cal.date(byAdding: .day, value: -i, to: today).flatMap { cd[Self.dayString($0)]?.point }
        }
        guard vals.count >= max(3, days / 2) else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Primo giorno con dati registrati.
    var firstRecordedDay: Date? {
        (Array(current.history.keys) + Array((current.creatorDaily ?? [:]).keys)).min().flatMap { k -> Date? in
            Self.dayFormatter.date(from: k)
        }
    }

    enum Grouping: String, CaseIterable { case giorno = "Giorno", settimana = "Settimana", mese = "Mese", anno = "Anno" }

    /// Somma degli incrementi raggruppati per giorno/settimana/mese/anno.
    func grouped(_ kp: KeyPath<ProfileStats, Int>, days: Int, by g: Grouping) -> [DayPoint] {
        let pts = dailyGains(kp, days: days)
        guard g != .giorno else { return pts }
        let cal = Calendar.current
        let comp: Calendar.Component = g == .settimana ? .weekOfYear : g == .mese ? .month : .year
        var sums: [Date: Int] = [:]
        for p in pts {
            let start = cal.dateInterval(of: comp, for: p.date)?.start ?? p.date
            sums[start, default: 0] += p.value
        }
        return sums.map { DayPoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }

    /// Totale guadagnato nel periodo corrente (oggi, questa settimana, questo mese, quest'anno).
    func total(_ kp: KeyPath<ProfileStats, Int>, in comp: Calendar.Component) -> Int {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: comp, for: Date())?.start else { return 0 }
        return dailyGains(kp, days: 366).filter { $0.date >= start }.map(\.value).reduce(0, +)
    }

    /// Variazione % della somma degli ultimi 7 giorni rispetto ai 7 precedenti.
    func weekChange(_ kp: KeyPath<ProfileStats, Int>) -> Double? {
        let g = dailyGains(kp, days: 14)
        guard g.count >= 8 else { return nil }
        let cut = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date()))!
        let recent = g.filter { $0.date > cut }.map(\.value).reduce(0, +)
        let before = g.filter { $0.date <= cut }.map(\.value).reduce(0, +)
        guard before > 0 else { return nil }
        return Double(recent - before) / Double(before) * 100
    }

    // MARK: Insight
    struct Insight: Identifiable { let id = UUID(); let icon: String; let title: String; let text: String; let positive: Bool }

    var insights: [Insight] {
        var out: [Insight] = []
        for (name, kp) in [("Download", \ProfileStats.downloads), ("Stampe", \.prints), ("Follower", \.followers), ("Like", \.likes)] {
            if let c = weekChange(kp), abs(c) >= 10 {
                out.append(Insight(icon: c > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                                   title: "\(name) \(c > 0 ? "in aumento" : "in calo") questa settimana",
                                   text: "\(c > 0 ? "+" : "")\(Int(c))% rispetto ai 7 giorni precedenti.",
                                   positive: c > 0))
            }
        }
        if let top = designs.max(by: { $0.downloadCount < $1.downloadCount }) {
            let tot = max(1, designs.map(\.downloadCount).reduce(0, +))
            out.append(Insight(icon: "trophy", title: "Modello più scaricato",
                               text: "\(top.title): \(top.downloadCount) download (\(top.downloadCount * 100 / tot)% dei modelli in lista).",
                               positive: true))
        }
        if let hot = designs.max(by: { delta(design: $0, \.downloadCount) < delta(design: $1, \.downloadCount) }),
           delta(design: hot, \.downloadCount) > 0 {
            out.append(Insight(icon: "flame", title: "In tendenza oggi",
                               text: "\(hot.title): +\(delta(design: hot, \.downloadCount)) download oggi. Buon momento per condividerlo.",
                               positive: true))
        }
        for d in designs where d.downloadCount >= 20 {
            let ratio = Double(d.printCount) / Double(d.downloadCount)
            if ratio < 0.15 {
                out.append(Insight(icon: "exclamationmark.triangle", title: "Pochi stampano dopo il download",
                                   text: "\(d.title): solo \(Int(ratio * 100))% dei download diventa una stampa. Prova a migliorare il profilo di stampa.",
                                   positive: false))
                break
            }
        }
        if out.isEmpty {
            out.append(Insight(icon: "hourglass", title: "Sto raccogliendo dati",
                               text: "Gli insight settimanali compaiono dopo qualche giorno di utilizzo.", positive: true))
        }
        return out
    }

    // MARK: Aggiornamento
    /// Aggiorna solo se i dati hanno più di `seconds` secondi (per l'apertura delle schermate).
    func refreshIfStale(_ seconds: TimeInterval = 120) async {
        if let u = snapshot?.updated, Date().timeIntervalSince(u) < seconds { return }
        await refresh()
    }

    func refresh() async {
        guard !handle.isEmpty else { error = "Aggiungi il tuo username in Settings"; return }
        // evita due aggiornamenti in parallelo, ma non restare bloccato se uno si è piantato
        if loading, let t = loadingSince, Date().timeIntervalSince(t) < 120 { return }
        loading = true; loadingSince = Date()
        defer { loading = false; loadingSince = nil }
        let h = handle
        do {
            let page = try await MakerWorldFetcher.shared.fetchProfile(handle: handle)
            let old = stats
            // Profilo subito a schermo, poi modelli e storico in parallelo
            record(ProfileStats(page), designs: designs.isEmpty ? (page.recentDesigns?.hits ?? []) : designs)
            async let allReq = MakerWorldFetcher.shared.fetchAllDesigns(handle: h)
            async let histReq = MakerWorldFetcher.shared.fetchCreatorHistory(handle: h) { [weak self] i, n in self?.historyProgress = i < n ? Double(i) / Double(n) : nil }
            async let hourlyReq: Void = loadHourly()
            let known = ProfileStats(page).pointsKnown == true
            async let ptsReq: Void = loadPointsToday(h, enabled: known)
            let (all, histRes, _, _) = await (allReq, histReq, hourlyReq, ptsReq)
            if let all, h == handle { record(ProfileStats(page), designs: all) }
            if let hist = histRes {
                var acc = data[h] ?? AccountData(); acc.creatorDaily = hist; data[h] = acc; save()
            }
            if let old, let new = stats { await notifyMilestones(old: old, new: new) }
            updateWidget()
            error = nil
        } catch is CancellationError {
            // aggiornamento sostituito da uno nuovo: nessun errore da mostrare
        } catch {
            self.error = "Aggiornamento fallito: \(error.localizedDescription)"
        }
    }

    private func record(_ stats: ProfileStats, designs: [Design]) {
        self.designs = designs
        var acc = current
        let day = Self.dayString(Date())
        if var s = acc.snapshot, s.day == day {
            s.latest = stats
            for d in designs where s.designsStart[d.id] == nil { s.designsStart[d.id] = d }
            s.updated = Date()
            acc.snapshot = s
        } else {
            acc.prevDayEnd = acc.snapshot?.updated
            acc.snapshot = DailySnapshot(day: day, startOfDay: stats, latest: stats,
                                         designsStart: Dictionary(uniqueKeysWithValues: designs.map { ($0.id, $0) }),
                                         updated: Date(), created: Date())
        }
        acc.history[day] = stats
        acc.designHistory[day] = Dictionary(uniqueKeysWithValues: designs.map { ($0.id, $0.downloadCount) })
        var daily = acc.designDaily ?? [:], starts = acc.designDayStart ?? [:], info = acc.designInfo ?? [:]
        var st = starts[day] ?? [:]
        for d in designs {
            if st[d.id] == nil { st[d.id] = DesignCounts(d) }
            info[d.id] = DesignInfo(title: (d.titleTranslated?.isEmpty == false ? d.titleTranslated! : d.title), cover: d.coverUrl)
        }
        starts[day] = st
        daily[day] = Dictionary(uniqueKeysWithValues: designs.map { ($0.id, DesignCounts($0)) })
        acc.designDaily = daily; acc.designDayStart = starts; acc.designInfo = info
        data[handle] = acc
        save()
    }

    /// Salva i dati per il widget (account Kamy29) e lo aggiorna.
    func updateWidget() {
        let wh = accounts.first { $0.lowercased() == "kamy29" } ?? handle
        guard handle == wh, let st = stats else { return }
        let cal = Calendar.current, today = todayLabel
        let cd = current.creatorDaily ?? [:]
        var p14: [Double] = (1..<14).reversed().compactMap { i in
            cal.date(byAdding: .day, value: -i, to: today).flatMap { cd[Self.dayString($0)]?.point }
        }
        p14.append(deltaPoints())
        let top = designs(in: cal.dateInterval(of: .day, for: Date())!).prefix(3).map {
            WidgetData.Top(title: $0.title, downloads: $0.gain.downloads, prints: $0.gain.prints)
        }
        let w = WidgetData(updated: snapshot?.updated ?? Date(), handle: wh,
                           points: st.pointsKnown == true ? st.pointsRegular + st.pointsExclusive : nil,
                           pointsToday: deltaPoints(), perDay: pointsPerDay(days: 7),
                           downloads: delta(\.downloads), prints: delta(\.prints), likes: delta(\.likes),
                           followers: delta(\.followers), boosts: delta(\.boosts),
                           spark7Downloads: dailyGains(\.downloads, days: 7).map(\.value),
                           spark7Prints: dailyGains(\.prints, days: 7).map(\.value),
                           spark7Likes: dailyGains(\.likes, days: 7).map(\.value),
                           points14: p14, top: Array(top))
        w.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { UserDefaults.standard.set(d, forKey: key) }
    }

    // MARK: Notifiche
    func requestNotifications() async {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsOn = ok
    }

    private func notifyMilestones(old: ProfileStats, new: ProfileStats) async {
        guard notificationsOn else { return }
        func crossed(_ a: Int, _ b: Int, step: Int) -> Int? { b / step > a / step ? (b / step) * step : nil }
        var msgs: [String] = []
        if let m = crossed(old.followers, new.followers, step: 100) { msgs.append("Hai raggiunto \(m) follower! 🎉") }
        if let m = crossed(old.downloads, new.downloads, step: 1000) { msgs.append("Hai superato \(m) download totali!") }
        if let m = crossed(old.prints, new.prints, step: 500) { msgs.append("Hai superato \(m) stampe!") }
        if let m = crossed(old.boosts, new.boosts, step: 10) { msgs.append("Sei arrivato a \(m) boost ricevuti!") }
        if new.boosts > old.boosts && msgs.isEmpty { msgs.append("Hai ricevuto \(new.boosts - old.boosts) nuovi boost ⚡") }
        for m in msgs {
            let c = UNMutableNotificationContent()
            c.title = "MakerDash · \(handle)"; c.body = m; c.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
