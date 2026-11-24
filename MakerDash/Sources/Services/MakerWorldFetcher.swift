import Foundation
import WebKit

/// Usa un WKWebView invisibile: condivide i cookie del login MakerWorld e supera Cloudflare
/// come un normale browser. Carica la pagina profilo e legge il JSON __NEXT_DATA__.
@MainActor
final class MakerWorldFetcher: NSObject, WKNavigationDelegate {
    static let shared = MakerWorldFetcher()
    let webView: WKWebView
    private var continuation: CheckedContinuation<PageProps, Error>?

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()   // cookie persistenti = resti loggato
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: cfg)
        super.init()
        webView.navigationDelegate = self
    }

    func fetchProfile(handle: String) async throws -> PageProps {
        let h = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let ts = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://makerworld.com/it/@\(h)?_t=\(ts)")!
        return try await withCheckedThrowingContinuation { c in
            continuation?.resume(throwing: CancellationError())
            continuation = c
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
            req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            req.setValue("no-cache", forHTTPHeaderField: "Pragma")
            webView.load(req)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in await self.extract(attempt: 0) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }

    private func extract(attempt: Int) async {
        let js = "document.getElementById('__NEXT_DATA__') ? document.getElementById('__NEXT_DATA__').textContent : ''"
        let text = (try? await webView.evaluateJavaScript(js) as? String) ?? ""
        if text.isEmpty {
            // Probabile pagina Cloudflare "Just a moment...": riprova dopo qualche secondo.
            if attempt < 6 {
                try? await Task.sleep(for: .seconds(2))
                await extract(attempt: attempt + 1)
            } else { finish(.failure(URLError(.cannotParseResponse))) }
            return
        }
        do {
            let next = try JSONDecoder().decode(NextData.self, from: Data(text.utf8))
            guard let page = next.page else { throw URLError(.cannotParseResponse) }
            finish(.success(page))
        } catch { finish(.failure(error)) }
    }

    private func finish(_ r: Result<PageProps, Error>) {
        continuation?.resume(with: r)
        continuation = nil
    }
}
