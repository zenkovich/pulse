import SwiftUI
import AppKit
import PulseCore

/// True when rendering for `--snapshot`: platform-backed views (ScrollView) are replaced by plain stacks.
struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshot: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
    }
}

extension View {
    /// White (dark: raised grey) card with a hairline edge on the dashboard surface.
    func cardBackground(cornerRadius: CGFloat = 10) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.card)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.cardBorder, lineWidth: 0.5))
        )
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// The one big number per tab, with a caption and optional detail on the right.
struct HeroValue<Accessory: View>: View {
    let value: String
    var unit: String? = nil
    let caption: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.system(size: 34, weight: .semibold)).monospacedDigit()
                    if let unit {
                        Text(unit).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

/// Legend entry: line key in the series color, value strong, name secondary. Text never wears the series color.
struct LegendItem: View {
    let color: Color
    let name: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 10, height: 3)
            Text(value).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let detail { Text(detail).foregroundStyle(.tertiary) }
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .font(.system(size: 11.5))
    }
}

/// Status pill: icon + label so state never relies on color alone.
struct StatusBadge: View {
    let severity: Severity
    let text: String

    var body: some View {
        let color = Color.severity(severity) ?? .statusGood
        HStack(spacing: 4) {
            Image(systemName: severity == .normal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color)
            Text(text).foregroundStyle(.primary)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct MeterBar: View {
    let fraction: Double
    var color: Color = .series1
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.track)
                Capsule().fill(color)
                    .frame(width: max(fraction > 0 ? height : 0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// Horizontal stacked bar with 2pt gaps between segments; the remainder is the track.
struct SegmentedBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    let total: Double
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let visible = segments.filter { $0.value > 0 }
            let gaps = CGFloat(max(0, visible.count)) * 2
            let usable = max(0, geo.size.width - gaps)
            HStack(spacing: 2) {
                ForEach(visible) { segment in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(segment.color)
                        .frame(width: max(2, usable * CGFloat(segment.value / max(total, 1))))
                }
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.track)
            }
        }
        .frame(height: height)
    }
}

/// Capsule segmented control drawn in SwiftUI (renders in snapshots, matches the dashboard chrome).
struct RangePicker: View {
    @Binding var range: HistoryRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryRange.allCases) { option in
                Button {
                    range = option
                } label: {
                    Text(option.title)
                        .font(.system(size: 10.5, weight: option == range ? .semibold : .regular))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(option == range ? Color.primary.opacity(0.12) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(option == range ? .primary : .secondary)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.track.opacity(0.6)))
    }
}

/// Top processes with app icons. Helpers get their parent app's icon (Chrome Helper → Chrome).
struct ProcessList: View {
    let title: String
    let entries: [ProcessEntry]
    let value: (ProcessEntry) -> String
    let fraction: (ProcessEntry) -> Double
    var note: String? = nil

    var body: some View {
        Card {
            SectionHeader(title) {
                if let note { Text(note).font(.system(size: 10)).foregroundStyle(.tertiary) }
            }
            if entries.isEmpty {
                Text("Собираю список процессов…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(spacing: 7) {
                ForEach(entries) { entry in
                    HStack(spacing: 8) {
                        Image(nsImage: ProcessIcons.shared.icon(pid: entry.pid))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(entry.name)
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help("\(entry.name) — PID \(entry.pid)")
                        Spacer(minLength: 6)
                        MeterBar(fraction: fraction(entry), color: .series1, height: 4).frame(width: 48)
                        Text(value(entry))
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 62, alignment: .trailing)
                    }
                }
            }
        }
    }
}

@MainActor
final class ProcessIcons {
    static let shared = ProcessIcons()
    /// Icons downscaled once to 16pt@2x: app icons carry 1024px representations, which SwiftUI would
    /// otherwise rasterise for every row on every refresh.
    private var cache: [String: NSImage] = [:]
    private lazy var generic: NSImage = Self.small(NSWorkspace.shared.icon(for: .unixExecutable))

    func icon(pid: Int32) -> NSImage {
        let bundlePath: String?
        if let url = NSRunningApplication(processIdentifier: pid)?.bundleURL {
            bundlePath = url.path
        } else if let path = ProcessSampler.executablePath(pid: pid), let range = path.range(of: ".app/") {
            // Helpers live inside their app: the outermost .app bundle owns the icon.
            bundlePath = String(path[..<range.lowerBound]) + ".app"
        } else {
            bundlePath = nil
        }
        guard let key = bundlePath else { return generic }
        if let cached = cache[key] { return cached }
        let icon = Self.small(NSWorkspace.shared.icon(forFile: key))
        cache[key] = icon
        return icon
    }

    private static func small(_ image: NSImage) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}
