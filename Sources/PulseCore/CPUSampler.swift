import Foundation
import Darwin
import IOKit

/// Per-core load from tick-counter deltas between two calls.
public final class CPUSampler {
    /// Raw counters per core: user, system, idle, nice (CPU_STATE_* order).
    public typealias Ticks = [UInt32]

    private let host = mach_host_self()
    private var previous: [Ticks] = []

    public init() {
        previous = readTicks()
    }

    public func sample() -> CPUSample {
        let current = readTicks()
        defer { previous = current }
        return Self.load(from: previous, to: current)
    }

    /// Pure delta math, kept separate for tests. Counters wrap at 2^32, hence the wrapping subtraction.
    public static func load(from old: [Ticks], to new: [Ticks]) -> CPUSample {
        guard old.count == new.count, !new.isEmpty else {
            return CPUSample(user: 0, system: 0, cores: new.map { _ in CoreLoad(user: 0, system: 0) })
        }
        var cores: [CoreLoad] = []
        cores.reserveCapacity(new.count)
        var sumUser = 0.0, sumSystem = 0.0
        for (a, b) in zip(old, new) {
            let user = Double(b[Int(CPU_STATE_USER)] &- a[Int(CPU_STATE_USER)])
                + Double(b[Int(CPU_STATE_NICE)] &- a[Int(CPU_STATE_NICE)])
            let system = Double(b[Int(CPU_STATE_SYSTEM)] &- a[Int(CPU_STATE_SYSTEM)])
            let idle = Double(b[Int(CPU_STATE_IDLE)] &- a[Int(CPU_STATE_IDLE)])
            let total = user + system + idle
            let core = total > 0 ? CoreLoad(user: user / total, system: system / total) : CoreLoad(user: 0, system: 0)
            cores.append(core)
            sumUser += core.user
            sumSystem += core.system
        }
        let n = Double(cores.count)
        return CPUSample(user: sumUser / n, system: sumSystem / n, cores: cores)
    }

    private func readTicks() -> [Ticks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { cpu in
            (0..<states).map { UInt32(bitPattern: info[cpu * states + $0]) }
        }
    }

    // MARK: - Static info

    public static var coreCount: Int { Sysctl.int("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount }

    public static var modelName: String {
        Sysctl.string("machdep.cpu.brand_string") ?? "CPU"
    }

    /// Core types in logical-cpu order. The device tree knows each core's cluster; perf levels are the fallback.
    public static func coreKinds() -> [CoreKind] {
        let count = coreCount
        var kinds = [CoreKind](repeating: .unknown, count: count)
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if cpus != 0 {
            Registry.forEachChild(cpus, plane: "IODeviceTree") { cpu in
                guard let id = Registry.int(Registry.property(cpu, "logical-cpu-id")), id >= 0, id < count,
                      let cluster = Registry.string(Registry.property(cpu, "cluster-type")) else { return }
                kinds[id] = cluster.hasPrefix("E") ? .efficiency : cluster.hasPrefix("P") ? .performance : .unknown
            }
            IOObjectRelease(cpus)
        }
        if kinds.contains(.unknown), Sysctl.int("hw.nperflevels") == 2,
           let efficiency = Sysctl.int("hw.perflevel1.logicalcpu"), efficiency < count {
            kinds = (0..<count).map { $0 < efficiency ? .efficiency : .performance }
        }
        return kinds
    }

    public static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : [0, 0, 0]
    }

    public static func uptime(now: Date = Date()) -> TimeInterval {
        let boot = Sysctl.value("kern.boottime", as: timeval.self, default: timeval())
        guard boot.tv_sec > 0 else { return ProcessInfo.processInfo.systemUptime }
        let bootDate = Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1e6)
        return now.timeIntervalSince(bootDate)
    }
}
