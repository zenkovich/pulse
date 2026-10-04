import SwiftUI
import PulseCore

struct DashboardActions {
    let openSettings: () -> Void
    let openActivityMonitor: () -> Void
    let quit: () -> Void
}

/// The popover: tab bar, one scrollable page per metric, footer with app actions.
struct DashboardView: View {
    static let size = NSSize(width: 400, height: 640)

    @ObservedObject var monitor: Monitor
    @ObservedObject var settings: AppSettings
    let actions: DashboardActions
    /// Snapshots render taller pages without a ScrollView.
    var height: CGFloat = DashboardView.size.height

    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(spacing: 0) {
            TabBar(selection: $settings.tab)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)
            Divider()
            if isSnapshot {
                page.frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView { page }
            }
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: height)
        .background(Color.surface)
    }

    private var page: some View {
        Group {
            switch settings.tab {
            case .overview: OverviewTab(monitor: monitor, settings: settings)
            case .cpu: CPUTab(monitor: monitor, settings: settings)
            case .gpu: GPUTab(monitor: monitor, settings: settings)
            case .memory: MemoryTab(monitor: monitor, settings: settings)
            case .disk: DiskTab(monitor: monitor, settings: settings)
            case .network: NetworkTab(monitor: monitor, settings: settings)
            }
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button(action: actions.openActivityMonitor) {
                Label("Мониторинг системы", systemImage: "chart.bar.doc.horizontal")
            }
            Spacer()
            Button(action: actions.openSettings) {
                Image(systemName: "gearshape")
            }
            .help("Настройки")
            Button(action: actions.quit) {
                Image(systemName: "power")
            }
            .help("Завершить Pulse")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct TabBar: View {
    @Binding var selection: DashboardTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 14, weight: .regular))
                            .frame(height: 17)
                        Text(tab.title).font(.system(size: 10, weight: tab == selection ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tab == selection ? Color.primary.opacity(0.1) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == selection ? .primary : .secondary)
            }
        }
    }
}
