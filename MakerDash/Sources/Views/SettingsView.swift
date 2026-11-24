import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject var store: StatsStore
    @State private var showLogin = false
    @State private var newHandle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account MakerWorld") {
                    ForEach(store.accounts, id: \.self) { a in
                        HStack {
                            Text(a)
                            Spacer()
                            if a == store.handle { Image(systemName: "checkmark").foregroundStyle(.green) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { store.handle = a; Task { await store.refresh() } }
                    }
                    .onDelete { idx in idx.map { store.accounts[$0] }.forEach(store.removeAccount) }
                    HStack {
                        TextField("Aggiungi username (es. Kamy29)", text: $newHandle)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Aggiungi") { store.addAccount(newHandle); newHandle = ""; Task { await store.refresh() } }
                            .disabled(newHandle.isEmpty)
                    }
                    Button("Accedi a MakerWorld (per i punti)") { showLogin = true }
                }
                Section("Preferenze") {
                    Picker("Tab all'avvio", selection: $store.defaultTab) {
                        Text("Analytics").tag(0); Text("Stats").tag(1); Text("Models").tag(2)
                    }
                    Toggle("Notifiche traguardi e boost", isOn: Binding(
                        get: { store.notificationsOn },
                        set: { v in if v { Task { await store.requestNotifications() } } else { store.notificationsOn = false } }))
                }
                Section { Button("Aggiorna ora") { Task { await store.refresh() } } }
                Section {
                    Text("Le statistiche pubbliche non richiedono login. Il login serve per i punti e avviene direttamente su makerworld.com. L'app prova ad aggiornarsi in background ogni 30 minuti circa (iOS decide quando).")
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

struct LoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let wv = MakerWorldFetcher.shared.webView
        wv.load(URLRequest(url: URL(string: "https://makerworld.com/it")!))
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
