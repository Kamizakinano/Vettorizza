import Foundation
import WebKit

/// Un WKWebView invisibile per ogni account, ciascuno con i propri cookie (login separati).
/// Carica la pagina profilo e legge il JSON __NEXT_DATA__.
@MainActor
final class MakerWorldFetcher: NSObject, WKNavigationDelegate {
    static let shared = MakerWorldFetcher()
    private var views: [String: WKWebView] = [:]
    private var waiting: [ObjectIdentifier: CheckedContinuation<PageProps, Error>] = [:]

    private func storeID(for handle: String) -> UUID {
        let key = "store.\(handle.lowercased())"
        if let s = UserDefaults.standard.string(forKey: key), let u = UUID(uuidString: s) { return u }
        let u = UUID(); UserDefaults.standard.set(u.uuidString, forKey: key); return u
    }

    func webView(for handle: String) -> WKWebView {
        if let v = views[handle.lowercased()] { return v }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID(for: handle))
        let v = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: cfg)
        v.navigationDelegate = self
        views[handle.lowercased()] = v
        return v
    }

    func logout(handle: String) async {
        let v = webView(for: handle)
        let store = v.configuration.websiteDataStore
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records)
    }

    func fetchProfile(handle: String) async throws -> PageProps {
        let h = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let ts = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://makerworld.com/it/@\(h)?_t=\(ts)")!
        let v = webView(for: h)
        return try await withCheckedThrowingContinuation { c in
            let id = ObjectIdentifier(v)
            waiting[id]?.resume(throwing: CancellationError())
            waiting[id] = c
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
            req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            req.setValue("no-cache", forHTTPHeaderField: "Pragma")
            v.load(req)
        }
    }

    /// Scarica tutti i modelli pubblicati, 20 alla volta, dall'interno della pagina (stessi cookie).
    func fetchAllDesigns(handle: String) async -> [Design]? {
        let h = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let v = webView(for: h)
        let js = """
        const out = []; let off = 0;
        for (let i = 0; i < 50; i++) {
          const r = await fetch(`/api/v1/design-service/my/design/published?handle=%40${h}&limit=20&offset=${off}`,
                                {credentials: 'include', cache: 'no-store'});
          if (!r.ok) break;
          const j = await r.json();
          const hits = j.hits || [];
          out.push(...hits);
          off += hits.length;
          if (hits.length < 20 || (j.total && off >= j.total)) break;
        }
        return JSON.stringify(out);
        """
        guard let res = try? await v.callAsyncJavaScript(js, arguments: ["h": h], contentWorld: .page),
              let text = res as? String,
              let arr = try? JSONDecoder().decode([Design].self, from: Data(text.utf8)),
              !arr.isEmpty else { return nil }
        return arr
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in await self.extract(webView, attempt: 0) }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(webView, .failure(error)) }
    }

    private func extract(_ v: WKWebView, attempt: Int) async {
        guard waiting[ObjectIdentifier(v)] != nil else { return } // navigazione di login, non un fetch
        let js = "document.getElementById('__NEXT_DATA__') ? document.getElementById('__NEXT_DATA__').textContent : ''"
        let text = (try? await v.evaluateJavaScript(js) as? String) ?? ""
        if text.isEmpty {
            if attempt < 6 { try? await Task.sleep(for: .seconds(2)); await extract(v, attempt: attempt + 1) }
            else { finish(v, .failure(URLError(.cannotParseResponse))) }
            return
        }
        do {
            let next = try JSONDecoder().decode(NextData.self, from: Data(text.utf8))
            guard let page = next.page else { throw URLError(.cannotParseResponse) }
            finish(v, .success(page))
        } catch { finish(v, .failure(error)) }
    }

    private func finish(_ v: WKWebView, _ r: Result<PageProps, Error>) {
        waiting.removeValue(forKey: ObjectIdentifier(v))?.resume(with: r)
    }
}
