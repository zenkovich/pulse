import Foundation
import Darwin

/// Top processes. `ps` is setuid root, so unlike proc_pid_rusage it sees every user's processes
/// (WindowServer, kernel_task, daemons) — without Pulse needing privileges of its own.
public final class ProcessSampler {
    public init() {}

    public func sample() -> [ProcessEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pid=,pcpu=,rss=,comm="]
        process.environment = ["LC_ALL": "C"]   // a Russian locale would print "12,5"
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var entries = Self.parse(String(decoding: data, as: UTF8.self))
        // Activity Monitor's "Memory" is the physical footprint; readable for our own processes only.
        for i in entries.indices {
            if let footprint = Self.footprint(pid: entries[i].pid) { entries[i].memory = footprint }
        }
        return entries
    }

    public static func parse(_ output: String) -> [ProcessEntry] {
        var result: [ProcessEntry] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]),
                  let rssKB = UInt64(parts[2]) else { continue }
            result.append(ProcessEntry(pid: pid, name: String(parts[3]), cpu: cpu, memory: rssKB * 1024))
        }
        return result
    }

    static func footprint(pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 && info.ri_phys_footprint > 0 ? info.ri_phys_footprint : nil
    }

    public static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    public static func processCount() -> Int {
        Int(proc_listallpids(nil, 0))
    }
}
