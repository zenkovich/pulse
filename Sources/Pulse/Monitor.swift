import AppKit
import Combine
import PulseCore

/// Samples on a background queue, keeps the history, and tells the UI when to redraw.
/// The dashboard only re-renders (`revision` changes) while it is open, so a closed popover costs nothing.
@MainActor
final class Monitor: ObservableObject {
    let info: SystemInfo
    let hasTemperatures: Bool

    private(set) var latest = Snapshot.empty
    private(set) var history = History(window: 3600)
    private(set) var detail = DetailSample()
    /// The startup volume, refreshed now and then even with the dashboard closed (for the disk ring).
    private(set) var rootVolume: VolumeInfo?

    /// Bumped on every sample while the dashboard is visible.
    @Published private(set) var revision = 0

    /// Called after every sample (status bar images).
    var onSample: (() -> Void)?

    /// True while the dashboard is on screen: enables process, volume and interface sampling.
    var isDetailed = false {
        didSet {
            guard isDetailed != oldValue, isDetailed else { return }
            lastProcessTime = .distantPast
            lastVolumeTime = .distantPast
            tick()
        }
    }

    private let sampler: SystemSampler
    private let queue = DispatchQueue(label: "space.zenkovich.pulse.sampler", qos: .utility)
    private var timer: Timer?
    private var inFlight = false
    /// A tick requested while one was running (e.g. the dashboard just opened) runs right after it.
    private var tickPending = false
    private var lastProcessTime = Date.distantPast
    private var lastVolumeTime = Date.distantPast
    private var lastRootVolumeTime = Date.distantPast
    private var wakeObserver: NSObjectProtocol?

    init() {
        let sampler = SystemSampler()
        self.sampler = sampler
        info = sampler.info
        hasTemperatures = sampler.hasTemperatures
        rootVolume = DiskSampler.volumes().first { $0.isRoot }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Rates across a sleep are meaningless; drop the first post-wake interval by sampling right away.
            Task { @MainActor in self?.tick() }
        }
    }

    func start(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = interval * 0.1
        // .common keeps ticking while a menu is open or a slider is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func tick() {
        guard !inFlight else {
            tickPending = true
            return
        }
        inFlight = true
        let now = Date()
        let wantProcesses = isDetailed && now.timeIntervalSince(lastProcessTime) >= 1.9
        let wantVolumes = isDetailed && now.timeIntervalSince(lastVolumeTime) >= 10
        let wantRoot = now.timeIntervalSince(lastRootVolumeTime) >= 60
        let wantInterfaces = isDetailed
        if wantProcesses { lastProcessTime = now }
        if wantVolumes { lastVolumeTime = now }
        if wantRoot { lastRootVolumeTime = now }

        let sampler = self.sampler
        queue.async { [weak self] in
            let snapshot = sampler.sample(now: now)
            let processes = wantProcesses ? sampler.sampleProcesses() : nil
            let volumes = (wantVolumes || wantRoot) ? DiskSampler.volumes() : nil
            let interfaces = wantInterfaces ? sampler.sampleInterfaces() : nil
            let loads = CPUSampler.loadAverage()
            let uptime = CPUSampler.uptime(now: now)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                self.latest = snapshot
                self.history.append(snapshot)
                if let volumes {
                    self.rootVolume = volumes.first { $0.isRoot } ?? self.rootVolume
                    if wantVolumes { self.detail.volumes = volumes }
                }
                if let processes {
                    self.detail.processes = processes.entries
                    self.detail.processCount = processes.count
                }
                if let interfaces { self.detail.interfaces = interfaces }
                self.detail.loadAverage = loads
                self.detail.uptime = uptime
                self.detail.thermalState = ProcessInfo.processInfo.thermalState
                if self.isDetailed { self.revision &+= 1 }
                self.onSample?()
                if self.tickPending {
                    self.tickPending = false
                    self.tick()
                }
            }
        }
    }

    /// Synchronous sampling for the snapshot renderer (no timers, no run loop).
    func sampleNow(includeDetail: Bool) {
        let now = Date()
        let snapshot = sampler.sample(now: now)
        latest = snapshot
        history.append(snapshot)
        if includeDetail {
            let processes = sampler.sampleProcesses()
            detail.processes = processes.entries
            detail.processCount = processes.count
            detail.volumes = DiskSampler.volumes()
            rootVolume = detail.volumes.first { $0.isRoot }
            detail.interfaces = sampler.sampleInterfaces()
            detail.loadAverage = CPUSampler.loadAverage()
            detail.uptime = CPUSampler.uptime(now: now)
            detail.thermalState = ProcessInfo.processInfo.thermalState
        }
        revision &+= 1
    }

    /// Lets the snapshot renderer seed a longer, synthetic history so charts have something to show.
    func injectHistory(_ snapshots: [Snapshot]) {
        history = History(window: 3600)
        snapshots.forEach { history.append($0) }
        if let last = snapshots.last { latest = last }
        revision &+= 1
    }
}
