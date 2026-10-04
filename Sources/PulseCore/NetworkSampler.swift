import Foundation
import Darwin
import SystemConfiguration

/// Throughput of physical interfaces from the 64-bit if_data counters (getifaddrs only has 32-bit ones).
public final class NetworkSampler {
    public struct Counters: Equatable {
        public var inBytes: UInt64
        public var outBytes: UInt64
    }

    private var last: (counters: [String: Counters], time: Date)?
    private var rates: [String: (inRate: Double, outRate: Double)] = [:]
    private var displayNames: [String: String] = [:]
    private var displayNamesTime = Date.distantPast

    public init() {
        last = (Self.readCounters(), Date())
    }

    /// Wi-Fi, Ethernet and cellular. Tunnels (utun, ipsec) would count VPN traffic twice; bridges and AWDL are noise.
    public static func isCounted(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    public func sample(now: Date = Date()) -> NetworkSample {
        let counters = Self.readCounters()
        defer { last = (counters, now) }
        var inTotal: UInt64 = 0, outTotal: UInt64 = 0
        var inRate = 0.0, outRate = 0.0
        var newRates: [String: (Double, Double)] = [:]
        let dt = last.map { now.timeIntervalSince($0.time) } ?? 0
        for (name, c) in counters {
            inTotal &+= c.inBytes
            outTotal &+= c.outBytes
            guard dt > 0, let old = last?.counters[name] else { continue }
            let i = c.inBytes >= old.inBytes ? Double(c.inBytes - old.inBytes) / dt : 0
            let o = c.outBytes >= old.outBytes ? Double(c.outBytes - old.outBytes) / dt : 0
            newRates[name] = (i, o)
            inRate += i
            outRate += o
        }
        rates = newRates
        return NetworkSample(inRate: inRate, outRate: outRate, inTotal: inTotal, outTotal: outTotal)
    }

    /// Interfaces that are up and have an address, primary first. Uses rates from the last `sample()`.
    public func interfaces() -> [InterfaceInfo] {
        if Date().timeIntervalSince(displayNamesTime) > 30 {
            displayNames = Self.readDisplayNames()
            displayNamesTime = Date()
        }
        let primary = Self.primaryInterface()
        let addresses = Self.readAddresses()
        let counters = last?.counters ?? [:]
        return addresses.keys.filter(Self.isCounted).map { name in
            let c = counters[name] ?? Counters(inBytes: 0, outBytes: 0)
            let r = rates[name] ?? (0, 0)
            return InterfaceInfo(bsdName: name, displayName: displayNames[name] ?? name,
                                 addresses: addresses[name] ?? [], isPrimary: name == primary,
                                 inRate: r.inRate, outRate: r.outRate, inTotal: c.inBytes, outTotal: c.outBytes)
        }
        .sorted { ($0.isPrimary ? 0 : 1, $0.bsdName) < ($1.isPrimary ? 0 : 1, $1.bsdName) }
    }

    // MARK: - Reading

    static func readCounters() -> [String: Counters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: Counters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        if isCounted(name) {
                            result[name] = Counters(inBytes: message.ifm_data.ifi_ibytes,
                                                    outBytes: message.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += messageLength
            }
        }
        return result
    }

    /// IPv4 and global IPv6 addresses of interfaces that are up and running.
    static func readAddresses() -> [String: [String]] {
        var result: [String: [String]] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return result }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            if family == AF_INET6 && (text.hasPrefix("fe80") || text.contains("%")) { continue }
            result[String(cString: entry.pointee.ifa_name), default: []].append(text)
        }
        // IPv4 first: it is what people look for.
        return result.mapValues { $0.sorted { ($0.contains(":") ? 1 : 0) < ($1.contains(":") ? 1 : 0) } }
    }

    static func readDisplayNames() -> [String: String] {
        var result: [String: String] = [:]
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return result }
        for interface in all {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? else { continue }
            result[bsd] = name
        }
        return result
    }

    static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Pulse" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }
}
