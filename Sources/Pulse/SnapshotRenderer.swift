import AppKit
import SwiftUI
import PulseCore

/// `Pulse --snapshot <dir>`: renders the menu bar icons, every dashboard tab and the settings window to PNGs
/// in light and dark, without showing a window or touching the user's preferences. Values are this Mac's real
/// readings; the history behind the charts is synthesised around them so a fresh run has curves to draw.
@MainActor
enum SnapshotRenderer {
    static func run(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "space.zenkovich.pulse.snapshot"
        UserDefaults().removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let monitor = Monitor()

        for _ in 0..<4 {
            Thread.sleep(forTimeInterval: 0.5)
            monitor.sampleNow(includeDetail: true)
        }
        let real = monitor.history.samples
        monitor.injectHistory(synthetic(around: monitor.latest, seconds: 900) + real.suffix(2))
        monitor.isDetailed = false

        let appearances: [(String, NSAppearance)] = [("light", NSAppearance(named: .aqua)!),
                                                     ("dark", NSAppearance(named: .darkAqua)!)]
        for (name, appearance) in appearances {
            renderMenuBar(settings: settings, monitor: monitor, appearance: appearance,
                          to: directory.appendingPathComponent("menubar-\(name).png"))
        }

        settings.metrics = AppSettings.defaultMetrics
        let noop = DashboardActions(openSettings: {}, openActivityMonitor: {}, quit: {})
        for tab in DashboardTab.allCases {
            settings.tab = tab
            for (name, appearance) in appearances {
                let view = DashboardView(monitor: monitor, settings: settings, actions: noop, height: 1180)
                    .environment(\.isSnapshot, true)
                render(view, size: CGSize(width: DashboardView.size.width, height: 1180), appearance: appearance,
                       to: directory.appendingPathComponent("tab-\(tab.rawValue)-\(name).png"))
            }
        }
        settings.tab = .cpu
        for (name, appearance) in appearances {
            renderPopover(monitor: monitor, settings: settings, appearance: appearance,
                          to: directory.appendingPathComponent("popover-\(name).png"))
        }
        for (name, appearance) in appearances {
            render(SettingsView(settings: settings, monitor: monitor), size: SettingsView.size, appearance: appearance,
                   to: directory.appendingPathComponent("settings-\(name).png"))
        }
        print("snapshots written to \(directory.path)")
    }

    // MARK: - Rendering

    private static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance, to url: URL) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = CGRect(origin: .zero, size: size)
        // Never ordered front: the window only gives the view an appearance and a backing store.
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.contentView = nil
    }

    /// The real NSPopover (arrow, corners, painted frame), anchored to a window parked far off every display,
    /// captured from its own window — nothing appears on screen.
    private static func renderPopover(monitor: Monitor, settings: AppSettings, appearance: NSAppearance, to url: URL) {
        let anchorWindow = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 600, height: 40),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 200, y: 10, width: 40, height: 22))
        anchorWindow.contentView?.addSubview(anchor)
        anchorWindow.orderFrontRegardless()
        let popover = NSPopover()
        popover.animates = false
        popover.appearance = appearance
        let noop = DashboardActions(openSettings: {}, openActivityMonitor: {}, quit: {})
        popover.contentViewController = NSHostingController(rootView: DashboardView(monitor: monitor, settings: settings,
                                                                                     actions: noop))
        popover.contentSize = DashboardView.size
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        PopoverSurfaceView.install(in: popover)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        if let window = popover.contentViewController?.view.window,
           let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                               [.bestResolution]) {
            // A light backdrop like the window behind the popover in the user's screenshot.
            let size = NSSize(width: image.width, height: image.height)
            if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.width, pixelsHigh: image.height,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSColor.white.setFill()
                NSRect(origin: .zero, size: size).fill()
                NSGraphicsContext.current?.cgContext.draw(image, in: CGRect(origin: .zero, size: size))
                NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        popover.close()
        anchorWindow.orderOut(nil)
    }

    /// Every style of every metric on a strip colored like the menu bar, plus the default set.
    private static func renderMenuBar(settings: AppSettings, monitor: Monitor, appearance: NSAppearance, to url: URL) {
        let scale: CGFloat = 2
        let rowHeight: CGFloat = 34
        let width: CGFloat = 760
        var rows: [(String, [NSImage])] = []

        settings.metrics = AppSettings.defaultMetrics
        let defaults = settings.enabledKinds.map {
            MenuBarRenderer.image(kinds: [$0], layout: .separate, settings: settings, monitor: monitor,
                                  appearance: appearance, height: 22)
        }
        rows.append(("Отдельно", defaults))
        for layout in [MenuLayout.combined, .grid, .bars] {
            rows.append((layout.title, [MenuBarRenderer.image(kinds: settings.enabledKinds, layout: layout,
                                                             settings: settings, monitor: monitor,
                                                             appearance: appearance, height: 22)]))
        }
        for layout in [MenuLayout.grid, .bars] {
            rows.append((layout.title + " (все)", [MenuBarRenderer.image(kinds: MetricKind.allCases, layout: layout,
                                                                        settings: settings, monitor: monitor,
                                                                        appearance: appearance, height: 22)]))
        }
        for kind in MetricKind.allCases {
            var images: [NSImage] = []
            for style in kind.styles {
                for showValue in style == .text ? [true] : [true, false] {
                    settings.metrics[kind] = MetricConfig(enabled: true, style: style, showValue: showValue)
                    images.append(MenuBarRenderer.image(kinds: [kind], layout: .separate, settings: settings,
                                                        monitor: monitor, appearance: appearance, height: 22))
                }
            }
            rows.append((kind.title, images))
        }
        settings.highlightLoad = true

        let height = rowHeight * CGFloat(rows.count) + 12
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale),
                                         pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let dark = appearance.isDark
        NSColor(hex: dark ? 0x262626 : 0xe9e9e9).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: dark ? NSColor(white: 1, alpha: 0.6) : NSColor(white: 0, alpha: 0.55),
        ]
        for (index, row) in rows.enumerated() {
            let y = height - 6 - rowHeight * CGFloat(index + 1)
            NSAttributedString(string: row.0, attributes: captionAttributes)
                .draw(at: NSPoint(x: 12, y: y + (rowHeight - 14) / 2))
            var x: CGFloat = 120
            for image in row.1 {
                image.draw(in: NSRect(x: x, y: y + (rowHeight - 22) / 2, width: image.size.width, height: 22))
                x += image.size.width + 22
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: - Synthetic history

    /// Deterministic waves and spikes scaled around the real current values.
    private static func synthetic(around base: Snapshot, seconds: Int) -> [Snapshot] {
        var seed: UInt64 = 0x9e3779b97f4a7c15
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

        let step = 2
        var result: [Snapshot] = []
        for ago in stride(from: seconds, to: 2, by: -step) {
            let t = Double(ago)
            var s = base
            s.time = base.time.addingTimeInterval(-t)
            let wave = 0.5 + 0.5 * sin(t / 47) * cos(t / 13)
            let burst = random() < 0.04 ? 0.35 : 0
            let user = clamp(max(base.cpu.user, 0.08) * (0.5 + wave) + burst)
            let system = clamp(max(base.cpu.system, 0.04) * (0.7 + 0.6 * wave))
            let cores = base.cpu.cores.enumerated().map { k, core -> CoreLoad in
                let local = 0.5 + 0.5 * sin(t / (9 + Double(k) * 1.7) + Double(k))
                return CoreLoad(user: clamp(max(core.user, 0.05) * (0.3 + 1.4 * local) + burst * random()),
                                system: clamp(max(core.system, 0.02) * (0.6 + 0.8 * local)))
            }
            s.cpu = CPUSample(user: user, system: system, cores: cores)
            if var gpu = base.gpu {
                gpu.device = clamp(max(gpu.device, 0.1) * (0.4 + 1.2 * wave))
                gpu.renderer = gpu.device
                gpu.memoryInUse = UInt64(Double(gpu.memoryInUse) * (0.85 + 0.3 * wave))
                s.gpu = gpu
            }
            let drift = 1 + 0.04 * sin(t / 120)
            s.memory.app = UInt64(Double(base.memory.app) * drift)
            s.memory.compressed = UInt64(Double(base.memory.compressed) * (2 - drift))
            s.disk.readRate = random() < 0.15 ? random() * 40_000_000 : random() * 600_000
            s.disk.writeRate = random() < 0.1 ? random() * 25_000_000 : random() * 400_000
            s.network.inRate = (0.5 + wave) * 900_000 + (random() < 0.05 ? 6_000_000 : 0)
            s.network.outRate = (0.5 + wave) * 120_000
            if let chip = base.temperatures.chip {
                s.temperatures.chip = chip - 6 + 10 * wave
            }
            result.append(s)
        }
        return result
    }
}
