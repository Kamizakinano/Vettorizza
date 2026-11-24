import Foundation

struct ProfileStats: Codable, Equatable {
    var followers: Int
    var boosts: Int
    var likes: Int
    var downloads: Int
    var prints: Int
}

struct DesignModel: Codable, Identifiable {
    var id: Int
    var title: String
    var coverURL: URL?
    var likes: Int
    var downloads: Int
    var prints: Int
    var boosts: Int
}

/// Snapshot salvato per calcolare le variazioni giornaliere (reset a mezzanotte).
struct DailySnapshot: Codable {
    var day: String          // yyyy-MM-dd
    var startOfDay: ProfileStats
    var latest: ProfileStats
}
