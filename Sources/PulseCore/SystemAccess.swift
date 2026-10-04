import Foundation
import IOKit

enum Sysctl {
    static func value<T>(_ name: String, as: T.Type, default fallback: T) -> T {
        var value = fallback
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return fallback }
        return value
    }

    /// Integer sysctls come as 4 or 8 bytes; reading into a zeroed Int64 handles both on little-endian.
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

enum Registry {
    static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Looks the key up on the entry and then on its parents (Intel GPUs keep "model" on the PCI device).
    static func searchProperty(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let data = value as? Data, !data.isEmpty {
            var result: UInt64 = 0
            for (i, byte) in data.prefix(8).enumerated() { result |= UInt64(byte) << (8 * UInt64(i)) }
            return Int(result)
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let data = value as? Data {
            let bytes = data.prefix { $0 != 0 }
            return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
        }
        return nil
    }

    /// Calls `body` for every service matching `className`; the service is released afterwards.
    static func forEachService(_ className: String, _ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    static func forEachChild(_ entry: io_registry_entry_t, plane: String, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, plane, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var child = IOIteratorNext(iterator)
        while child != 0 {
            body(child)
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func number(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
}
