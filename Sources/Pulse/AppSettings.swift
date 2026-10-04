import Foundation
import Combine

enum MetricKind: String, CaseIterable, Codable, Identifiable {
    case cpu, gpu, memory, disk, network, temperature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "Процессор"
        case .gpu: return "Графика"
        case .memory: return "Память"
        case .disk: return "Диск"
        case .network: return "Сеть"
        case .temperature: return "Температура"
        }
    }

    /// Tiny caps label drawn in the menu bar.
    var shortLabel: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "RAM"
        case .disk: return "DISK"
        case .network: return "NET"
        case .temperature: return "TEMP"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cube.transparent"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .temperature: return "thermometer.medium"
        }
    }

    /// One-letter tag for the grid and bars layouts.
    var letter: String {
        switch self {
        case .cpu: return "C"
        case .gpu: return "G"
        case .memory: return "M"
        case .disk: return "D"
        case .network: return "N"
        case .temperature: return "T"
        }
    }

    var styles: [MenuStyle] {
        switch self {
        case .cpu: return [.text, .graph, .bar, .ring, .cores]
        case .gpu, .memory: return [.text, .graph, .bar, .ring]
        case .disk: return [.text, .graph, .ring]
        case .network: return [.text, .graph]
        case .temperature: return [.text]
        }
    }

    var tab: DashboardTab {
        switch self {
        case .cpu, .temperature: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .disk: return .disk
        case .network: return .network
        }
    }
}

enum MenuStyle: String, CaseIterable, Codable, Identifiable {
    case text, graph, bar, ring, cores

    var id: String { rawValue }

    func title(for kind: MetricKind) -> String {
        switch self {
        case .text: return kind == .disk || kind == .network ? "Скорость" : "Число"
        case .graph: return "График"
        case .bar: return "Шкала"
        case .ring: return kind == .disk ? "Место на диске" : "Кольцо"
        case .cores: return "По ядрам"
        }
    }
}

struct MetricConfig: Codable, Equatable {
    var enabled: Bool
    var style: MenuStyle
    var showValue: Bool
}

/// How the enabled metrics share the menu bar. Everything but `separate` is a single status item.
enum MenuLayout: String, CaseIterable, Codable, Identifiable {
    case separate, combined, grid, bars
    var id: String { rawValue }

    var title: String {
        switch self {
        case .separate: return "Отдельно"
        case .combined: return "Вместе"
        case .grid: return "Сетка"
        case .bars: return "Столбики"
        }
    }

    /// Grid and bars draw every metric their own way; per-metric styles apply to the other two.
    var usesMetricStyles: Bool { self == .separate || self == .combined }

    var hint: String {
        switch self {
        case .separate: return "Каждая метрика — свой значок со своим видом."
        case .combined: return "Те же виды, но одним значком: меньше отступов между ними."
        case .grid: return "Самый компактный с числами: две строки коротких подписей."
        case .bars: return "Самый узкий: шкала на метрику, буква под ней."
        }
    }
}

enum HistoryRange: Int, CaseIterable, Codable, Identifiable {
    case minute = 60, fiveMinutes = 300, fifteenMinutes = 900, hour = 3600

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .minute: return "1 мин"
        case .fiveMinutes: return "5 мин"
        case .fifteenMinutes: return "15 мин"
        case .hour: return "1 ч"
        }
    }
}

enum DashboardTab: String, CaseIterable, Codable, Identifiable {
    case overview, cpu, gpu, memory, disk, network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Обзор"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Память"
        case .disk: return "Диск"
        case .network: return "Сеть"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cpu: return MetricKind.cpu.symbol
        case .gpu: return MetricKind.gpu.symbol
        case .memory: return MetricKind.memory.symbol
        case .disk: return MetricKind.disk.symbol
        case .network: return MetricKind.network.symbol
        }
    }
}

/// User preferences, persisted to UserDefaults on every change.
@MainActor
final class AppSettings: ObservableObject {
    static let intervals: [TimeInterval] = [1, 2, 3, 5]

    static let defaultMetrics: [MetricKind: MetricConfig] = [
        .cpu: MetricConfig(enabled: true, style: .graph, showValue: true),
        .gpu: MetricConfig(enabled: true, style: .graph, showValue: true),
        .memory: MetricConfig(enabled: true, style: .ring, showValue: true),
        .disk: MetricConfig(enabled: true, style: .text, showValue: true),
        .network: MetricConfig(enabled: false, style: .text, showValue: true),
        .temperature: MetricConfig(enabled: false, style: .text, showValue: true),
    ]

    @Published var interval: TimeInterval { didSet { defaults.set(interval, forKey: Keys.interval) } }
    @Published var layout: MenuLayout { didSet { defaults.set(layout.rawValue, forKey: Keys.layout) } }
    @Published var highlightLoad: Bool { didSet { defaults.set(highlightLoad, forKey: Keys.highlight) } }
    @Published var metrics: [MetricKind: MetricConfig] { didSet { saveMetrics() } }
    @Published var range: HistoryRange { didSet { defaults.set(range.rawValue, forKey: Keys.range) } }
    @Published var tab: DashboardTab { didSet { defaults.set(tab.rawValue, forKey: Keys.tab) } }

    private let defaults: UserDefaults

    private enum Keys {
        static let interval = "interval"
        static let layout = "menuLayout"
        static let highlight = "highlightLoad"
        static let metrics = "metrics"
        static let range = "historyRange"
        static let tab = "dashboardTab"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: Keys.interval)
        interval = Self.intervals.contains(storedInterval) ? storedInterval : 2
        layout = MenuLayout(rawValue: defaults.string(forKey: Keys.layout) ?? "") ?? .grid
        highlightLoad = defaults.object(forKey: Keys.highlight) as? Bool ?? true
        range = HistoryRange(rawValue: defaults.integer(forKey: Keys.range)) ?? .fiveMinutes
        tab = DashboardTab(rawValue: defaults.string(forKey: Keys.tab) ?? "") ?? .overview
        var metrics = Self.defaultMetrics
        if let data = defaults.data(forKey: Keys.metrics),
           let stored = try? JSONDecoder().decode([String: MetricConfig].self, from: data) {
            for (key, config) in stored {
                guard let kind = MetricKind(rawValue: key) else { continue }
                var config = config
                if !kind.styles.contains(config.style) { config.style = kind.styles[0] }
                metrics[kind] = config
            }
        }
        self.metrics = metrics
    }

    func config(_ kind: MetricKind) -> MetricConfig {
        metrics[kind] ?? Self.defaultMetrics[kind]!
    }

    /// Menu bar order, left to right.
    var enabledKinds: [MetricKind] {
        MetricKind.allCases.filter { config($0).enabled }
    }

    private func saveMetrics() {
        let raw = Dictionary(uniqueKeysWithValues: metrics.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { defaults.set(data, forKey: Keys.metrics) }
    }
}
