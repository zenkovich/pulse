import SwiftUI
import PulseCore

extension Monitor {
    /// Chart rows for the selected range, averaged down to at most `maxPoints`.
    func rows(_ range: HistoryRange, maxPoints: Int = 180, _ extract: (Snapshot) -> [Double]) -> [SeriesRow] {
        Downsample.rows(history.recent(range.seconds), range: range.seconds, maxPoints: maxPoints, extract)
    }
}

extension ProcessInfo.ThermalState {
    var title: String {
        switch self {
        case .nominal: return "Норма"
        case .fair: return "Повышенный"
        case .serious: return "Высокий — частота снижена"
        case .critical: return "Критический"
        @unknown default: return "—"
        }
    }
}

// MARK: - CPU

struct CPUTab: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        let s = monitor.latest
        let info = monitor.info
        VStack(spacing: 12) {
            HeroValue(value: "\(Int((s.cpu.total * 100).rounded()))", unit: "%", caption: coresCaption(info)) {
                if let chip = s.temperatures.chip { TemperatureBadge(celsius: chip, caption: "чип") }
            }

            Card {
                SectionHeader("История") { RangePicker(range: $settings.range) }
                HStack(spacing: 14) {
                    LegendItem(color: .series1, name: "пользователь", value: Format.percent(s.cpu.user))
                    LegendItem(color: .series2, name: "система", value: Format.percent(s.cpu.system))
                    Spacer()
                }
                TimeChart(defs: [SeriesDef(name: "Пользователь", color: .series1),
                                 SeriesDef(name: "Система", color: .series2)],
                          rows: monitor.rows(settings.range) { [$0.cpu.user, $0.cpu.system] },
                          stacked: true, yMax: 1, range: settings.range.seconds, now: s.time,
                          format: Format.percent)
            }

            Card {
                SectionHeader("Ядра") {
                    Text("сейчас").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                CoreBars(cores: s.cpu.cores, labels: info.coreLabels(), kinds: info.coreKinds)
                Divider().padding(.vertical, 2)
                SectionHeader("По ядрам за \(settings.range.title)") {
                    HeatmapScale()
                }
                CoreHeatmap(rows: monitor.rows(settings.range, maxPoints: 60) { $0.cpu.cores.map(\.total) },
                            kinds: info.coreKinds, range: settings.range.seconds, now: s.time)
            }

            Card {
                StatRow(label: "Средняя нагрузка", value: monitor.detail.loadAverage.map { Format.decimal($0, digits: 2) }
                    .joined(separator: "  "), detail: "1 · 5 · 15 мин")
                StatRow(label: "Процессов", value: "\(monitor.detail.processCount)")
                StatRow(label: "Время работы", value: Format.duration(monitor.detail.uptime))
                StatRow(label: "Тепловой режим", value: monitor.detail.thermalState.title)
            }

            ProcessList(title: "Больше всего CPU",
                        entries: Array(monitor.detail.processes.sorted { $0.cpu > $1.cpu }.prefix(6)),
                        value: { Format.decimal($0.cpu, digits: 1) + "%" },
                        fraction: { min(1, $0.cpu / 100) },
                        note: "100% = одно ядро")
        }
    }

    private func coresCaption(_ info: SystemInfo) -> String {
        if info.efficiencyCores > 0 && info.performanceCores > 0 {
            return "\(info.cpuModel) · \(info.performanceCores)P + \(info.efficiencyCores)E ядер"
        }
        return "\(info.cpuModel) · \(info.coreKinds.count) ядер"
    }
}

struct TemperatureBadge: View {
    let celsius: Double
    let caption: String

    var body: some View {
        let severity = Severity.temperature(celsius)
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(Color.severity(severity) ?? .secondary)
                Text(Format.temperature(celsius) + "C").monospacedDigit()
            }
            .font(.system(size: 16, weight: .semibold))
            Text(caption).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}

/// Current load per core as stacked user/system columns, E and P clusters split by a hairline.
struct CoreBars: View {
    let cores: [CoreLoad]
    let labels: [String]
    let kinds: [CoreKind]

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(cores.indices, id: \.self) { i in
                if i > 0, i < kinds.count, kinds[i] != kinds[i - 1] {
                    Rectangle().fill(Color.track).frame(width: 1, height: 74).padding(.horizontal, 3)
                }
                VStack(spacing: 3) {
                    Text("\(Int((cores[i].total * 100).rounded()))")
                        .font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                    CoreColumn(load: cores[i]).frame(width: 12, height: 52)
                    Text(i < labels.count ? labels[i] : "").font(.system(size: 8.5)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .help(help(i))
            }
        }
    }

    private func help(_ i: Int) -> String {
        let label = i < labels.count ? labels[i] : "\(i + 1)"
        let kind = i < kinds.count ? (kinds[i] == .efficiency ? "эффективное" : kinds[i] == .performance ? "производительное" : "") : ""
        return "Ядро \(label) \(kind): пользователь \(Format.percent(cores[i].user)), система \(Format.percent(cores[i].system))"
    }
}

private struct CoreColumn: View {
    let load: CoreLoad

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let user = size.height * CGFloat(min(1, load.user))
            let system = size.height * CGFloat(min(1 - min(1, load.user), load.system))
            let gap: CGFloat = user > 0.5 && system > 0.5 ? 1.5 : 0
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.track)
                if user > 0.5 {
                    RoundedRectangle(cornerRadius: min(3, user / 2)).fill(Color.series1)
                        .frame(width: size.width, height: user)
                        .offset(y: size.height - user)
                }
                if system > 0.5 {
                    let h = max(0.5, system - gap)
                    RoundedRectangle(cornerRadius: min(3, h / 2)).fill(Color.series2)
                        .frame(width: size.width, height: h)
                        .offset(y: size.height - user - system)
                }
            }
        }
    }
}

/// Cores × time, one sequential hue: brighter = busier. Columns are placed by time so data slides in from the right.
/// Cells are binned into a few opacity levels, one Path each, so the whole map is a dozen shapes.
struct CoreHeatmap: View {
    let rows: [SeriesRow]
    let kinds: [CoreKind]
    let range: TimeInterval
    let now: Date

    private static let levels = 12

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            clusterLabels
            GeometryReader { geo in
                let paths = cellPaths(size: geo.size)
                ZStack {
                    Color.track.opacity(0.5)
                    ForEach(paths.indices, id: \.self) { level in
                        paths[level].fill(Color.series1.opacity(0.07 + 0.93 * Double(level) / Double(Self.levels - 1)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .frame(height: CGFloat(kinds.count) * 5 + 12)
        .help("Каждая строка — ядро, каждый столбец — момент времени. Чем ярче, тем выше загрузка.")
    }

    private func cellPaths(size: CGSize) -> [Path] {
        var paths = [Path](repeating: Path(), count: Self.levels)
        let count = kinds.count
        guard count > 0 else { return paths }
        let rowGap: CGFloat = 1
        let clusterGap: CGFloat = 4
        let clusters = CGFloat(zip(kinds, kinds.dropFirst()).filter { $0 != $1 }.count)
        let rowHeight = (size.height - rowGap * CGFloat(count - 1) - clusterGap * clusters) / CGFloat(count)
        let columnWidth = size.width / 60
        let start = now.addingTimeInterval(-range)
        for row in rows {
            let x = CGFloat(row.time.timeIntervalSince(start) / range) * size.width - columnWidth / 2
            var y: CGFloat = 0
            for core in 0..<min(count, row.values.count) {
                if core > 0 { y += kinds[core] != kinds[core - 1] ? clusterGap : rowGap }
                let v = min(1, max(0, row.values[core]))
                let level = Int((v * Double(Self.levels - 1)).rounded())
                paths[level].addRect(CGRect(x: x, y: y, width: columnWidth + 0.5, height: rowHeight))
                y += rowHeight
            }
        }
        return paths
    }

    /// "E" and "P" next to their rows.
    private var clusterLabels: some View {
        GeometryReader { geo in
            let groups = clusterGroups
            let total = CGFloat(kinds.count)
            ForEach(groups.indices, id: \.self) { g in
                let group = groups[g]
                Text(group.kind == .unknown ? "" : group.kind.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .position(x: geo.size.width / 2,
                              y: geo.size.height * (CGFloat(group.start) + CGFloat(group.count) / 2) / total)
            }
        }
        .frame(width: 10)
    }

    private var clusterGroups: [(kind: CoreKind, start: Int, count: Int)] {
        var groups: [(kind: CoreKind, start: Int, count: Int)] = []
        for (i, kind) in kinds.enumerated() {
            if let last = groups.last, last.kind == kind {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((kind, i, 1))
            }
        }
        return groups
    }
}

private struct HeatmapScale: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("0%")
            LinearGradient(colors: [Color.series1.opacity(0.07), Color.series1], startPoint: .leading, endPoint: .trailing)
                .frame(width: 44, height: 6)
                .clipShape(Capsule())
            Text("100%")
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
}

// MARK: - GPU

struct GPUTab: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        let s = monitor.latest
        let info = monitor.info
        if let gpu = s.gpu {
            VStack(spacing: 12) {
                HeroValue(value: "\(Int((gpu.device * 100).rounded()))", unit: "%", caption: caption(info)) {
                    if let t = s.temperatures.gpu ?? s.temperatures.chip {
                        TemperatureBadge(celsius: t, caption: s.temperatures.gpu != nil ? "GPU" : "чип")
                    }
                }

                Card {
                    SectionHeader("Загрузка") { RangePicker(range: $settings.range) }
                    TimeChart(defs: [SeriesDef(name: "Загрузка", color: .series1)],
                              rows: monitor.rows(settings.range) { [$0.gpu?.device ?? 0] },
                              yMax: 1, range: settings.range.seconds, now: s.time, format: Format.percent)
                }

                Card {
                    SectionHeader("Видеопамять") {
                        Text("используется " + Format.bytes(gpu.memoryInUse))
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                    TimeChart(defs: [SeriesDef(name: "Используется", color: .series1)],
                              rows: monitor.rows(settings.range) { [Double($0.gpu?.memoryInUse ?? 0)] },
                              minimumYMax: Double(1 << 30), binaryScale: true, range: settings.range.seconds, now: s.time,
                              format: { Format.bytes($0) }, height: 90)
                }

                Card {
                    StatRow(label: "Рендеринг", value: Format.percent(gpu.renderer))
                    StatRow(label: "Тайлер (геометрия)", value: Format.percent(gpu.tiler))
                    StatRow(label: "Выделено памяти", value: Format.bytes(gpu.memoryAllocated))
                    if let cores = info.gpuCores { StatRow(label: "Ядер GPU", value: "\(cores)") }
                }

                Text("На Apple Silicon видеопамять общая с оперативной: она входит в «Память».")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cube.transparent").font(.system(size: 28)).foregroundStyle(.tertiary)
                Text("macOS не отдаёт статистику GPU на этом Mac.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    private func caption(_ info: SystemInfo) -> String {
        let model = info.gpuModel ?? "GPU"
        return info.gpuCores.map { "\(model) · \($0) ядер GPU" } ?? model
    }
}
