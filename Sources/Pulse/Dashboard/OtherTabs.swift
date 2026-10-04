import SwiftUI
import PulseCore

private func splitValue(_ formatted: String) -> (String, String?) {
    guard let space = formatted.lastIndex(of: " ") else { return (formatted, nil) }
    return (String(formatted[..<space]), String(formatted[formatted.index(after: space)...]))
}

// MARK: - Memory

struct MemoryTab: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        let m = monitor.latest.memory
        let (value, unit) = splitValue(Format.bytes(m.used))
        let cachedColor = Color.primary.opacity(0.28)
        VStack(spacing: 12) {
            HeroValue(value: value, unit: unit, caption: "занято из \(Format.bytes(m.total))") {
                StatusBadge(severity: .memory(m.pressure), text: "Давление: " + pressureTitle(m.pressure))
            }

            Card {
                SectionHeader("Из чего состоит")
                SegmentedBar(segments: [
                    .init(id: "app", value: Double(m.app), color: .series1),
                    .init(id: "wired", value: Double(m.wired), color: .series2),
                    .init(id: "compressed", value: Double(m.compressed), color: .series3),
                    .init(id: "cached", value: Double(m.cached), color: cachedColor),
                ], total: Double(m.total))
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        LegendItem(color: .series1, name: "приложения", value: Format.bytes(m.app))
                        LegendItem(color: .series2, name: "зарезервировано", value: Format.bytes(m.wired))
                    }
                    GridRow {
                        LegendItem(color: .series3, name: "сжато", value: Format.bytes(m.compressed))
                        LegendItem(color: cachedColor, name: "кэш файлов", value: Format.bytes(m.cached))
                    }
                }
            }

            Card {
                SectionHeader("История") { RangePicker(range: $settings.range) }
                TimeChart(defs: [SeriesDef(name: "Приложения", color: .series1),
                                 SeriesDef(name: "Зарезервировано", color: .series2),
                                 SeriesDef(name: "Сжато", color: .series3)],
                          rows: monitor.rows(settings.range) {
                              [Double($0.memory.app), Double($0.memory.wired), Double($0.memory.compressed)]
                          },
                          stacked: true, yMax: Double(max(1, m.total)), range: settings.range.seconds,
                          now: monitor.latest.time, format: { Format.bytes($0) })
            }

            Card {
                StatRow(label: "Своп", value: "\(Format.bytes(m.swapUsed)) из \(Format.bytes(m.swapTotal))")
                StatRow(label: "Свободно", value: Format.bytes(m.free))
                StatRow(label: "Занято", value: Format.percent(m.usedFraction))
            }

            ProcessList(title: "Больше всего памяти",
                        entries: Array(monitor.detail.processes.sorted { $0.memory > $1.memory }.prefix(6)),
                        value: { Format.bytes($0.memory) },
                        fraction: { Double($0.memory) / Double(max(1, m.total)) })
        }
    }

    private func pressureTitle(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: return "норма"
        case .warning: return "высокое"
        case .critical: return "критическое"
        }
    }
}

// MARK: - Disk

struct RateTile: View {
    let title: String
    let symbol: String
    let rate: Double
    let color: Color

    var body: some View {
        let (value, unit) = splitValue(Format.rate(rate))
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Capsule().fill(color).frame(width: 10, height: 3)
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                if let unit { Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiskTab: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        let d = monitor.latest.disk
        VStack(spacing: 12) {
            HStack {
                RateTile(title: "Чтение", symbol: "arrow.down", rate: d.readRate, color: .series1)
                RateTile(title: "Запись", symbol: "arrow.up", rate: d.writeRate, color: .series2)
            }

            Card {
                SectionHeader("Активность") { RangePicker(range: $settings.range) }
                TimeChart(defs: [SeriesDef(name: "Чтение", color: .series1), SeriesDef(name: "Запись", color: .series2)],
                          rows: monitor.rows(settings.range) { [$0.disk.readRate, $0.disk.writeRate] },
                          minimumYMax: 1_000_000, range: settings.range.seconds, now: monitor.latest.time,
                          format: Format.rate)
            }

            Card {
                SectionHeader("Тома")
                if monitor.detail.volumes.isEmpty {
                    Text("Читаю тома…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(monitor.detail.volumes) { volume in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                                .foregroundStyle(.secondary)
                            Text(volume.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text("свободно " + Format.bytes(volume.available, binary: false))
                                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        MeterBar(fraction: volume.usedFraction,
                                 color: Color.severity(.load(volume.usedFraction)) ?? .series1)
                        Text("занято \(Format.bytes(volume.used, binary: false)) из \(Format.bytes(volume.total, binary: false))")
                            .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.tertiary)
                    }
                }
            }

            Card {
                StatRow(label: "Прочитано с момента загрузки", value: Format.bytes(d.readTotal, binary: false))
                StatRow(label: "Записано с момента загрузки", value: Format.bytes(d.writeTotal, binary: false))
                if let ssd = monitor.latest.temperatures.ssd {
                    StatRow(label: "Температура SSD", value: Format.temperature(ssd) + "C")
                }
            }
        }
    }
}

// MARK: - Network

struct NetworkTab: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        let n = monitor.latest.network
        VStack(spacing: 12) {
            HStack {
                RateTile(title: "Входящий", symbol: "arrow.down", rate: n.inRate, color: .series1)
                RateTile(title: "Исходящий", symbol: "arrow.up", rate: n.outRate, color: .series2)
            }

            Card {
                SectionHeader("Трафик") { RangePicker(range: $settings.range) }
                TimeChart(defs: [SeriesDef(name: "Входящий", color: .series1), SeriesDef(name: "Исходящий", color: .series2)],
                          rows: monitor.rows(settings.range) { [$0.network.inRate, $0.network.outRate] },
                          minimumYMax: 100_000, range: settings.range.seconds, now: monitor.latest.time,
                          format: Format.rate)
            }

            Card {
                SectionHeader("Интерфейсы")
                if monitor.detail.interfaces.isEmpty {
                    Text("Нет активных подключений").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(monitor.detail.interfaces) { interface in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: interface.displayName.contains("Wi-Fi") ? "wifi" : "cable.connector")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(interface.displayName).font(.system(size: 12, weight: .medium))
                            Text(interface.bsdName).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            if interface.isPrimary {
                                Text("основной")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.track))
                            }
                            Spacer()
                            Text("↓ \(Format.rate(interface.inRate))  ↑ \(Format.rate(interface.outRate))")
                                .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        if !interface.addresses.isEmpty {
                            Text(interface.addresses.prefix(2).joined(separator: "   "))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.leading, 22)
                        }
                    }
                }
            }

            Card {
                StatRow(label: "Получено с момента загрузки", value: Format.bytes(n.inTotal, binary: false))
                StatRow(label: "Отправлено с момента загрузки", value: Format.bytes(n.outTotal, binary: false))
            }
        }
    }
}

// MARK: - Overview

struct OverviewTab: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        let s = monitor.latest
        let range = settings.range
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        VStack(spacing: 12) {
            HStack {
                Text("За последние").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                RangePicker(range: $settings.range)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                OverviewCard(tab: .cpu, title: "Процессор", value: Format.percent(s.cpu.total),
                             detail: "польз. \(Format.percent(s.cpu.user)) · сист. \(Format.percent(s.cpu.system))",
                             rows: monitor.rows(range, maxPoints: 90) { [$0.cpu.total] }, yMax: 1,
                             severity: .load(s.cpu.total), settings: settings, now: s.time)
                OverviewCard(tab: .gpu, title: "Графика", value: s.gpu.map { Format.percent($0.device) } ?? "—",
                             detail: s.gpu.map { "видеопамять \(Format.bytes($0.memoryInUse))" } ?? "нет данных",
                             rows: monitor.rows(range, maxPoints: 90) { [$0.gpu?.device ?? 0] }, yMax: 1,
                             severity: .load(s.gpu?.device ?? 0), settings: settings, now: s.time)
                OverviewCard(tab: .memory, title: "Память", value: Format.bytes(s.memory.used),
                             detail: "из \(Format.bytes(s.memory.total)) · своп \(Format.bytes(s.memory.swapUsed))",
                             rows: monitor.rows(range, maxPoints: 90) { [$0.memory.usedFraction] }, yMax: 1,
                             severity: .memory(s.memory.pressure), settings: settings, now: s.time)
                OverviewCard(tab: .disk, title: "Диск", value: Format.rate(s.disk.readRate + s.disk.writeRate),
                             detail: "↓ \(Format.rate(s.disk.readRate)) ↑ \(Format.rate(s.disk.writeRate))",
                             rows: monitor.rows(range, maxPoints: 90) { [$0.disk.readRate + $0.disk.writeRate] },
                             yMax: nil, minimumYMax: 1_000_000, severity: .normal, settings: settings, now: s.time)
                OverviewCard(tab: .network, title: "Сеть", value: Format.rate(s.network.inRate + s.network.outRate),
                             detail: "↓ \(Format.rate(s.network.inRate)) ↑ \(Format.rate(s.network.outRate))",
                             rows: monitor.rows(range, maxPoints: 90) { [$0.network.inRate + $0.network.outRate] },
                             yMax: nil, minimumYMax: 100_000, severity: .normal, settings: settings, now: s.time)
                temperatureCard(s)
            }

            Card {
                SectionHeader("Этот Mac")
                StatRow(label: "Чип", value: monitor.info.cpuModel)
                StatRow(label: "Модель", value: monitor.info.modelIdentifier)
                StatRow(label: "macOS", value: monitor.info.osVersion)
                StatRow(label: "Время работы", value: Format.duration(monitor.detail.uptime))
                if let root = monitor.rootVolume {
                    StatRow(label: "Свободно на \(root.name)", value: Format.bytes(root.available, binary: false))
                }
            }
        }
    }

    @ViewBuilder
    private func temperatureCard(_ s: Snapshot) -> some View {
        if let chip = s.temperatures.chip {
            OverviewCard(tab: .cpu, title: "Температура", value: Format.temperature(chip) + "C",
                         detail: [s.temperatures.ssd.map { "SSD \(Format.temperature($0))" },
                                  s.temperatures.battery.map { "батарея \(Format.temperature($0))" }]
                            .compactMap { $0 }.joined(separator: " · "),
                         rows: monitor.rows(range: settings.range), yMax: nil, minimumYMax: 50,
                         severity: .temperature(chip), settings: settings, symbol: "thermometer.medium", now: s.time)
        } else {
            OverviewCard(tab: .cpu, title: "Нагрузка", value: Format.decimal(monitor.detail.loadAverage.first ?? 0, digits: 2),
                         detail: "средняя за 1 мин", rows: [], yMax: nil, severity: .normal, settings: settings,
                         symbol: "gauge.with.dots.needle.33percent", now: s.time)
        }
    }
}

private extension Monitor {
    func rows(range: HistoryRange) -> [SeriesRow] {
        rows(range, maxPoints: 90) { [$0.temperatures.chip ?? 0] }
    }
}

private struct OverviewCard: View {
    let tab: DashboardTab
    let title: String
    let value: String
    let detail: String
    let rows: [SeriesRow]
    let yMax: Double?
    var minimumYMax: Double = 1
    let severity: Severity
    @ObservedObject var settings: AppSettings
    var symbol: String? = nil
    var now = Date()

    var body: some View {
        Button {
            settings.tab = tab
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: symbol ?? tab.symbol).font(.system(size: 11))
                    Text(title).font(.system(size: 11, weight: .medium))
                    Spacer()
                    if let color = Color.severity(severity) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(color)
                    }
                }
                .foregroundStyle(.secondary)
                Text(value).font(.system(size: 19, weight: .semibold)).monospacedDigit().lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail.isEmpty ? " " : detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .minimumScaleFactor(0.8)
                Sparkline(values: rows, color: .series1, yMax: yMax, minimumYMax: minimumYMax,
                          range: settings.range.seconds, now: now)
                    .frame(height: 34)
                    .padding(.top, 2)
            }
            .padding(10)
            .cardBackground()
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
