import Foundation
import IOKit

/// GPU load from the accelerator's PerformanceStatistics — the same numbers Activity Monitor's GPU history uses.
public final class GPUSampler {
    private var services: [io_service_t] = []

    public init() {
        Registry.forEachService("IOAccelerator") { service in
            guard Registry.property(service, "PerformanceStatistics") != nil else { return }
            IOObjectRetain(service)
            services.append(service)
        }
    }

    deinit {
        services.forEach { IOObjectRelease($0) }
    }

    /// The busiest GPU when there are several (Intel Macs with a discrete card).
    public func sample() -> GPUSample? {
        var best: GPUSample?
        for service in services {
            guard let stats = Registry.property(service, "PerformanceStatistics") as? [String: Any],
                  let sample = Self.parse(stats) else { continue }
            if best == nil || sample.device > best!.device { best = sample }
        }
        return best
    }

    public static func parse(_ stats: [String: Any]) -> GPUSample? {
        guard let device = stats.number("Device Utilization %") ?? stats.number("GPU Activity(%)") else { return nil }
        let renderer = stats.number("Renderer Utilization %") ?? device
        let tiler = stats.number("Tiler Utilization %") ?? 0
        let inUse = stats.number("In use system memory") ?? stats.number("vramUsedBytes") ?? 0
        let allocated = stats.number("Alloc system memory") ?? 0
        return GPUSample(device: clamp(device / 100), renderer: clamp(renderer / 100), tiler: clamp(tiler / 100),
                         memoryInUse: UInt64(max(0, inUse)), memoryAllocated: UInt64(max(0, allocated)))
    }

    public static func info() -> (model: String?, cores: Int?) {
        var model: String?
        var cores: Int?
        Registry.forEachService("IOAccelerator") { service in
            guard model == nil else { return }
            model = Registry.string(Registry.searchProperty(service, "model"))
            cores = Registry.int(Registry.property(service, "gpu-core-count"))
        }
        return (model, cores)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}
