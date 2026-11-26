import WidgetKit
import SwiftUI

struct Entry: TimelineEntry { let date: Date; let data: WidgetData?; var placeholder = false }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), data: .sample, placeholder: true) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), data: context.isPreview ? (WidgetData.load() ?? .sample) : WidgetData.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let fromApp = WidgetData.load()
            var w = fromApp ?? WidgetData(updated: .distantPast, handle: "Kamy29")
            await PublicStats.merge(into: &w, standalone: fromApp == nil)
            let e = Entry(date: Date(), data: w.updated == .distantPast ? nil : w)
            completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

// MARK: Colori e piccoli componenti
private let purple = Color(red: 0.67, green: 0.45, blue: 1)
private let bg = Color(red: 0.12, green: 0.11, blue: 0.16)

private func fmt(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
private func plus(_ v: Int) -> String { v >= 0 ? "+\(v)" : "\(v)" }

struct Header: View {
    let text: String; var updated: Date? = nil
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "paperplane.fill").font(.caption2).rotationEffect(.degrees(-45))
            Text(text).font(.caption.bold()).lineLimit(1)
            Spacer(minLength: 0)
            if let u = updated { Text(u, style: .relative).font(.caption2).foregroundStyle(.secondary).lineLimit(1).multilineTextAlignment(.trailing) }
        }.foregroundStyle(purple)
    }
}

struct VoucherBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(Color.yellow).frame(width: max(6, g.size.width * progress))
            }
        }.frame(height: 6)
    }
}

struct Spark: View {
    let values: [Int]; let color: Color
    var body: some View {
        GeometryReader { g in
            let mx = Double(values.max() ?? 1), mn = Double(values.min() ?? 0), r = max(mx - mn, 1)
            Path { p in
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                                     y: g.size.height * (1 - CGFloat((Double(v) - mn) / r)))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }.stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct NoData: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "paperplane.fill").foregroundStyle(purple)
            Text("Apri MakerDash per caricare i dati").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

struct Waiting: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock").foregroundStyle(purple)
            Text("I dati di oggi partono dall'01:00 (giorno MakerWorld)").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

// MARK: Widget Punti (piccolo / medio / grande)
struct PointsView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry
    var body: some View {
        Group {
            if let w = e.data, w.waiting {
                Waiting()
            } else if let w = e.data {
                switch family {
                case .systemMedium: medium(w)
                case .systemLarge: large(w)
                default: small(w)
                }
            } else { NoData() }
        }
        .containerBackground(bg, for: .widget)
    }

    @ViewBuilder func pointsBlock(_ w: WidgetData, big: Bool) -> some View {
        if let p = w.points {
            Text(fmt(p) + (big ? "" : "")).font(.system(size: big ? 34 : 30, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
            Text("+\(fmt(w.pointsToday)) oggi" + (w.perDay.map { " · ~\(fmt($0))/g" } ?? "")).font(.caption.bold()).foregroundStyle(.green).lineLimit(1)
        } else {
            Text("Punti visibili solo nell'app").font(.caption).foregroundStyle(.secondary)
        }
    }

    func small(_ w: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Header(text: "PUNTI")
            Spacer(minLength: 0)
            pointsBlock(w, big: false)
            Spacer(minLength: 0)
            if w.points != nil {
                Text("\(w.cards) buoni · \(w.cards * 40) €").font(.caption.bold()).foregroundStyle(.yellow)
                VoucherBar(progress: w.progress)
                Text("\(w.toNext) pt al prossimo").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    func medium(_ w: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(text: "MakerDash · \(w.handle)", updated: w.updated)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    pointsBlock(w, big: true)
                    if w.points != nil {
                        VoucherBar(progress: w.progress).padding(.top, 4)
                        Text("\(w.cards) buoni (\(w.cards * 40) €) · \(w.toNext) al prossimo").font(.caption2).foregroundStyle(.yellow).lineLimit(1).minimumScaleFactor(0.8)
                        if let n = w.nextVoucher { Text("Prossimo buono ≈ \(n.formatted(.dateTime.day().month(.abbreviated)))").font(.caption2).foregroundStyle(.secondary) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    row("Download", w.downloads, .blue, w.spark7Downloads)
                    row("Stampe", w.prints, .green, w.spark7Prints)
                    row("Like", w.likes, .pink, w.spark7Likes)
                }.frame(maxWidth: .infinity)
            }
        }
    }

    func row(_ t: String, _ v: Int, _ c: Color, _ s: [Int]) -> some View {
        VStack(spacing: 1) {
            HStack { Text(t).font(.caption2).foregroundStyle(.secondary); Spacer(); Text(plus(v)).font(.caption.bold()).foregroundStyle(c) }
            if s.count > 1 { Spark(values: s, color: c).frame(height: 12) }
        }
    }

    func large(_ w: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(text: "MakerDash · \(w.handle)", updated: w.updated)
            HStack(alignment: .firstTextBaseline) {
                if let p = w.points {
                    Text("\(fmt(p)) pt").font(.system(size: 34, weight: .bold))
                    Text("+\(fmt(w.pointsToday)) oggi").font(.subheadline.bold()).foregroundStyle(.green)
                }
            }
            if w.points != nil {
                VoucherBar(progress: w.progress)
                Text("\(w.cards) buoni · \(w.cards * 40) € · \(w.toNext) pt al prossimo" + (w.nextVoucher.map { " (≈ \($0.formatted(.dateTime.day().month(.abbreviated))))" } ?? ""))
                    .font(.caption2).foregroundStyle(.yellow).lineLimit(1).minimumScaleFactor(0.8)
            }
            if w.points14.count > 1 {
                Text("Punti ultimi 14 giorni").font(.caption.bold()).foregroundStyle(.secondary)
                let mx = max(w.points14.max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(w.points14.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 3).fill(purple).frame(height: max(3, 60 * v / mx))
                    }
                }.frame(height: 60)
            }
            Text("Oggi").font(.caption.bold()).foregroundStyle(.secondary)
            HStack {
                stat("Download", w.downloads, .blue); stat("Stampe", w.prints, .green); stat("Like", w.likes, .pink)
                stat("Follower", w.followers, .yellow); stat("Boost", w.boosts, purple)
            }
            if !w.top.isEmpty {
                Text("Top modelli oggi").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(Array(w.top.prefix(3).enumerated()), id: \.offset) { i, t in
                    HStack { Text("\(i + 1). \(t.title)").font(.caption).lineLimit(1); Spacer(); Text("+\(t.downloads) ↓").font(.caption.bold()).foregroundStyle(.blue) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    func stat(_ t: String, _ v: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            Text(plus(v)).font(.subheadline.bold()).foregroundStyle(c)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Widget Oggi (piccolo)
struct TodayView: View {
    let e: Entry
    var body: some View {
        Group {
            if let w = e.data, w.waiting {
                Waiting()
            } else if let w = e.data {
                VStack(alignment: .leading, spacing: 6) {
                    Header(text: "OGGI")
                    Spacer(minLength: 0)
                    line("Download", w.downloads, .blue)
                    line("Stampe", w.prints, .green)
                    line("Like", w.likes, .pink)
                    line("Follower", w.followers, .yellow)
                    Spacer(minLength: 0)
                }
            } else { NoData() }
        }.containerBackground(bg, for: .widget)
    }
    func line(_ t: String, _ v: Int, _ c: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(plus(v)).font(.headline).foregroundStyle(c)
        }
    }
}

// MARK: Schermata di blocco
struct LockView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry
    var body: some View {
        let w = e.data
        switch family {
        case .accessoryCircular:
            Gauge(value: w?.progress ?? 0) {
                Image(systemName: "ticket")
            } currentValueLabel: {
                Text("\(Int(((w?.points ?? 0).truncatingRemainder(dividingBy: 524))))")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Text(w.map { "\(fmt($0.points ?? 0)) pt · ↓\(plus($0.downloads))" } ?? "MakerDash")
                .containerBackground(.clear, for: .widget)
        default:
            VStack(alignment: .leading, spacing: 2) {
                if let w {
                    Text("\(fmt(w.points ?? 0)) pt  +\(fmt(w.pointsToday))").font(.headline)
                    Text("Download \(plus(w.downloads)) · Stampe \(plus(w.prints))").font(.caption)
                    Text("\(w.toNext) pt al prossimo buono").font(.caption2).foregroundStyle(.secondary)
                } else { Text("MakerDash").font(.headline) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        }
    }
}

struct PointsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "points", provider: Provider()) { PointsView(e: $0) }
            .configurationDisplayName("Punti e riepilogo")
            .description("Punti, buoni e statistiche di oggi.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: Provider()) { TodayView(e: $0) }
            .configurationDisplayName("Oggi")
            .description("Download, stampe, like e follower di oggi.")
            .supportedFamilies([.systemSmall])
    }
}
struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lock", provider: Provider()) { LockView(e: $0) }
            .configurationDisplayName("Schermata di blocco")
            .description("Punti verso il prossimo buono.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MakerDashWidgets: WidgetBundle {
    var body: some Widget { PointsWidget(); TodayWidget(); LockWidget() }
}
