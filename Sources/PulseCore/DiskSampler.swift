import Foundation
import IOKit

/// Disk throughput summed over all block storage drivers, plus mounted volume capacities.
public final class DiskSampler {
    private var last: (read: UInt64, write: UInt64, time: Date)?

    public init() {
        let (read, write) = Self.readCounters()
        last = (read, write, Date())
    }

    public func sample(now: Date = Date()) -> DiskSample {
        let (read, write) = Self.readCounters()
        defer { last = (read, write, now) }
        guard let last, now > last.time else {
            return DiskSample(readRate: 0, writeRate: 0, readTotal: read, writeTotal: write)
        }
        let dt = now.timeIntervalSince(last.time)
        // A drive that disappears makes the sum drop; treat that interval as idle rather than negative.
        let readRate = read >= last.read ? Double(read - last.read) / dt : 0
        let writeRate = write >= last.write ? Double(write - last.write) / dt : 0
        return DiskSample(readRate: readRate, writeRate: writeRate, readTotal: read, writeTotal: write)
    }

    private static func readCounters() -> (UInt64, UInt64) {
        var read: UInt64 = 0, write: UInt64 = 0
        Registry.forEachService("IOBlockStorageDriver") { driver in
            guard let stats = Registry.property(driver, "Statistics") as? [String: Any] else { return }
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, write)
    }

    /// Visible local volumes, the startup disk first.
    public static func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
                                      .volumeIsRootFileSystemKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                               options: [.skipHiddenVolumes]) else { return [] }
        var result: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal != false, values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { continue }
            let isRoot = values.volumeIsRootFileSystem ?? (url.path == "/")
            // "Important usage" counts purgeable space as free, which is what Finder shows.
            let available = values.volumeAvailableCapacityForImportantUsage.map { Int($0) }
                ?? values.volumeAvailableCapacity ?? 0
            result.append(VolumeInfo(path: url.path, name: values.volumeLocalizedName ?? url.lastPathComponent,
                                     total: UInt64(total), available: UInt64(max(0, min(available, total))),
                                     isRoot: isRoot, isInternal: values.volumeIsInternal ?? false))
        }
        return result.sorted { ($0.isRoot ? 0 : 1, $0.name) < ($1.isRoot ? 0 : 1, $1.name) }
    }
}
