import SwiftUI
import AppKit
import PulseCore

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let monitor: Monitor
    private var window: NSWindow?

    init(settings: AppSettings, monitor: Monitor) {
        self.settings = settings
        self.monitor = monitor
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, monitor: monitor))
            let window = NSWindow(contentViewController: host)
            window.title = "Настройки Pulse"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    static let size = CGSize(width: 580, height: 700)

    @ObservedObject var settings: AppSettings
    let monitor: Monitor

    @State private var loginState = LoginItem.state
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Основные") {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { loginState != .disabled },
                    set: { setLaunchAtLogin($0) }))
                if loginState == .requiresApproval {
                    HStack {
                        Text("macOS ждёт разрешения в «Объектах входа».").foregroundStyle(.secondary)
                        Spacer()
                        Button("Открыть настройки…") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError).foregroundStyle(Color(nsColor: Palette.critical)).font(.callout)
                }
                Picker("Обновлять каждые", selection: $settings.interval) {
                    ForEach(AppSettings.intervals, id: \.self) { interval in
                        Text("\(Int(interval)) с").tag(interval)
                    }
                }
                Toggle("Подсвечивать высокую нагрузку цветом", isOn: $settings.highlightLoad)
            }

            Section {
                Picker("Вид", selection: $settings.layout) {
                    ForEach(MenuLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                // Previews redraw with live data while the window is open.
                TimelineView(.periodic(from: .now, by: settings.interval)) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        MenuBarPreview(settings: settings, monitor: monitor)
                        Text(settings.layout.hint).font(.callout).foregroundStyle(.secondary)
                        Divider()
                        ForEach(MetricKind.allCases) { kind in
                            MetricRow(kind: kind, config: binding(for: kind), settings: settings, monitor: monitor)
                        }
                    }
                }
            } header: {
                Text("Строка меню")
            } footer: {
                Text("Порядок отдельных значков меняется перетаскиванием с зажатой ⌘. Правый клик по значку — меню.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("О программе") {
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                LabeledContent("Mac", value: "\(monitor.info.cpuModel), macOS \(monitor.info.osVersion)")
                Text("Pulse не требует прав администратора и не отправляет данные в сеть.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.size.width, height: Self.size.height)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginState = LoginItem.state
        }
    }

    private func binding(for kind: MetricKind) -> Binding<MetricConfig> {
        Binding(get: { settings.config(kind) }, set: { settings.metrics[kind] = $0 })
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Не получилось: \(error.localizedDescription)"
        }
        loginState = LoginItem.state
    }
}

/// The whole menu bar as the chosen layout draws it, on a strip that mimics the menu bar.
private struct MenuBarPreview: View {
    @ObservedObject var settings: AppSettings
    let monitor: Monitor

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)!
        let kinds = settings.enabledKinds
        let images: [NSImage] = settings.layout == .separate
            ? kinds.map { MenuBarRenderer.image(kinds: [$0], layout: .separate, settings: settings, monitor: monitor,
                                                appearance: appearance) }
            : [MenuBarRenderer.image(kinds: kinds, layout: settings.layout, settings: settings, monitor: monitor,
                                     appearance: appearance)]
        let width = images.reduce(0) { $0 + $1.size.width } + CGFloat(max(0, images.count - 1)) * 10
        return HStack(spacing: 10) {
            ForEach(images.indices, id: \.self) { Image(nsImage: images[$0]) }
            Spacer(minLength: 8)
            Text("≈ \(Int(width.rounded())) pt").font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

private struct MetricRow: View {
    let kind: MetricKind
    @Binding var config: MetricConfig
    @ObservedObject var settings: AppSettings
    let monitor: Monitor

    @Environment(\.colorScheme) private var colorScheme

    /// "Show value" only means something next to a graphic.
    private var valueToggleApplies: Bool {
        switch (kind, config.style) {
        case (_, .text), (.temperature, _): return false
        default: return true
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $config.enabled) {
                Label(kind.title, systemImage: kind.symbol)
            }
            .toggleStyle(.checkbox)
            .frame(width: 140, alignment: .leading)

            preview
                .frame(width: 110, alignment: .center)
                .opacity(config.enabled && settings.layout.usesMetricStyles ? 1 : 0.35)

            Spacer(minLength: 4)

            Picker("Вид", selection: $config.style) {
                ForEach(kind.styles) { style in Text(style.title(for: kind)).tag(style) }
            }
            .labelsHidden()
            .frame(width: 130)
            .disabled(!config.enabled || kind.styles.count < 2 || !settings.layout.usesMetricStyles)

            Toggle("Число", isOn: $config.showValue)
                .toggleStyle(.checkbox)
                .fixedSize()
                .disabled(!config.enabled || !valueToggleApplies || !settings.layout.usesMetricStyles)
                .opacity(valueToggleApplies ? 1 : 0.4)
        }
    }

    /// The real menu bar rendering on a strip that mimics the menu bar.
    private var preview: some View {
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)!
        let image = MenuBarRenderer.image(kinds: [kind], layout: .separate, settings: settings, monitor: monitor,
                                          appearance: appearance)
        return Image(nsImage: image)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}
