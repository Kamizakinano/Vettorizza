import SwiftUI
import UIKit

struct VouchersView: View {
    @EnvironmentObject var store: StatsStore
    @EnvironmentObject var vs: VoucherStore
    enum Filter: String, CaseIterable { case av = "Da attivare", res = "Da parte", used = "Riscattati", all = "Tutti" }
    @State private var filter: Filter = .av
    @State private var code = "", amount = "", desc = ""
    @State private var reserved = false
    @State private var showBulk = false
    @State private var bulk = ""
    @State private var manualPoints = ""
    @State private var toast: String?
    @State private var reserveTarget: Voucher?
    @State private var reserveDesc = ""

    var filtered: [Voucher] {
        vs.vouchers.filter {
            switch filter { case .all: true; case .av: $0.status == .available; case .res: $0.status == .reserved; case .used: $0.status == .used }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        pill("Credito", vs.credit, .green)
                        pill("Da attivare", vs.total(.available), .primary)
                        pill("Da parte", vs.total(.reserved), .orange)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }

                Section("Punti") {
                    HStack {
                        Text("Punti attuali").foregroundStyle(.secondary)
                        Spacer()
                        Text(vs.points.isEmpty ? "—" : VoucherStore.fmt(vs.currentPoints, max: 3)).font(.title3.bold().monospacedDigit())
                    }
                    if vs.points.count > 1 {
                        let d = vs.points[0].points - vs.points[1].points
                        Text("\(d >= 0 ? "+" : "")\(VoucherStore.fmt(d, max: 3)) dall'ultima volta")
                            .font(.caption).foregroundStyle(d >= 0 ? .green : .red)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("🎟️ Buoni raggiunti: **\(vs.cardsReached)**")
                            Spacer()
                            Text("mancano **\(VoucherStore.fmt(vs.pointsPerCard - vs.rest))**").font(.caption)
                        }
                        ProgressView(value: vs.rest, total: vs.pointsPerCard).tint(.green)
                        Text("\(VoucherStore.fmt(vs.rest)) / \(VoucherStore.fmt(vs.pointsPerCard)) punti")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Punti adesso (manuale)", text: $manualPoints).keyboardType(.decimalPad)
                        Button("Salva") {
                            if let v = VoucherStore.num(manualPoints) { vs.addPoints(v); manualPoints = ""; show("Punti salvati") }
                        }
                    }
                    Stepper("Punti per buono: \(VoucherStore.fmt(vs.pointsPerCard))", value: $vs.pointsPerCard, in: 1...10000, step: 1)
                        .font(.caption)
                    DisclosureGroup("Storico punti (\(vs.points.count))") {
                        ForEach(Array(vs.points.enumerated()), id: \.element.id) { i, p in
                            HStack {
                                Text(p.date.formatted(date: .numeric, time: .shortened)).font(.caption)
                                if p.auto { Image(systemName: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(.secondary) }
                                Spacer()
                                if i < vs.points.count - 1 {
                                    let d = p.points - vs.points[i + 1].points
                                    Text("\(d >= 0 ? "+" : "")\(VoucherStore.fmt(d, max: 3))").font(.caption.bold())
                                        .foregroundStyle(d > 0 ? .green : d < 0 ? .red : .secondary)
                                }
                                Text(VoucherStore.fmt(p.points, max: 3)).font(.callout.monospacedDigit().bold())
                            }
                        }
                        .onDelete { vs.points.remove(atOffsets: $0) }
                    }
                }

                Section("Aggiungi buono") {
                    HStack {
                        TextField("Codice buono", text: $code)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled().font(.body.monospaced())
                        Button("Incolla") { pasteCode() }.buttonStyle(.bordered)
                    }
                    TextField("Importo", text: $amount).keyboardType(.decimalPad)
                    TextField("Descrizione (facoltativa)", text: $desc)
                    Toggle("Da parte", isOn: $reserved)
                    Button("Aggiungi") { addOne() }.disabled(code.isEmpty || amount.isEmpty)
                    Button(showBulk ? "Chiudi" : "+ Più buoni / importa dalla web app") { showBulk.toggle() }
                    if showBulk {
                        Text("Uno per riga: CODICE importo. Puoi incollare l'output del pulsante **Esporta** della vecchia web app.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $bulk).frame(minHeight: 100).font(.body.monospaced())
                        Button("Importa") { let n = vs.importText(bulk); bulk = ""; show("\(n) buoni importati"); if n > 0 { showBulk = false } }
                    }
                }

                Section {
                    Picker("Filtro", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) } }
                        .pickerStyle(.segmented)
                    HStack {
                        Button("Copia da attivare") {
                            copy(vs.vouchers.filter { $0.status == .available }.map(\.code).joined(separator: "\n"))
                        }
                        Spacer()
                        Button("Esporta") { copy(vs.exportText) }
                    }.buttonStyle(.bordered).font(.caption)
                    if filtered.isEmpty { Text("Nessun buono").foregroundStyle(.secondary) }
                    ForEach(filtered) { v in row(v) }
                }
            }
            .navigationTitle("Buoni")
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color(white: 0.2))).padding(.bottom, 20)
                }
            }
            .alert("Descrizione", isPresented: Binding(get: { reserveTarget != nil }, set: { if !$0 { reserveTarget = nil } })) {
                TextField("Descrizione", text: $reserveDesc)
                Button("OK") { if let t = reserveTarget { vs.toggleReserved(t, desc: reserveDesc.trimmingCharacters(in: .whitespaces)) }; reserveTarget = nil }
                Button("Annulla", role: .cancel) { reserveTarget = nil }
            }
            .onChange(of: store.stats) { _, s in
                if let s, s.pointsKnown == true { vs.addPoints(s.pointsRegular + s.pointsExclusive, auto: true) }
            }
            .onAppear {
                if let s = store.stats, s.pointsKnown == true { vs.addPoints(s.pointsRegular + s.pointsExclusive, auto: true) }
            }
        }
    }

    private func row(_ v: Voucher) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.code).font(.body.monospaced()).textSelection(.enabled)
                    .strikethrough(v.used).foregroundStyle(v.used ? .secondary : .primary)
                if !v.desc.isEmpty { Text(v.desc).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(VoucherStore.money(v.amount)).font(.headline.monospacedDigit())
        }
        .contentShape(Rectangle())
        .onTapGesture { copy(v.code) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { vs.delete(v) } label: { Label("Elimina", systemImage: "trash") }
            Button { vs.toggleUsed(v); show(v.used ? "Riscatto annullato" : "Riscattato: +\(VoucherStore.money(v.amount)) al credito") }
                label: { Label(v.used ? "Annulla" : "Riscatta", systemImage: v.used ? "arrow.uturn.backward" : "checkmark") }.tint(.green)
        }
        .swipeActions(edge: .leading) {
            if !v.used {
                Button { if v.reserved { vs.toggleReserved(v, desc: nil) } else { reserveDesc = v.desc; reserveTarget = v } }
                    label: { Label(v.reserved ? "Sblocca" : "Da parte", systemImage: "bookmark") }.tint(.orange)
            }
            Button { copy(v.code) } label: { Label("Copia", systemImage: "doc.on.doc") }.tint(.blue)
        }
    }

    private func pill(_ t: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.caption2).foregroundStyle(.secondary)
            Text(VoucherStore.money(v)).font(.headline.monospacedDigit()).foregroundStyle(c)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(c.opacity(0.12)))
    }

    private func addOne() {
        guard let a = VoucherStore.num(amount) else { show("Inserisci l'importo"); return }
        if vs.add(code: code, amount: a, desc: desc.trimmingCharacters(in: .whitespaces), reserved: reserved) {
            code = ""; amount = ""; desc = ""; reserved = false
        } else { show("Codice già presente") }
    }

    private func pasteCode() {
        guard let t = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return }
        if let m = t.firstMatch(of: /^(\S+)(?:[\s,;:\t-]+[€$]?\s*([\d.,]+))?/) {
            code = String(m.1)
            if let a = m.2 { amount = String(a) }
        } else { code = t }
    }

    private func copy(_ t: String) { UIPasteboard.general.string = t; show("Copiato!") }
    private func show(_ t: String) {
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { if toast == t { toast = nil } }
    }
}
