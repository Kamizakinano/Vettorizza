import Foundation

/// Client per gli endpoint interni di MakerWorld (non documentati).
/// ⚠️ Gli URL vanno verificati catturando le richieste del sito con DevTools → Network.
enum MakerWorldAPI {
    static let base = URL(string: "https://makerworld.com")!

    /// TODO: sostituire con l'endpoint reale del profilo (catturato dal browser).
    static func profilePath(username: String) -> String { "/api/v1/design-user-service/profile/\(username)" }
    /// TODO: endpoint reale della lista modelli dell'utente.
    static func designsPath(uid: String) -> String { "/api/v1/design-service/published/\(uid)/design" }

    static func get<T: Decodable>(_ path: String, token: String?) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
