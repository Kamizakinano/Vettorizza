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
            // Se la pagina non risponde, sblocca dopo 30 secondi
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                if self.waiting[id] != nil { self.finish(v, .failure(URLError(.timedOut))) }
            }
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

    /// Storico giornaliero (ultimo anno) dal Creator Center: richiede il login dell'account.
    /// Storico giornaliero del Creator Center (giorni in UTC). Chiede blocchi da 20 giorni,
    /// perché su intervalli lunghi il Creator Center raggruppa più giorni in una voce.
    func fetchCreatorHistory(handle: String, progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async -> [String: CreatorDay]? {
        let h = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let v = webView(for: h)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = cal.timeZone
        let chunks = 20
        let js = """
        const r = await fetch(`/it/my/data-overview/model?endDate=${e}&startDate=${s}`, {credentials:'include', cache:'no-store'});
        if (!r.ok) return '';
        const html = await r.text();
        const doc = new DOMParser().parseFromString(html, 'text/html');
        const el = doc.getElementById('__NEXT_DATA__'); if (!el) return '';
        const j = JSON.parse(el.textContent);
        const list = j?.props?.pageProps?.statisticalData?.dateList || [];
        const out = {};
        for (const d of list) {
          const k = (d.intervalVal || '').replaceAll('/', '-');
          if (!k) continue;
          out[k] = {follower:d.follower|0, boost:d.boost|0, like:d.like|0, download:d.download|0, print:d.print|0, collect:d.collect|0, point:(d.pointFromModel||0)+(d.pointFromInst||0)};
        }
        return JSON.stringify(out);
        """
        // Una sola richiesta per l'ultimo anno: il Creator Center restituisce comunque una voce per ogni giorno (UTC).
        await progress(0, 1)
        let end = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -399, to: end)!
        defer { Task { await progress(1, 1) } }
        guard let res = try? await v.callAsyncJavaScript(js, arguments: ["e": f.string(from: end), "s": f.string(from: start)], contentWorld: .page),
              let text = res as? String, !text.isEmpty,
              let dict = try? JSONDecoder().decode([String: CreatorDay].self, from: Data(text.utf8)), !dict.isEmpty else { return nil }
        _ = chunks
        return dict
    }

    /// Movimenti punti (guadagnati e spesi). Richiede il login dell'account.
    func fetchPointBills(handle: String, offset: Int, limit: Int = 20) async -> PointBillPage? {
        let h = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let v = webView(for: h)
        let js = """
        const r = await fetch(`/api/v1/point-service/point-bill/my?offset=${o}&limit=${l}&filter=all`, {credentials:'include', cache:'no-store'});
        if (!r.ok) return '';
        const j = await r.json();
        const hits = (j.hits || []).map(x => {
          let t = x.type, d = '';
          const b = x.extInfoBoostExchangePoint, m = x.designRewardV2, i = x.instanceRewardV2;
          if (b) { t = 'Boost'; d = `${b.fromUsername || ''} · ${b.designTitle || ''}`; }
          else if (m) { t = 'Premio modello'; d = m.title || ''; }
          else if (i) { t = 'Premio profilo'; d = `${i.instanceTitle || ''} · ${i.designTitle || ''}`; }
          else if (x.extInfoAcademyCourseAward) { t = 'Academy'; }
          else if (x.extInfoMakerLabFirstExport) { t = 'MakerLab'; }
          else if ((x.type || '').includes('exchange') || (x.type || '').includes('redeem')) { t = 'Riscatto'; d = x.type; }
          return {title: t, detail: d, change: x.pointChange || 0, regular: x.pointChangeRegular || 0,
                  exclusive: x.pointChangeExclusive || 0, time: x.pointTime || x.createTime || ''};
        });
        return JSON.stringify({total: j.total || 0, income: j.totalIncome || 0, expense: j.totalExpense || 0, hits});
        """
        guard let res = try? await v.callAsyncJavaScript(js, arguments: ["o": offset, "l": limit], contentWorld: .page),
              let text = res as? String, !text.isEmpty else { return nil }
        return try? JSONDecoder().decode(PointBillPage.self, from: Data(text.utf8))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in await self.extract(webView, attempt: 0) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(webView, .failure(error)) }
    }
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in self.finish(webView, .failure(URLError(.networkConnectionLost))) }
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
