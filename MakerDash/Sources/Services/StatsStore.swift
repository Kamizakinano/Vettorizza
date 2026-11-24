import Foundation
import UserNotifications

/// Dati salvati per ogni account.
struct AccountData: Codable {
    var snapshot: DailySnapshot?
    var history: [String: ProfileStats] = [:]     // "yyyy-MM-dd" -> ultimo valore del giorno
    var designHistory: [String: [Int: Int]] = [:] // giorno -> (id modello -> downloads)
}

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
    @Published private(set) var data: [String: AccountData] = [:]
    @Published private(set) var designs: [Design] = []
    @Published var error: String?
    @Published var loading = false

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
    func delta(_ kp: KeyPath<ProfileStats, Int>) -> Int {
        guard let s = snapshot else { return 0 }
        return s.latest[keyPath: kp] - s.startOfDay[keyPath: kp]
    }
    func deltaPoints() -> Double {
        guard let s = snapshot else { return 0 }
        return (s.latest.pointsRegular + s.latest.pointsExclusive) - (s.startOfDay.pointsRegular + s.startOfDay.pointsExclusive)
    }
    func delta(design: Design, _ kp: KeyPath<Design, Int>) -> Int {
        guard let start = snapshot?.designsStart[design.id] else { return 0 }
        return design[keyPath: kp] - start[keyPath: kp]
    }

    // MARK: Storico
    struct DayPoint: Identifiable { let date: Date; let value: Int; var id: Date { date } }

    /// Incremento giornaliero di una metrica per gli ultimi `days` giorni.
    func dailyGains(_ kp: KeyPath<ProfileStats, Int>, days: Int) -> [DayPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let h = current.history
        return (0..<days).reversed().compactMap { i -> DayPoint? in
            guard let d = cal.date(byAdding: .day, value: -i, to: today),
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
    func refresh() async {
        guard !handle.isEmpty else { error = "Aggiungi il tuo username in Settings"; return }
        loading = true; defer { loading = false }
        do {
            let page = try await MakerWorldFetcher.shared.fetchProfile(handle: handle)
            let old = stats
            record(ProfileStats(page), designs: page.recentDesigns?.hits ?? [])
            if let old, let new = stats { await notifyMilestones(old: old, new: new) }
            error = nil
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
            acc.snapshot = DailySnapshot(day: day, startOfDay: stats, latest: stats,
                                         designsStart: Dictionary(uniqueKeysWithValues: designs.map { ($0.id, $0) }),
                                         updated: Date())
        }
        acc.history[day] = stats
        acc.designHistory[day] = Dictionary(uniqueKeysWithValues: designs.map { ($0.id, $0.downloadCount) })
        data[handle] = acc
        save()
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
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
}
