import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var store: StatsStore
    enum Sort: String, CaseIterable { case recenti = "Recenti", downloads = "Downloads", oggi = "Trending oggi" }
    @State private var sort: Sort = .recenti

    var sorted: [Design] {
        switch sort {
        case .recenti: store.designs
        case .downloads: store.designs.sorted { $0.downloadCount > $1.downloadCount }
        case .oggi: store.designs.sorted { store.delta(design: $0, \.downloadCount) > store.delta(design: $1, \.downloadCount) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                AccountPicker().listRowBackground(Color.clear)
                ForEach(sorted) { m in
                HStack(spacing: 12) {
                    RemoteImage(url: m.coverUrl.flatMap(URL.init(string:)))
                        .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.titleTranslated?.isEmpty == false ? m.titleTranslated! : m.title)
                            .font(.subheadline.bold()).lineLimit(1)
                        HStack(spacing: 4) {
                            if m.isExclusive == true { badge("EXC", .green) }
                            if m.isStaffPicked == true { badge("FEAT", .yellow) }
                        }
                        HStack(spacing: 10) {
                            stat("bolt", m.boostCnt ?? 0, nil)
                            stat("heart", m.likeCount, store.delta(design: m, \.likeCount))
                            stat("arrow.down.circle", m.downloadCount, store.delta(design: m, \.downloadCount))
                            stat("printer", m.printCount, store.delta(design: m, \.printCount))
                        }
                    }
                }
                }
            }
            .overlay { if store.designs.isEmpty { ContentUnavailableView("Nessun modello", systemImage: "cube") } }
            .toolbar {
                Picker("Ordina", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) } }
            }
            .navigationTitle("Models")
            .refreshable { await store.refresh() }
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(c.opacity(0.25))).foregroundStyle(c)
    }

    private func stat(_ icon: String, _ v: Int, _ d: Int?) -> some View {
        VStack(spacing: 0) {
            Label("\(v)", systemImage: icon).font(.caption2.monospacedDigit()).labelStyle(.titleAndIcon)
            if let d { Text(d > 0 ? "+\(d)" : "\(d)").font(.caption2).foregroundStyle(d > 0 ? .green : .secondary) }
        }
    }
}
