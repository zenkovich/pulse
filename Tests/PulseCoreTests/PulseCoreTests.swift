import XCTest
@testable import PulseCore

final class CPUMathTests: XCTestCase {
    func testLoadFromTickDeltas() {
        // user, system, idle, nice
        let old: [CPUSampler.Ticks] = [[100, 50, 850, 0], [0, 0, 1000, 0]]
        let new: [CPUSampler.Ticks] = [[160, 70, 860, 10], [0, 0, 1100, 0]]
        let sample = CPUSampler.load(from: old, to: new)
        XCTAssertEqual(sample.cores[0].user, 0.7, accuracy: 1e-9)      // (60 + 10) / 100
        XCTAssertEqual(sample.cores[0].system, 0.2, accuracy: 1e-9)
        XCTAssertEqual(sample.cores[1].total, 0, accuracy: 1e-9)
        XCTAssertEqual(sample.total, 0.45, accuracy: 1e-9)
    }

    func testCounterWrapAround() {
        let old: [CPUSampler.Ticks] = [[UInt32.max - 9, 0, 0, 0]]
        let new: [CPUSampler.Ticks] = [[10, 0, 20, 0]]
        let sample = CPUSampler.load(from: old, to: new)
        XCTAssertEqual(sample.cores[0].user, 20.0 / 40.0, accuracy: 1e-9)
    }

    func testMismatchedCoreCountsGiveZeros() {
        let sample = CPUSampler.load(from: [], to: [[1, 2, 3, 4]])
        XCTAssertEqual(sample.cores.count, 1)
        XCTAssertEqual(sample.total, 0)
    }
}

final class FormatTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(Format.bytes(UInt64(0)), "0 Б")
        XCTAssertEqual(Format.bytes(UInt64(512 * 1024 * 1024)), "512 МБ")
        XCTAssertEqual(Format.bytes(UInt64(68_719_476_736)), "64,0 ГБ")
        XCTAssertEqual(Format.bytes(Double(1_000_000_000_000), binary: false), "1,0 ТБ")
        XCTAssertEqual(Format.bytes(Double(1023 * 1024), binary: true), "1,0 МБ")
    }

    func testRates() {
        XCTAssertEqual(Format.rate(12_345_678), "12,3 МБ/с")
        XCTAssertEqual(Format.compactRate(500), "0K")
        XCTAssertEqual(Format.compactRate(870_000), "870K")
        XCTAssertEqual(Format.compactRate(12_300_000), "12M")
        XCTAssertEqual(Format.compactRate(1_240_000), "1,2M")
    }

    func testDurationAndPercent() {
        XCTAssertEqual(Format.duration(3 * 86400 + 4 * 3600 + 5), "3 д 4 ч")
        XCTAssertEqual(Format.duration(2 * 3600 + 12 * 60), "2 ч 12 мин")
        XCTAssertEqual(Format.percent(0.234), "23%")
        XCTAssertEqual(Format.percent(-0.1), "0%")
    }
}

final class HistoryTests: XCTestCase {
    private func snapshot(_ t: TimeInterval, cpu: Double = 0) -> Snapshot {
        var s = Snapshot.empty
        s.time = Date(timeIntervalSinceReferenceDate: t)
        s.cpu = CPUSample(user: cpu, system: 0, cores: [])
        return s
    }

    func testPrunesToWindow() {
        var history = History(window: 100)
        for t in stride(from: 0.0, through: 300, by: 1) { history.append(snapshot(t)) }
        XCTAssertLessThanOrEqual(history.samples.count, 161)
        XCTAssertGreaterThanOrEqual(history.samples.first!.time.timeIntervalSinceReferenceDate, 300 - 160)
        XCTAssertEqual(history.recent(10).count, 11)
    }

    func testClockGoingBackResets() {
        var history = History(window: 100)
        history.append(snapshot(50))
        history.append(snapshot(10))
        XCTAssertEqual(history.samples.count, 1)
    }

    func testDownsampleAveragesStableBuckets() {
        var history = History(window: 3600)
        for t in 0..<600 { history.append(snapshot(Double(t), cpu: t % 2 == 0 ? 1 : 0)) }
        let rows = Downsample.rows(history.recent(600), range: 600, maxPoints: 60) { [$0.cpu.total] }
        XCTAssertLessThanOrEqual(rows.count, 61)
        for row in rows { XCTAssertEqual(row.values[0], 0.5, accuracy: 0.01) }
        // Same buckets after one more sample: ids of the shared rows don't move.
        history.append(snapshot(600, cpu: 1))
        let next = Downsample.rows(history.recent(600), range: 600, maxPoints: 60) { [$0.cpu.total] }
        XCTAssertEqual(Set(rows.dropFirst().dropLast().map(\.id)).isSubset(of: Set(next.map(\.id))), true)
    }
}

final class ParsingTests: XCTestCase {
    func testPsOutput() {
        let output = """
          381  23.5 241888 WindowServer
        26441 571.7 849568 beamlab_base
          12   0.0      0 Google Chrome Helper (Renderer)
        garbage line
        """
        let entries = ProcessSampler.parse(output)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[1].cpu, 571.7, accuracy: 1e-9)
        XCTAssertEqual(entries[0].memory, 241888 * 1024)
        XCTAssertEqual(entries[2].name, "Google Chrome Helper (Renderer)")
    }

    func testGPUStats() {
        let sample = GPUSampler.parse(["Device Utilization %": 45, "Renderer Utilization %": 40,
                                       "Tiler Utilization %": 14, "In use system memory": 4_049_027_072])
        XCTAssertEqual(sample?.device ?? 0, 0.45, accuracy: 1e-9)
        XCTAssertEqual(sample?.memoryInUse, 4_049_027_072)
        XCTAssertNil(GPUSampler.parse(["recoveryCount": 0]))
    }

    func testTemperatureGroups() {
        XCTAssertEqual(TemperatureSampler.group(for: "PMU tdie3"), .chip)
        XCTAssertEqual(TemperatureSampler.group(for: "pACC MTR Temp Sensor2"), .chip)
        XCTAssertEqual(TemperatureSampler.group(for: "GPU MTR Temp Sensor1"), .gpu)
        XCTAssertEqual(TemperatureSampler.group(for: "NAND CH0 temp"), .ssd)
        XCTAssertNil(TemperatureSampler.group(for: "PMU tcal"))
    }

    func testSeverity() {
        XCTAssertEqual(Severity.load(0.5), .normal)
        XCTAssertEqual(Severity.load(0.9), .serious)
        XCTAssertEqual(Severity.memory(.critical), .critical)
    }
}

/// Reads the real machine once — no UI, safe to run anywhere.
final class LiveSamplingTests: XCTestCase {
    func testSamplesThisMac() throws {
        let sampler = SystemSampler()
        XCTAssertFalse(sampler.info.coreKinds.isEmpty)
        Thread.sleep(forTimeInterval: 0.3)
        let snapshot = sampler.sample()
        XCTAssertEqual(snapshot.cpu.cores.count, sampler.info.coreKinds.count)
        XCTAssert((0...1).contains(snapshot.cpu.total))
        XCTAssertGreaterThan(snapshot.memory.total, 0)
        XCTAssertGreaterThan(snapshot.memory.used, 0)
        XCTAssertFalse(DiskSampler.volumes().isEmpty)
        let processes = sampler.sampleProcesses()
        XCTAssertGreaterThan(processes.entries.count, 10)
        XCTAssert(processes.entries.contains { $0.name == "WindowServer" || $0.name == "launchd" })
    }

    func testTemperatureCost() {
        let sampler = TemperatureSampler()
        guard sampler.isAvailable else { return }
        let start = Date()
        for _ in 0..<10 { _ = sampler.sample() }
        let perSample = Date().timeIntervalSince(start) / 10
        print("temperature sample: \(Int(perSample * 1000)) ms, chip \(sampler.sample().chip ?? -1)")
        XCTAssertLessThan(perSample, 0.05)
    }
}
