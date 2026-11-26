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
    let selfFlag: Bool?
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
    let handle: String?
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

    enum CodingKeys: String, CodingKey {
        case id, title, titleTranslated, coverUrl, cover, likeCount, collectionCount, printCount
        case downloadCount, commentCount, boostCnt, isExclusive, isStaffPicked, publishTime, createTime
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? "#\(id)"
        titleTranslated = try? c.decodeIfPresent(String.self, forKey: .titleTranslated)
        coverUrl = (try? c.decodeIfPresent(String.self, forKey: .coverUrl)) ?? (try? c.decodeIfPresent(String.self, forKey: .cover))
        likeCount = (try? c.decode(Int.self, forKey: .likeCount)) ?? 0
        collectionCount = (try? c.decode(Int.self, forKey: .collectionCount)) ?? 0
        printCount = (try? c.decode(Int.self, forKey: .printCount)) ?? 0
        downloadCount = (try? c.decode(Int.self, forKey: .downloadCount)) ?? 0
        commentCount = (try? c.decode(Int.self, forKey: .commentCount)) ?? 0
        boostCnt = try? c.decodeIfPresent(Int.self, forKey: .boostCnt)
        isExclusive = try? c.decodeIfPresent(Bool.self, forKey: .isExclusive)
        isStaffPicked = try? c.decodeIfPresent(Bool.self, forKey: .isStaffPicked)
        publishTime = (try? c.decodeIfPresent(String.self, forKey: .publishTime)) ?? (try? c.decodeIfPresent(String.self, forKey: .createTime))
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title)
        try c.encodeIfPresent(titleTranslated, forKey: .titleTranslated); try c.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try c.encode(likeCount, forKey: .likeCount); try c.encode(collectionCount, forKey: .collectionCount)
        try c.encode(printCount, forKey: .printCount); try c.encode(downloadCount, forKey: .downloadCount)
        try c.encode(commentCount, forKey: .commentCount); try c.encodeIfPresent(boostCnt, forKey: .boostCnt)
        try c.encodeIfPresent(isExclusive, forKey: .isExclusive); try c.encodeIfPresent(isStaffPicked, forKey: .isStaffPicked)
        try c.encodeIfPresent(publishTime, forKey: .publishTime)
    }
}

/// Risposta di /api/v1/design-service/my/design/published
struct DesignPage: Decodable { let hits: [Design]?; let total: Int? }

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
    var pointsKnown: Bool?

    init(_ p: PageProps) {
        let u = p.userInfo
        followers = u?.fanCount ?? 0
        boosts = u?.boostGained ?? 0
        likes = u?.likeCount ?? 0
        downloads = u?.downloadCount ?? 0
        prints = (u?.MWCount?.myDesignPrintCount ?? 0) + (u?.MWCount?.myInstancePrintCount ?? 0)
        collections = u?.collectionCount ?? 0
        // I punti valgono solo se la sessione (login) appartiene allo stesso profilo.
        let own = p.selfFlag == true &&
            (p.session?.user?.handle?.lowercased() == u?.handle?.lowercased() || u?.handle == nil)
        pointsKnown = own
        pointsRegular = own ? (p.session?.user?.pointRegular ?? u?.point ?? 0) : 0
        pointsExclusive = own ? (p.session?.user?.pointExclusive ?? 0) : 0
    }
}

struct DailySnapshot: Codable {
    var day: String
    var startOfDay: ProfileStats
    var latest: ProfileStats
    var designsStart: [Int: Design]
    var updated: Date
    var created: Date? = nil
}
