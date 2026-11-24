import Foundation

@MainActor
final class StatsStore: ObservableObject {
    @Published var handle: String = UserDefaults.standard.string(forKey: "handle") ?? "" {
        didSet { UserDefaults.standard.set(handle, forKey: "handle") }
    }
    @Published private(set) var snapshot: DailySnapshot?
    @Published private(set) var designs: [Design] = []
    @Published private(set) var avatar: URL?
    @Published var error: String?
    @Published var loading = false

    private let key = "dailySnapshot"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(DailySnapshot.self, from: d) { snapshot = s }
    }

    var stats: ProfileStats? { snapshot?.latest }

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

    func refresh() async {
        guard !handle.isEmpty else { error = "Imposta il tuo username in Settings"; return }
        loading = true; defer { loading = false }
        do {
            let page = try await MakerWorldFetcher.shared.fetchProfile(handle: handle)
            record(ProfileStats(page), designs: page.recentDesigns?.hits ?? [])
            avatar = page.userInfo?.avatar.flatMap(URL.init(string:))
            error = nil
        } catch {
            self.error = "Aggiornamento fallito: \(error.localizedDescription)"
        }
    }

    private func record(_ stats: ProfileStats, designs: [Design]) {
        self.designs = designs
        let day = Self.dayString(Date())
        if var s = snapshot, s.day == day {
            s.latest = stats
            for d in designs where s.designsStart[d.id] == nil { s.designsStart[d.id] = d }
            s.updated = Date()
            snapshot = s
        } else {
            snapshot = DailySnapshot(day: day, startOfDay: stats, latest: stats,
                                     designsStart: Dictionary(uniqueKeysWithValues: designs.map { ($0.id, $0) }),
                                     updated: Date())
        }
        if let d = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(d, forKey: key) }
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
}
