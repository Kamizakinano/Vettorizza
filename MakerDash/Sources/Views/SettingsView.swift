import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject var store: StatsStore
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account MakerWorld") {
                    TextField("Username (es. Kamy29)", text: $store.handle)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Accedi a MakerWorld (per i punti)") { showLogin = true }
                }
                Section { Button("Aggiorna ora") { Task { await store.refresh() } } }
                Section {
                    Text("Senza login vedi le statistiche pubbliche. Con il login l'app legge anche i punti Regular/Exclusive. Il login avviene direttamente su makerworld.com: l'app non vede la tua password.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showLogin) {
                NavigationStack {
                    LoginWebView()
                        .navigationTitle("Login MakerWorld")
                        .toolbar { Button("Fatto") { showLogin = false; Task { await store.refresh() } } }
                }
            }
        }
    }
}

/// Mostra lo stesso WKWebView usato per il fetch, così i cookie del login restano condivisi.
struct LoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let wv = MakerWorldFetcher.shared.webView
        wv.load(URLRequest(url: URL(string: "https://makerworld.com/it")!))
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
