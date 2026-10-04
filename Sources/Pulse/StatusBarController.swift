import AppKit
import Combine
import SwiftUI

/// Owns the status items and the dashboard popover.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: Monitor
    private let settings: AppSettings
    private let showSettings: () -> Void

    /// Keyed by metric (separate layout), "combined", or "fallback" when every metric is switched off.
    private var items: [String: (item: NSStatusItem, kinds: [MetricKind])] = [:]
    private var layoutSignature = ""
    private let popover = NSPopover()
    private weak var popoverAnchor: NSStatusBarButton?
    private var popoverClosedAt = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    init(monitor: Monitor, settings: AppSettings, showSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.settings = settings
        self.showSettings = showSettings
        super.init()

        popover.behavior = .transient
        popover.delegate = self
        let dashboard = DashboardView(monitor: monitor, settings: settings, actions: DashboardActions(
            openSettings: { [weak self] in self?.closePopover(); self?.showSettings() },
            openActivityMonitor: { [weak self] in self?.closePopover(); Self.openActivityMonitor() },
            quit: { NSApp.terminate(nil) }
        ))
        let host = NSHostingController(rootView: dashboard)
        popover.contentViewController = host
        popover.contentSize = DashboardView.size

        settings.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.settingsChanged() } }
            .store(in: &cancellables)
        rebuild()
    }

    // MARK: - Items

    private func settingsChanged() {
        let signature = "\(settings.layout.rawValue):\(settings.enabledKinds.map(\.rawValue).joined(separator: ","))"
        if signature != layoutSignature { rebuild() } else { refresh() }
    }

    private func rebuild() {
        closePopover()
        for entry in items.values { NSStatusBar.system.removeStatusItem(entry.item) }
        items = [:]
        let kinds = settings.enabledKinds
        layoutSignature = "\(settings.layout.rawValue):\(kinds.map(\.rawValue).joined(separator: ","))"
        if kinds.isEmpty {
            makeItem(key: "fallback", kinds: [])
        } else if settings.layout != .separate {
            makeItem(key: "combined", kinds: kinds)
        } else {
            // New items appear to the left of existing ones: create right-to-left so CPU ends up first.
            for kind in kinds.reversed() { makeItem(key: kind.rawValue, kinds: [kind]) }
        }
        refresh()
    }

    private func makeItem(key: String, kinds: [MetricKind]) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "pulse.\(key)"     // remembers the position after ⌘-dragging
        if let button = item.button {
            button.identifier = NSUserInterfaceItemIdentifier(key)
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(kinds.isEmpty ? "Pulse" : kinds.map(\.title).joined(separator: ", "))
        }
        items[key] = (item, kinds)
    }

    func refresh() {
        for (key, entry) in items {
            guard let button = entry.item.button else { continue }
            let layout = key == "combined" ? settings.layout : .separate
            button.image = MenuBarRenderer.image(kinds: entry.kinds, layout: layout, settings: settings,
                                                 monitor: monitor, appearance: button.effectiveAppearance)
            button.toolTip = entry.kinds.isEmpty ? "Pulse" : MenuBarRenderer.tooltip(kinds: entry.kinds, monitor: monitor)
        }
    }

    // MARK: - Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu(for: sender)
            return
        }
        if popover.isShown {
            let sameButton = popoverAnchor === sender
            closePopover()
            if sameButton { return }
        } else if popoverAnchor === sender, Date().timeIntervalSince(popoverClosedAt) < 0.3 {
            // The transient popover already closed on mouse-down of this very click.
            return
        }
        showPopover(from: sender)
    }

    private func showPopover(from button: NSStatusBarButton) {
        let key = button.identifier?.rawValue ?? ""
        if let kind = MetricKind(rawValue: key) { settings.tab = kind.tab }
        monitor.isDetailed = true
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        PopoverSurfaceView.install(in: popover)
        popoverAnchor = button
        button.highlight(true)
    }

    private func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.isDetailed = false
        popoverClosedAt = Date()
        popoverAnchor?.highlight(false)
    }

    func openDashboard() {
        guard let button = items.values.compactMap({ $0.item.button }).first(where: { $0.window != nil }) else { return }
        showPopover(from: button)
    }

    private func showMenu(for button: NSStatusBarButton) {
        guard let key = button.identifier?.rawValue, let item = items[key]?.item else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Открыть панель", action: #selector(menuOpenDashboard(_:)), keyEquivalent: "")
            .representedObject = button
        menu.addItem(.separator())
        menu.addItem(withTitle: "Настройки…", action: #selector(menuSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Мониторинг системы", action: #selector(menuActivityMonitor), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Завершить Pulse", action: #selector(menuQuit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        closePopover()
        item.menu = menu
        button.performClick(nil)    // blocks while the menu is open
        item.menu = nil
    }

    @objc private func menuOpenDashboard(_ sender: NSMenuItem) {
        guard let button = sender.representedObject as? NSStatusBarButton else { return }
        showPopover(from: button)
    }

    @objc private func menuSettings() { showSettings() }
    @objc private func menuActivityMonitor() { Self.openActivityMonitor() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    static func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Opaque fill behind the popover content; re-resolves its color when the appearance changes.
final class PopoverSurfaceView: NSView {
    /// The dashboard draws an opaque surface; this paints the popover's arrow to match. NSPopoverFrame
    /// clips its subviews to the popover shape, so the fill follows the rounded corners and the arrow.
    static func install(in popover: NSPopover) {
        guard let frame = popover.contentViewController?.view.window?.contentView?.superview,
              !frame.subviews.contains(where: { $0 is PopoverSurfaceView }) else { return }
        let surface = PopoverSurfaceView(frame: frame.bounds)
        surface.autoresizingMask = [.width, .height]
        frame.addSubview(surface, positioned: .below, relativeTo: nil)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Palette.surface.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
