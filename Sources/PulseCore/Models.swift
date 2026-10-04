import Foundation

// MARK: - CPU

public enum CoreKind: String, Sendable, Codable {
    case efficiency = "E"
    case performance = "P"
    case unknown = "C"
}

/// Load of one logical core over the last sampling interval, fractions 0…1.
public struct CoreLoad: Sendable, Equatable {
    public var user: Double     // includes nice
    public var system: Double

    public init(user: Double, system: Double) {
        self.user = user
        self.system = system
    }

    public var total: Double { min(1, user + system) }
}

public struct CPUSample: Sendable {
    public var user: Double
    public var system: Double
    public var cores: [CoreLoad]

    public init(user: Double, system: Double, cores: [CoreLoad]) {
        self.user = user
        self.system = system
        self.cores = cores
    }

    public static let zero = CPUSample(user: 0, system: 0, cores: [])
    public var total: Double { min(1, user + system) }
    public var idle: Double { max(0, 1 - total) }
}

// MARK: - GPU

public struct GPUSample: Sendable {
    public var device: Double       // 0…1
    public var renderer: Double
    public var tiler: Double
    public var memoryInUse: UInt64
    public var memoryAllocated: UInt64

    public init(device: Double, renderer: Double, tiler: Double, memoryInUse: UInt64, memoryAllocated: UInt64) {
        self.device = device
        self.renderer = renderer
        self.tiler = tiler
        self.memoryInUse = memoryInUse
        self.memoryAllocated = memoryAllocated
    }
}

// MARK: - Memory

public enum MemoryPressure: Int, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4
}

public struct MemorySample: Sendable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var free: UInt64
    public var pressure: MemoryPressure
    public var swapUsed: UInt64
    public var swapTotal: UInt64

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64, free: UInt64,
                pressure: MemoryPressure, swapUsed: UInt64, swapTotal: UInt64) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.free = free
        self.pressure = pressure
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
    }

    public static let zero = MemorySample(total: 0, app: 0, wired: 0, compressed: 0, cached: 0, free: 0,
                                          pressure: .normal, swapUsed: 0, swapTotal: 0)

    /// What Activity Monitor calls "Memory Used".
    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

// MARK: - Disk & network

public struct DiskSample: Sendable {
    public var readRate: Double     // bytes per second
    public var writeRate: Double
    public var readTotal: UInt64    // since boot
    public var writeTotal: UInt64

    public init(readRate: Double, writeRate: Double, readTotal: UInt64, writeTotal: UInt64) {
        self.readRate = readRate
        self.writeRate = writeRate
        self.readTotal = readTotal
        self.writeTotal = writeTotal
    }

    public static let zero = DiskSample(readRate: 0, writeRate: 0, readTotal: 0, writeTotal: 0)
}

public struct NetworkSample: Sendable {
    public var inRate: Double       // bytes per second
    public var outRate: Double
    public var inTotal: UInt64      // since boot
    public var outTotal: UInt64

    public init(inRate: Double, outRate: Double, inTotal: UInt64, outTotal: UInt64) {
        self.inRate = inRate
        self.outRate = outRate
        self.inTotal = inTotal
        self.outTotal = outTotal
    }

    public static let zero = NetworkSample(inRate: 0, outRate: 0, inTotal: 0, outTotal: 0)
}

public struct VolumeInfo: Identifiable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var total: UInt64
    public var available: UInt64
    public var isRoot: Bool
    public var isInternal: Bool

    public init(path: String, name: String, total: UInt64, available: UInt64, isRoot: Bool, isInternal: Bool) {
        self.path = path
        self.name = name
        self.total = total
        self.available = available
        self.isRoot = isRoot
        self.isInternal = isInternal
    }

    public var used: UInt64 { total > available ? total - available : 0 }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

public struct InterfaceInfo: Identifiable, Sendable {
    public var id: String { bsdName }
    public var bsdName: String
    public var displayName: String
    public var addresses: [String]
    public var isPrimary: Bool
    public var inRate: Double
    public var outRate: Double
    public var inTotal: UInt64
    public var outTotal: UInt64

    public init(bsdName: String, displayName: String, addresses: [String], isPrimary: Bool,
                inRate: Double, outRate: Double, inTotal: UInt64, outTotal: UInt64) {
        self.bsdName = bsdName
        self.displayName = displayName
        self.addresses = addresses
        self.isPrimary = isPrimary
        self.inRate = inRate
        self.outRate = outRate
        self.inTotal = inTotal
        self.outTotal = outTotal
    }
}

// MARK: - Temperatures & processes

public struct Temperatures: Sendable {
    public var chip: Double?        // hottest SoC/CPU die sensor, °C
    public var gpu: Double?         // only where the SoC exposes separate GPU sensors (M1/M2)
    public var ssd: Double?
    public var battery: Double?

    public init(chip: Double? = nil, gpu: Double? = nil, ssd: Double? = nil, battery: Double? = nil) {
        self.chip = chip
        self.gpu = gpu
        self.ssd = ssd
        self.battery = battery
    }
}

public struct ProcessEntry: Identifiable, Sendable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var name: String
    public var cpu: Double          // percent of one core, like Activity Monitor (can exceed 100)
    public var memory: UInt64       // physical footprint where readable, otherwise RSS

    public init(pid: Int32, name: String, cpu: Double, memory: UInt64) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
        self.memory = memory
    }
}

// MARK: - Snapshot

/// Everything sampled on one tick. Cheap enough to keep an hour of these.
public struct Snapshot: Sendable {
    public var time: Date
    public var cpu: CPUSample
    public var gpu: GPUSample?
    public var memory: MemorySample
    public var disk: DiskSample
    public var network: NetworkSample
    public var temperatures: Temperatures

    public init(time: Date, cpu: CPUSample, gpu: GPUSample?, memory: MemorySample, disk: DiskSample,
                network: NetworkSample, temperatures: Temperatures) {
        self.time = time
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.temperatures = temperatures
    }

    public static let empty = Snapshot(time: Date(), cpu: .zero, gpu: nil, memory: .zero, disk: .zero,
                                       network: .zero, temperatures: Temperatures())
}

/// Heavier data sampled only while the dashboard is open.
public struct DetailSample: Sendable {
    public var processes: [ProcessEntry]
    public var processCount: Int
    public var volumes: [VolumeInfo]
    public var interfaces: [InterfaceInfo]
    public var loadAverage: [Double]
    public var uptime: TimeInterval
    public var thermalState: ProcessInfo.ThermalState

    public init(processes: [ProcessEntry] = [], processCount: Int = 0, volumes: [VolumeInfo] = [],
                interfaces: [InterfaceInfo] = [], loadAverage: [Double] = [0, 0, 0], uptime: TimeInterval = 0,
                thermalState: ProcessInfo.ThermalState = .nominal) {
        self.processes = processes
        self.processCount = processCount
        self.volumes = volumes
        self.interfaces = interfaces
        self.loadAverage = loadAverage
        self.uptime = uptime
        self.thermalState = thermalState
    }
}

public struct SystemInfo: Sendable {
    public var cpuModel: String
    public var coreKinds: [CoreKind]
    public var gpuModel: String?
    public var gpuCores: Int?
    public var memoryTotal: UInt64
    public var osVersion: String
    public var modelIdentifier: String

    public init(cpuModel: String, coreKinds: [CoreKind], gpuModel: String?, gpuCores: Int?, memoryTotal: UInt64,
                osVersion: String, modelIdentifier: String) {
        self.cpuModel = cpuModel
        self.coreKinds = coreKinds
        self.gpuModel = gpuModel
        self.gpuCores = gpuCores
        self.memoryTotal = memoryTotal
        self.osVersion = osVersion
        self.modelIdentifier = modelIdentifier
    }

    public var efficiencyCores: Int { coreKinds.filter { $0 == .efficiency }.count }
    public var performanceCores: Int { coreKinds.filter { $0 == .performance }.count }

    /// "E1".."E4", "P1".."P12" on Apple Silicon, "1".."8" elsewhere.
    public func coreLabels() -> [String] {
        var e = 0, p = 0, c = 0
        return coreKinds.map { kind in
            switch kind {
            case .efficiency: e += 1; return "E\(e)"
            case .performance: p += 1; return "P\(p)"
            case .unknown: c += 1; return "\(c)"
            }
        }
    }
}

// MARK: - Severity

/// How loud a value should look. Thresholds live here so the menu bar and the dashboard agree.
public enum Severity: Int, Sendable, Comparable {
    case normal, warning, serious, critical

    public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

    public static func load(_ fraction: Double) -> Severity {
        if fraction >= 0.95 { return .critical }
        if fraction >= 0.85 { return .serious }
        if fraction >= 0.70 { return .warning }
        return .normal
    }

    /// Memory "fullness" is normal on macOS; only kernel pressure means trouble.
    public static func memory(_ pressure: MemoryPressure) -> Severity {
        switch pressure {
        case .normal: return .normal
        case .warning: return .serious
        case .critical: return .critical
        }
    }

    public static func temperature(_ celsius: Double) -> Severity {
        if celsius >= 100 { return .critical }
        if celsius >= 90 { return .serious }
        if celsius >= 80 { return .warning }
        return .normal
    }
}
