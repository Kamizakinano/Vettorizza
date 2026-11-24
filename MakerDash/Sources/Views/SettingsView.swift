import SwiftUI
import WebKit

struct SettingsView: View {
    @EnvironmentObject var store: StatsStore
    @State private var loginFor: String?
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
                }
                Section {
                    ForEach(store.accounts, id: \.self) { a in
                        HStack {
                            Text(a)
                            Spacer()
                            Text(store.data[a]?.snapshot?.latest.pointsKnown == true ? "Collegato" : "Non collegato")
                                .font(.caption).foregroundStyle(store.data[a]?.snapshot?.latest.pointsKnown == true ? .green : .secondary)
                            Menu {
                                Button("Accedi") { loginFor = a }
                                Button("Esci", role: .destructive) { Task { await MakerWorldFetcher.shared.logout(handle: a) } }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                } header: { Text("Login per i punti") } footer: {
                    Text("Ogni account ha il suo login separato. Accedi con l'account corrispondente al nickname.")
                }
                Section("Preferenze") {
                    Picker("Tab all'avvio", selection: $store.defaultTab) {
                        Text("Analytics").tag(0); Text("Stats").tag(1); Text("Models").tag(2); Text("Buoni").tag(4)
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
            .keyboardDone()
            .sheet(item: Binding(get: { loginFor.map(LoginTarget.init) }, set: { loginFor = $0?.id })) { t in
                NavigationStack {
                    LoginWebView(handle: t.id)
                        .navigationTitle("Login · \(t.id)")
                        .toolbar { Button("Fatto") { loginFor = nil; store.handle = t.id; Task { await store.refresh() } } }
                }
            }
        }
    }
}

struct LoginTarget: Identifiable { let id: String }

struct LoginWebView: UIViewRepresentable {
    let handle: String
    func makeUIView(context: Context) -> WKWebView {
        let wv = MakerWorldFetcher.shared.webView(for: handle)
        wv.load(URLRequest(url: URL(string: "https://makerworld.com/it")!))
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
