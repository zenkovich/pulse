import Foundation
import Darwin

/// VM page counters turned into Activity Monitor's categories.
public final class MemorySampler {
    private let host = mach_host_self()
    public let total: UInt64

    public init() {
        total = UInt64(Sysctl.int("hw.memsize") ?? Int(ProcessInfo.processInfo.physicalMemory))
    }

    public func sample() -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        let swap = Sysctl.value("vm.swapusage", as: xsw_usage.self, default: xsw_usage())
        let pressureLevel = Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1
        guard result == KERN_SUCCESS else { return .zero }
        return Self.compute(stats: stats, pageSize: UInt64(vm_kernel_page_size), total: total,
                            pressureLevel: pressureLevel, swapUsed: swap.xsu_used, swapTotal: swap.xsu_total)
    }

    public static func compute(stats: vm_statistics64, pageSize: UInt64, total: UInt64, pressureLevel: Int,
                               swapUsed: UInt64, swapTotal: UInt64) -> MemorySample {
        let anonymous = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (anonymous > purgeable ? anonymous - purgeable : 0) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let cached = (UInt64(stats.external_page_count) + purgeable) * pageSize
        let used = app + wired + compressed
        let free = total > used + cached ? total - used - cached : 0
        return MemorySample(total: total, app: app, wired: wired, compressed: compressed, cached: cached, free: free,
                            pressure: MemoryPressure(rawValue: pressureLevel) ?? .normal,
                            swapUsed: swapUsed, swapTotal: swapTotal)
    }
}
