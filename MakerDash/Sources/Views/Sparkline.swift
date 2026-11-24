import SwiftUI
import Charts

struct Sparkline: View {
    let points: [StatsStore.DayPoint]
    let color: Color
    var body: some View {
        if points.count >= 2 {
            Chart(points) { p in
                LineMark(x: .value("d", p.date), y: .value("v", p.value))
                    .interpolationMethod(.catmullRom).foregroundStyle(color)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 30)
        } else {
            Color.clear.frame(height: 30)
        }
    }
}
