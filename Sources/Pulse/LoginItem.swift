import Foundation
import ServiceManagement

/// Launch at login. SMAppService is the native way (shows up in System Settings → Login Items);
/// a per-user LaunchAgent is the fallback for builds that macOS refuses to register.
enum LoginItem {
    enum State {
        case enabled, disabled, requiresApproval
    }

    private static let agentLabel = "space.zenkovich.pulse"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return FileManager.default.fileExists(atPath: agentURL.path) ? .enabled : .disabled
        }
    }

    static var isEnabled: Bool { state != .disabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                try installAgent()
            }
        } else {
            if SMAppService.mainApp.status != .notRegistered {
                try? SMAppService.mainApp.unregister()
            }
            try? FileManager.default.removeItem(at: agentURL)
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func installAgent() throws {
        guard let executable = Bundle.main.executablePath else { throw CocoaError(.fileNoSuchFile) }
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: agentURL)
    }
}
