import Foundation

struct Voucher: Codable, Identifiable, Equatable {
    var id = UUID()
    var code: String
    var amount: Double
    var desc: String = ""
    var reserved = false
    var used = false
    var date = Date()
    enum Status { case available, reserved, used }
    var status: Status { used ? .used : reserved ? .reserved : .available }
}

struct PointEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var points: Double
    var date = Date()
    var auto = false
}

/// Porting della web app "Buoni MakerWorld".
@MainActor
final class VoucherStore: ObservableObject {
    @Published var vouchers: [Voucher] = [] { didSet { save() } }
    @Published var points: [PointEntry] = [] { didSet { save() } }   // più recente in testa
    @Published var credit: Double = 0 { didSet { save() } }
    @Published var pointsPerCard: Double = UserDefaults.standard.object(forKey: "pointsPerCard") as? Double ?? 524 {
        didSet { UserDefaults.standard.set(pointsPerCard, forKey: "pointsPerCard") }
    }

    private let key = "buoni.v1"
    private struct Saved: Codable { var vouchers: [Voucher]; var points: [PointEntry]; var credit: Double }
    private var loading = true

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            vouchers = s.vouchers; points = s.points; credit = s.credit
        }
        loading = false
    }

    private func save() {
        guard !loading, let d = try? JSONEncoder().encode(Saved(vouchers: vouchers, points: points, credit: credit)) else { return }
        UserDefaults.standard.set(d, forKey: key)
    }

    func total(_ s: Voucher.Status) -> Double { vouchers.filter { $0.status == s }.map(\.amount).reduce(0, +) }

    // MARK: Buoni
    @discardableResult
    func add(code: String, amount: Double, desc: String = "", reserved: Bool = false) -> Bool {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !vouchers.contains(where: { $0.code == c }) else { return false }
        vouchers.insert(Voucher(code: c, amount: amount, desc: desc, reserved: reserved), at: 0)
        return true
    }

    /// Righe "CODICE importo [descrizione] [(riscattato)|(da parte)]" — accetta anche il formato "Esporta" della web app.
    func importText(_ text: String) -> Int {
        var n = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let l = String(line).trimmingCharacters(in: .whitespaces)
            guard let m = l.firstMatch(of: /^(\S+)[\s,;:\t-]+[€$]?\s*([\d.,]+)\s*(.*)$/) else { continue }
            var rest = String(m.3)
            let used = rest.contains("(riscattato)"), res = rest.contains("(da parte)")
            rest = rest.replacingOccurrences(of: "(riscattato)", with: "").replacingOccurrences(of: "(da parte)", with: "")
                .trimmingCharacters(in: .whitespaces)
            if add(code: String(m.1), amount: Self.num(String(m.2)) ?? 0, desc: rest, reserved: res) {
                if used { vouchers[0].used = true }
                n += 1
            }
        }
        return n
    }

    func toggleUsed(_ v: Voucher) {
        guard let i = vouchers.firstIndex(of: v) else { return }
        vouchers[i].used.toggle()
        credit = ((credit + (vouchers[i].used ? v.amount : -v.amount)) * 100).rounded() / 100
    }
    func toggleReserved(_ v: Voucher, desc: String?) {
        guard let i = vouchers.firstIndex(of: v) else { return }
        vouchers[i].reserved.toggle()
        if let desc { vouchers[i].desc = desc }
    }
    func delete(_ v: Voucher) { vouchers.removeAll { $0.id == v.id } }

    var exportText: String {
        vouchers.map { v in
            "\(v.code) \(Self.fmt(v.amount))" + (v.desc.isEmpty ? "" : " \(v.desc)") +
            (v.used ? " (riscattato)" : v.reserved ? " (da parte)" : "")
        }.joined(separator: "\n")
    }

    // MARK: Punti
    func addPoints(_ p: Double, auto: Bool = false) {
        if auto, let last = points.first, abs(last.points - p) < 0.0001 { return } // registra solo se cambiano
        points.insert(PointEntry(points: p, auto: auto), at: 0)
    }

    var currentPoints: Double { points.first?.points ?? 0 }
    var cardsReached: Int { Int(currentPoints / pointsPerCard) }
    var rest: Double { currentPoints.truncatingRemainder(dividingBy: pointsPerCard) }

    static func num(_ t: String) -> Double? {
        var s = t.replacingOccurrences(of: " ", with: "")
        if s.contains(",") { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        return Double(s)
    }
    static func fmt(_ v: Double, max: Int = 2) -> String {
        v.formatted(.number.precision(.fractionLength(0...max)).locale(Locale(identifier: "it_IT")))
    }
    static func money(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "it_IT")))
    }
}
