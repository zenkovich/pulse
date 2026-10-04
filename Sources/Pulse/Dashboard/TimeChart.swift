import SwiftUI
import PulseCore

// Charts are drawn with plain Path shapes. Swift Charts and Canvas both start SwiftUI's Metal renderer, which
// costs a ~450 MB footprint spike on first draw — too much for a utility whose job is watching memory.

struct SeriesDef {
    let name: String
    let color: Color
}

/// Area/line chart over time with a fixed "now"-anchored window, relative time ticks,
/// and a crosshair tooltip that lists every series at the hovered moment.
struct TimeChart: View {
    let defs: [SeriesDef]
    let rows: [SeriesRow]
    var stacked = false
    /// Fixed top of the y scale (1 for percentages); nil = auto with a nice ceiling.
    var yMax: Double? = nil
    /// Smallest auto ceiling, so an idle disk doesn't blow noise up to full height.
    var minimumYMax: Double = 1
    /// Byte sizes in binary units get 1-2-5 ceilings in GiB (2 ГБ, not 2,1 ГБ).
    var binaryScale = false
    let range: TimeInterval
    let now: Date
    let format: (Double) -> String
    var height: CGFloat = 120

    @State private var hovered: SeriesRow?

    private static let axisWidth: CGFloat = 54
    private static let xAxisHeight: CGFloat = 16

    private var top: Double {
        if let yMax { return yMax }
        let peak = rows.map { row in stacked ? row.values.reduce(0, +) : (row.values.max() ?? 0) }.max() ?? 0
        return Self.niceCeiling(max(minimumYMax, peak * 1.1), binary: binaryScale)
    }

    var body: some View {
        let top = self.top
        let start = now.addingTimeInterval(-range)
        GeometryReader { geo in
            let plot = CGRect(x: 0, y: 6, width: max(1, geo.size.width - Self.axisWidth),
                              height: max(1, geo.size.height - 6 - Self.xAxisHeight))
            let xOf = { (time: Date) -> CGFloat in plot.minX + plot.width * CGFloat(time.timeIntervalSince(start) / range) }
            let yOf = { (value: Double) -> CGFloat in plot.maxY - plot.height * CGFloat(min(1, max(0, value / top))) }

            ZStack(alignment: .topLeading) {
                gridPath(plot: plot, xOf: xOf, yOf: yOf, top: top)
                    .stroke(Color.track, lineWidth: 0.5)

                ZStack {
                    ForEach(defs.indices, id: \.self) { i in
                        let band = self.band(series: i, xOf: xOf, yOf: yOf)
                        areaPath(band).fill(defs[i].color.opacity(stacked ? 0.28 : 0.14))
                        linePath(band.map(\.high)).stroke(defs[i].color,
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                }
                .clipShape(Rectangle().path(in: plot.insetBy(dx: 0, dy: -2)))

                ForEach([0, top / 2, top], id: \.self) { value in
                    Text(value == 0 ? "0" : format(value))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: Self.axisWidth - 6, alignment: .leading)
                        .position(x: plot.maxX + 6 + (Self.axisWidth - 6) / 2, y: yOf(value))
                }
                ForEach(xTicks, id: \.self) { tick in
                    Text(xLabel(tick))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: xOf(tick), y: plot.maxY + Self.xAxisHeight / 2 + 2)
                }

                if let hovered {
                    let x = xOf(hovered.time)
                    Path { p in
                        p.move(to: CGPoint(x: x, y: plot.minY))
                        p.addLine(to: CGPoint(x: x, y: plot.maxY))
                    }
                    .stroke(Color.secondary.opacity(0.55), lineWidth: 1)
                    let onLeft = x > geo.size.width / 2
                    tooltip(for: hovered)
                        .fixedSize()
                        .padding(onLeft ? .trailing : .leading, onLeft ? geo.size.width - x + 8 : x + 8)
                        .frame(width: geo.size.width, alignment: onLeft ? .topTrailing : .topLeading)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let fraction = Double((location.x - plot.minX) / plot.width)
                    hovered = location.x <= plot.maxX ? nearest(to: start.addingTimeInterval(fraction * range)) : nil
                case .ended:
                    hovered = nil
                }
            }
        }
        .frame(height: height)
    }

    // MARK: - Geometry

    private struct BandPoint {
        let low: CGPoint
        let high: CGPoint
    }

    private func band(series: Int, xOf: (Date) -> CGFloat, yOf: (Double) -> CGFloat) -> [BandPoint] {
        rows.compactMap { row in
            guard series < row.values.count else { return nil }
            let base = stacked ? row.values.prefix(series).reduce(0, +) : 0
            let x = xOf(row.time)
            return BandPoint(low: CGPoint(x: x, y: yOf(base)), high: CGPoint(x: x, y: yOf(base + row.values[series])))
        }
    }

    private func areaPath(_ band: [BandPoint]) -> Path {
        Path { path in
            guard band.count > 1 else { return }
            MonotoneCurve.add(band.map(\.high), to: &path, start: true)
            MonotoneCurve.add(band.reversed().map(\.low), to: &path, start: false)
            path.closeSubpath()
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in MonotoneCurve.add(points, to: &path, start: true) }
    }

    private func gridPath(plot: CGRect, xOf: (Date) -> CGFloat, yOf: (Double) -> CGFloat, top: Double) -> Path {
        Path { path in
            for value in [0, top / 2, top] {
                path.move(to: CGPoint(x: plot.minX, y: yOf(value)))
                path.addLine(to: CGPoint(x: plot.maxX, y: yOf(value)))
            }
            for tick in xTicks {
                path.move(to: CGPoint(x: xOf(tick), y: plot.minY))
                path.addLine(to: CGPoint(x: xOf(tick), y: plot.maxY))
            }
        }
    }

    private func tooltip(for row: SeriesRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.time, format: .dateTime.hour().minute().second())
                .font(.system(size: 10)).foregroundStyle(.secondary)
            ForEach(Array(defs.enumerated()), id: \.offset) { i, def in
                if i < row.values.count {
                    HStack(spacing: 5) {
                        Capsule().fill(def.color).frame(width: 10, height: 3)
                        Text(format(row.values[i])).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        Text(def.name).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .cardBackground(cornerRadius: 7)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
    }

    private func nearest(to date: Date) -> SeriesRow? {
        rows.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
    }

    // MARK: - Axes

    /// Interior ticks only (edge labels would be clipped).
    private var xTicks: [Date] {
        let step: TimeInterval
        switch range {
        case ...60: step = 15
        case ...300: step = 60
        case ...900: step = 300
        default: step = 900
        }
        return stride(from: step, to: range, by: step).map { now.addingTimeInterval(-$0) }
    }

    private func xLabel(_ date: Date) -> String {
        let ago = Int(now.timeIntervalSince(date).rounded())
        return ago < 60 ? "−\(ago) с" : "−\(ago / 60) мин"
    }

    /// 1-2-5 ceiling: 0.8 MB/s → 1 MB/s, 3.4 → 5, 6 → 10. Binary applies it per 1024-unit (1,6 GiB → 2 GiB).
    static func niceCeiling(_ value: Double, binary: Bool = false) -> Double {
        guard value > 0 else { return 1 }
        if binary {
            let unit = pow(1024, floor(log(value) / log(1024)))
            return niceCeiling(value / unit) * unit
        }
        let exponent = pow(10, floor(log10(value)))
        let fraction = value / exponent
        let nice: Double = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10
        return nice * exponent
    }
}

/// Fritsch–Carlson monotone cubic: smooth like Charts' `.monotone`, never overshoots the data.
enum MonotoneCurve {
    static func add(_ points: [CGPoint], to path: inout Path, start: Bool) {
        guard let first = points.first else { return }
        if start { path.move(to: first) } else { path.addLine(to: first) }
        let n = points.count
        guard n > 1 else { return }
        var secants = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<n - 1 {
            let dx = points[i + 1].x - points[i].x
            secants[i] = dx != 0 ? (points[i + 1].y - points[i].y) / dx : 0
        }
        var tangents = [CGFloat](repeating: 0, count: n)
        tangents[0] = secants[0]
        tangents[n - 1] = secants[n - 2]
        for i in 1..<n - 1 {
            tangents[i] = secants[i - 1] * secants[i] <= 0 ? 0 : (secants[i - 1] + secants[i]) / 2
        }
        for i in 0..<n - 1 {
            guard secants[i] != 0 else {
                tangents[i] = 0
                tangents[i + 1] = 0
                continue
            }
            let a = tangents[i] / secants[i], b = tangents[i + 1] / secants[i]
            let s = a * a + b * b
            if s > 9 {
                let t = 3 / s.squareRoot()
                tangents[i] = t * a * secants[i]
                tangents[i + 1] = t * b * secants[i]
            }
        }
        for i in 0..<n - 1 {
            let p0 = points[i], p1 = points[i + 1]
            let h = (p1.x - p0.x) / 3
            path.addCurve(to: p1, control1: CGPoint(x: p0.x + h, y: p0.y + tangents[i] * h),
                          control2: CGPoint(x: p1.x - h, y: p1.y - tangents[i + 1] * h))
        }
    }
}

/// Minimal sparkline for overview cards.
struct Sparkline: View {
    let values: [SeriesRow]
    let color: Color
    var yMax: Double? = 1
    var minimumYMax: Double = 1
    let range: TimeInterval
    let now: Date

    var body: some View {
        let peak = values.map { $0.values.first ?? 0 }.max() ?? 0
        let top = yMax ?? TimeChart.niceCeiling(max(minimumYMax, peak * 1.1))
        let start = now.addingTimeInterval(-range)
        GeometryReader { geo in
            let points = values.map { row in
                CGPoint(x: geo.size.width * CGFloat(row.time.timeIntervalSince(start) / range),
                        y: geo.size.height * (1 - CGFloat(min(1, max(0, (row.values.first ?? 0) / top)))))
            }
            ZStack {
                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    MonotoneCurve.add(points, to: &path, start: true)
                    path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    path.addLine(to: CGPoint(x: first.x, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(color.opacity(0.14))
                Path { path in MonotoneCurve.add(points, to: &path, start: true) }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            .clipShape(Rectangle().path(in: CGRect(origin: CGPoint(x: 0, y: -2),
                                                    size: CGSize(width: geo.size.width, height: geo.size.height + 4))))
        }
    }
}
