import Foundation

/// Owns every sampler. Not thread-safe: the app confines it to one serial queue, hence the unchecked Sendable.
public final class SystemSampler: @unchecked Sendable {
    public let info: SystemInfo

    private let cpu = CPUSampler()
    private let gpu = GPUSampler()
    private let memory = MemorySampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()
    private let temperatures = TemperatureSampler()
    private let processes = ProcessSampler()

    private var lastTemperatures = Temperatures()
    private var lastTemperatureTime = Date.distantPast
    /// Sensor reads cost a few IPCs each; die temperature doesn't move faster than this anyway.
    public var temperatureInterval: TimeInterval = 3

    public init() {
        let gpuInfo = GPUSampler.info()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        info = SystemInfo(cpuModel: CPUSampler.modelName, coreKinds: CPUSampler.coreKinds(),
                          gpuModel: gpuInfo.model, gpuCores: gpuInfo.cores, memoryTotal: memory.total,
                          osVersion: os.patchVersion > 0 ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
                              : "\(os.majorVersion).\(os.minorVersion)",
                          modelIdentifier: Sysctl.string("hw.model") ?? "Mac")
    }

    public var hasTemperatures: Bool { temperatures.isAvailable }

    public func sample(now: Date = Date()) -> Snapshot {
        if now.timeIntervalSince(lastTemperatureTime) >= temperatureInterval {
            lastTemperatures = temperatures.sample()
            lastTemperatureTime = now
        }
        return Snapshot(time: now, cpu: cpu.sample(), gpu: gpu.sample(), memory: memory.sample(),
                        disk: disk.sample(now: now), network: network.sample(now: now),
                        temperatures: lastTemperatures)
    }

    public func sampleProcesses() -> (entries: [ProcessEntry], count: Int) {
        (processes.sample(), ProcessSampler.processCount())
    }

    public func sampleInterfaces() -> [InterfaceInfo] {
        network.interfaces()
    }
}
