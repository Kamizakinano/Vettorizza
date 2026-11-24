import Foundation

@MainActor
final class StatsStore: ObservableObject {
    @Published var username: String = UserDefaults.standard.string(forKey: "username") ?? "" {
        didSet { UserDefaults.standard.set(username, forKey: "username") }
    }
    @Published var token: String = UserDefaults.standard.string(forKey: "token") ?? "" {
        didSet { UserDefaults.standard.set(token, forKey: "token") }
    }
    @Published private(set) var snapshot: DailySnapshot?
    @Published private(set) var models: [DesignModel] = []
    @Published var error: String?

    private let snapKey = "dailySnapshot"

    init() {
        if let d = UserDefaults.standard.data(forKey: snapKey) {
            snapshot = try? JSONDecoder().decode(DailySnapshot.self, from: d)
        }
    }

    var today: ProfileStats? { snapshot?.latest }
    func delta(_ kp: KeyPath<ProfileStats, Int>) -> Int {
        guard let s = snapshot else { return 0 }
        return s.latest[keyPath: kp] - s.startOfDay[keyPath: kp]
    }

    func refresh() async {
        guard !username.isEmpty else { error = "Imposta lo username in Settings"; return }
        do {
            let stats: ProfileStats = try await MakerWorldAPI.get(
                MakerWorldAPI.profilePath(username: username), token: token.isEmpty ? nil : token)
            record(stats)
            error = nil
        } catch {
            self.error = "Aggiornamento fallito: \(error.localizedDescription)"
        }
    }

    private func record(_ stats: ProfileStats) {
        let day = Self.dayString(Date())
        if snapshot?.day == day { snapshot?.latest = stats }
        else { snapshot = DailySnapshot(day: day, startOfDay: stats, latest: stats) }
        if let d = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(d, forKey: snapKey) }
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
}
