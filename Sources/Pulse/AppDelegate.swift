import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var monitor: Monitor!
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()

    /// Created from main.swift's top-level code, which isn't main-actor isolated in Swift 5 mode.
    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            SnapshotRenderer.run(directory: URL(fileURLWithPath: arguments[index + 1]))
            exit(0)
        }
        // `Pulse --login-item status|on|off`: manage launch at login from a script.
        if let index = arguments.firstIndex(of: "--login-item") {
            let command = index + 1 < arguments.count ? arguments[index + 1] : "status"
            do {
                if command == "on" || command == "off" { try LoginItem.setEnabled(command == "on") }
                print("launch at login: \(LoginItem.state)")
                exit(0)
            } catch {
                print("launch at login: failed — \(error.localizedDescription)")
                exit(1)
            }
        }
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            // Already running (e.g. started by hand while the login item is active).
            NSApp.terminate(nil)
            return
        }

        settings = AppSettings()
        monitor = Monitor()
        settingsWindow = SettingsWindowController(settings: settings, monitor: monitor)
        statusBar = StatusBarController(monitor: monitor, settings: settings) { [weak self] in
            self?.settingsWindow.show()
        }
        monitor.onSample = { [weak self] in self?.statusBar.refresh() }
        monitor.start(interval: settings.interval)

        settings.$interval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] interval in self?.monitor.start(interval: interval) }
            .store(in: &cancellables)
    }

    /// Opening Pulse.app again while it runs: show the dashboard, it's the most likely intent.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.openDashboard()
        return false
    }
}
