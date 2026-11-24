import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: StatsStore
    var body: some View {
        NavigationStack {
            Form {
                Section("Account MakerWorld") {
                    TextField("Username", text: $store.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Token (opzionale, per punti)", text: $store.token)
                }
                Section { Button("Aggiorna ora") { Task { await store.refresh() } } }
            }
            .navigationTitle("Settings")
        }
    }
}
