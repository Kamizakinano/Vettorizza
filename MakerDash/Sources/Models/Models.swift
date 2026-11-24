import Foundation

// MARK: - Struttura di __NEXT_DATA__ / _next/data/<build>/@handle.json (solo i campi usati)

struct NextData: Decodable { let props: Props?; let pageProps: PageProps?
    struct Props: Decodable { let pageProps: PageProps }
    var page: PageProps? { pageProps ?? props?.pageProps }
}

struct PageProps: Decodable {
    let userInfo: UserInfo?
    let recentDesigns: RecentDesigns?
    let session: Session?
}

struct UserInfo: Decodable {
    let uid: Int
    let name: String
    let handle: String?
    let avatar: String?
    let fanCount: Int
    let likeCount: Int
    let collectionCount: Int
    let downloadCount: Int
    let boostGained: Int?
    let point: Double?
    let MWCount: MWCount?
}

struct MWCount: Decodable {
    let myDesignDownloadCount: Int
    let myInstanceDownloadCount: Int
    let designCount: Int
    let myDesignPrintCount: Int
    let myInstancePrintCount: Int
}

/// Presente solo se sei loggato (contiene i punti divisi Regular/Exclusive).
struct Session: Decodable { let user: SessionUser? }
struct SessionUser: Decodable {
    let point: Double?
    let pointRegular: Double?
    let pointExclusive: Double?
}

struct RecentDesigns: Decodable { let total: Int; let hits: [Design] }

struct Design: Identifiable, Codable {
    let id: Int
    let title: String
    let titleTranslated: String?
    let coverUrl: String?
    let likeCount: Int
    let collectionCount: Int
    let printCount: Int
    let downloadCount: Int
    let commentCount: Int
    let boostCnt: Int?
    let isExclusive: Bool?
    let isStaffPicked: Bool?
    let publishTime: String?
}

// MARK: - Modello interno dell'app

struct ProfileStats: Codable, Equatable {
    var followers: Int
    var boosts: Int
    var likes: Int
    var downloads: Int
    var prints: Int
    var collections: Int
    var pointsRegular: Double
    var pointsExclusive: Double

    init(_ p: PageProps) {
        let u = p.userInfo
        followers = u?.fanCount ?? 0
        boosts = u?.boostGained ?? 0
        likes = u?.likeCount ?? 0
        downloads = u?.downloadCount ?? 0
        prints = (u?.MWCount?.myDesignPrintCount ?? 0) + (u?.MWCount?.myInstancePrintCount ?? 0)
        collections = u?.collectionCount ?? 0
        pointsRegular = p.session?.user?.pointRegular ?? u?.point ?? 0
        pointsExclusive = p.session?.user?.pointExclusive ?? 0
    }
}

struct DailySnapshot: Codable {
    var day: String
    var startOfDay: ProfileStats
    var latest: ProfileStats
    var designsStart: [Int: Design]
    var updated: Date
}
