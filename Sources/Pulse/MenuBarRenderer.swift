import AppKit
import PulseCore

/// Draws the menu bar icons. Every icon is a row of "pieces" (a graphic and/or a label-over-value column)
/// rendered into one NSImage per status item. Colors are resolved against the status button's appearance,
/// so the image works on light and dark menu bars; it is re-rendered on every sample anyway.
@MainActor
enum MenuBarRenderer {
    struct Ink {
        let primary: NSColor
        let highlight: Bool

        func fill(_ severity: Severity) -> NSColor {
            highlight ? (Palette.severity(severity) ?? primary) : primary
        }

        func faint(_ alpha: CGFloat) -> NSColor { primary.withAlphaComponent(alpha) }

        static func resolve(appearance: NSAppearance, highlight: Bool) -> Ink {
            var color = NSColor.black
            appearance.performAsCurrentDrawingAppearance {
                color = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
            }
            return Ink(primary: color, highlight: highlight)
        }
    }

    private struct Piece {
        let width: CGFloat
        let draw: (_ x: CGFloat, _ height: CGFloat) -> Void
    }

    static let pieceSpacing: CGFloat = 6
    private static let graphWidth: CGFloat = 24
    private static let graphHeight: CGFloat = 16

    // MARK: - Public

    /// One status item's image. `layout` matters only when `kinds` has several metrics (a single combined item).
    static func image(kinds: [MetricKind], layout: MenuLayout = .combined, settings: AppSettings, monitor: Monitor,
                      appearance: NSAppearance, height: CGFloat = NSStatusBar.system.thickness) -> NSImage {
        let ink = Ink.resolve(appearance: appearance, highlight: settings.highlightLoad)
        var pieces: [Piece] = []
        if kinds.isEmpty {
            pieces = [symbolPiece("waveform.path.ecg", ink: ink)]
        } else if layout == .grid {
            pieces = [grid(kinds, monitor: monitor, ink: ink)]
        } else if layout == .bars {
            pieces = [bars(kinds, monitor: monitor, ink: ink)]
        } else {
            for (index, kind) in kinds.enumerated() {
                if index > 0 { pieces.append(gap(pieceSpacing)) }
                pieces.append(contentsOf: self.pieces(kind: kind, config: settings.config(kind), monitor: monitor, ink: ink))
            }
        }
        let width = ceil(pieces.reduce(0) { $0 + $1.width })
        return NSImage(size: NSSize(width: max(width, 4), height: height), flipped: true) { _ in
            var x: CGFloat = 0
            for piece in pieces {
                piece.draw(x, height)
                x += piece.width
            }
            return true
        }
    }

    static func tooltip(kinds: [MetricKind], monitor: Monitor) -> String {
        let s = monitor.latest
        return kinds.map { kind -> String in
            switch kind {
            case .cpu:
                return "CPU \(Format.percent(s.cpu.total)) — пользователь \(Format.percent(s.cpu.user)), система \(Format.percent(s.cpu.system))"
            case .gpu:
                return s.gpu.map { "GPU \(Format.percent($0.device))" } ?? "GPU — нет данных"
            case .memory:
                return "Память \(Format.bytes(s.memory.used)) из \(Format.bytes(s.memory.total))"
            case .disk:
                return "Диск: чтение \(Format.rate(s.disk.readRate)), запись \(Format.rate(s.disk.writeRate))"
            case .network:
                return "Сеть: ↓ \(Format.rate(s.network.inRate)), ↑ \(Format.rate(s.network.outRate))"
            case .temperature:
                return s.temperatures.chip.map { "Температура чипа \(Format.temperature($0))C" } ?? "Температура недоступна"
            }
        }.joined(separator: "\n")
    }

    // MARK: - Pieces per metric

    private static func pieces(kind: MetricKind, config: MetricConfig, monitor: Monitor, ink: Ink) -> [Piece] {
        let s = monitor.latest
        let recent = monitor.history.suffix(Int(graphWidth))
        switch kind {
        case .cpu, .gpu, .memory:
            let value: Double?
            let severity: Severity
            let series: [Double?]
            switch kind {
            case .cpu:
                value = s.cpu.total
                severity = .load(s.cpu.total)
                series = recent.map { $0.cpu.total }
            case .gpu:
                value = s.gpu?.device
                severity = .load(s.gpu?.device ?? 0)
                series = recent.map { $0.gpu?.device }
            default:
                value = s.memory.usedFraction
                severity = .memory(s.memory.pressure)
                series = recent.map { $0.memory.usedFraction }
            }
            let text = value.map(Format.percent) ?? "—"
            let column = textColumn(label: kind.shortLabel, value: text, template: "100%", ink: ink)
            let graphic: Piece?
            switch config.style {
            case .text: return [column]
            case .graph:
                // Memory columns are colored by pressure, not by how full RAM is.
                graphic = graph(series, ink: ink, severity: kind == .memory ? { _ in severity } : { .load($0) })
            case .bar: graphic = bar(value ?? 0, color: ink.fill(severity), ink: ink)
            case .ring: graphic = ring(value ?? 0, color: ink.fill(severity), ink: ink)
            case .cores: graphic = cores(s.cpu.cores, kinds: monitor.info.coreKinds, ink: ink)
            }
            return config.showValue ? [graphic!, gap(3), column] : [graphic!]

        case .disk:
            switch config.style {
            case .graph:
                let graphic = dualGraph(recent.map { $0.disk.readRate }, recent.map { $0.disk.writeRate },
                                        minScale: 1_000_000, ink: ink)
                return config.showValue
                    ? [graphic, gap(3), rates(top: ("R", s.disk.readRate), bottom: ("W", s.disk.writeRate), ink: ink)]
                    : [graphic]
            case .ring:
                let used = monitor.rootVolume?.usedFraction ?? 0
                let graphic = ring(used, color: ink.fill(.load(used)), ink: ink)
                let column = textColumn(label: kind.shortLabel, value: Format.percent(used), template: "100%", ink: ink)
                return config.showValue ? [graphic, gap(3), column] : [graphic]
            default:
                return [rates(top: ("R", s.disk.readRate), bottom: ("W", s.disk.writeRate), ink: ink)]
            }

        case .network:
            let column = rates(top: ("↓", s.network.inRate), bottom: ("↑", s.network.outRate), ink: ink)
            if config.style == .graph {
                let graphic = dualGraph(recent.map { $0.network.inRate }, recent.map { $0.network.outRate },
                                        minScale: 100_000, ink: ink)
                return config.showValue ? [graphic, gap(3), column] : [graphic]
            }
            return [column]

        case .temperature:
            let text = s.temperatures.chip.map(Format.temperature) ?? "—"
            return [textColumn(label: kind.shortLabel, value: text, template: "100°", ink: ink)]
        }
    }

    // MARK: - Compact layouts

    private struct CompactValue {
        let text: String
        let template: String
        let fraction: Double
        let severity: Severity
    }

    private static func compactValue(_ kind: MetricKind, monitor: Monitor) -> CompactValue {
        let s = monitor.latest
        let recent = monitor.history.suffix(30)
        switch kind {
        case .cpu:
            return CompactValue(text: Format.percent(s.cpu.total), template: "100%", fraction: s.cpu.total,
                                severity: .load(s.cpu.total))
        case .gpu:
            let device = s.gpu?.device ?? 0
            return CompactValue(text: s.gpu.map { Format.percent($0.device) } ?? "—", template: "100%",
                                fraction: device, severity: .load(device))
        case .memory:
            return CompactValue(text: Format.percent(s.memory.usedFraction), template: "100%",
                                fraction: s.memory.usedFraction, severity: .memory(s.memory.pressure))
        case .disk:
            // Throughput has no natural 100%: scale against the last half minute, at least 10 MB/s.
            let rate = s.disk.readRate + s.disk.writeRate
            let peak = max(10_000_000, recent.map { $0.disk.readRate + $0.disk.writeRate }.max() ?? 0)
            return CompactValue(text: Format.compactRate(rate), template: "999K", fraction: rate / peak, severity: .normal)
        case .network:
            let rate = s.network.inRate + s.network.outRate
            let peak = max(1_000_000, recent.map { $0.network.inRate + $0.network.outRate }.max() ?? 0)
            return CompactValue(text: Format.compactRate(rate), template: "999K", fraction: rate / peak, severity: .normal)
        case .temperature:
            let t = s.temperatures.chip
            return CompactValue(text: t.map(Format.temperature) ?? "—", template: "100°",
                                fraction: t.map { ($0 - 20) / 80 } ?? 0, severity: t.map(Severity.temperature) ?? .normal)
        }
    }

    private static let gridLetterFont = NSFont.systemFont(ofSize: 7, weight: .bold)
    private static let gridValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    /// Two rows of "letter value" cells, filled column by column: C 37% / M 80% · G 5% / D 7,2M.
    /// The letter turns orange/red at serious load — the only color, so the numbers stay legible.
    private static func grid(_ kinds: [MetricKind], monitor: Monitor, ink: Ink) -> Piece {
        let cells = kinds.map { (kind: $0, value: compactValue($0, monitor: monitor)) }
        let rows = cells.count > 1 ? 2 : 1
        let columns = (cells.count + rows - 1) / rows
        let columnGap: CGFloat = 4
        let letterWidth = attributed("M", font: gridLetterFont, color: ink.primary).size().width
        var widths: [CGFloat] = []
        for column in 0..<columns {
            let members = cells[(column * rows)..<min(cells.count, column * rows + rows)]
            let valueWidth = members.map { attributed($0.value.template, font: gridValueFont, color: ink.primary).size().width }.max() ?? 0
            widths.append(ceil(letterWidth + 2 + valueWidth))
        }
        let width = widths.reduce(0, +) + columnGap * CGFloat(max(0, columns - 1))
        return Piece(width: width) { x, height in
            let rowHeight: CGFloat = 10
            let top = (height - rowHeight * CGFloat(rows)) / 2 - 0.5
            var columnX = x
            for column in 0..<columns {
                for row in 0..<rows {
                    let index = column * rows + row
                    guard index < cells.count else { continue }
                    let cell = cells[index]
                    let y = top + CGFloat(row) * rowHeight
                    let loud = ink.highlight && cell.value.severity >= .serious
                    let letterColor = loud ? (Palette.severity(cell.value.severity) ?? ink.primary) : ink.faint(0.6)
                    attributed(cell.kind.letter, font: gridLetterFont, color: letterColor)
                        .draw(at: NSPoint(x: columnX, y: y + 1.5))
                    let value = attributed(cell.value.text, font: gridValueFont, color: ink.primary)
                    value.draw(at: NSPoint(x: columnX + widths[column] - value.size().width, y: y))
                }
                columnX += widths[column] + columnGap
            }
        }
    }

    /// A thin vertical meter per metric with its letter underneath — the narrowest layout.
    private static func bars(_ kinds: [MetricKind], monitor: Monitor, ink: Ink) -> Piece {
        let letterFont = NSFont.systemFont(ofSize: 6.5, weight: .bold)
        let barWidth: CGFloat = 4
        let slot: CGFloat = max(barWidth, ceil(attributed("M", font: letterFont, color: ink.primary).size().width))
        let spacing: CGFloat = 3
        let values = kinds.map { (kind: $0, value: compactValue($0, monitor: monitor)) }
        let width = CGFloat(values.count) * slot + CGFloat(max(0, values.count - 1)) * spacing
        return Piece(width: width) { x, height in
            let barHeight: CGFloat = 12
            let top = (height - 20) / 2
            for (i, item) in values.enumerated() {
                let slotX = x + CGFloat(i) * (slot + spacing)
                let frame = NSRect(x: slotX + (slot - barWidth) / 2, y: top, width: barWidth, height: barHeight)
                ink.faint(0.18).setFill()
                NSBezierPath(roundedRect: frame, xRadius: 1.5, yRadius: 1.5).fill()
                let h = frame.height * CGFloat(min(1, max(0, item.value.fraction)))
                if h > 0.3 {
                    ink.fill(item.value.severity).setFill()
                    NSBezierPath(roundedRect: NSRect(x: frame.minX, y: frame.maxY - h, width: barWidth, height: h),
                                 xRadius: min(1.5, h / 2), yRadius: min(1.5, h / 2)).fill()
                }
                let letter = attributed(item.kind.letter, font: letterFont, color: ink.faint(0.7))
                letter.draw(at: NSPoint(x: slotX + (slot - letter.size().width) / 2, y: top + barHeight + 0.5))
            }
        }
    }

    // MARK: - Primitives

    private static let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
    private static let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)

    private static func gap(_ width: CGFloat) -> Piece { Piece(width: width) { _, _ in } }

    private static func attributed(_ text: String, font: NSFont, color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    /// Small caps label over the value, right-aligned so the % sign doesn't jitter.
    private static func textColumn(label: String, value: String, template: String, ink: Ink) -> Piece {
        let labelText = attributed(label, font: labelFont, color: ink.faint(0.7), kern: 0.4)
        let valueText = attributed(value, font: valueFont, color: ink.primary)
        let templateWidth = attributed(template, font: valueFont, color: ink.primary).size().width
        let width = ceil(max(labelText.size().width, templateWidth, valueText.size().width))
        return Piece(width: width) { x, height in
            let top = (height - 21) / 2
            labelText.draw(at: NSPoint(x: x + width - labelText.size().width, y: top + 1))
            valueText.draw(at: NSPoint(x: x + width - valueText.size().width, y: top + 8))
        }
    }

    /// Two compact rate lines: a faint prefix (R/W, ↓/↑) and a right-aligned value.
    private static func rates(top: (String, Double), bottom: (String, Double), ink: Ink) -> Piece {
        let prefixWidth = max(attributed("W", font: labelFont, color: ink.primary).size().width,
                              attributed("↓", font: labelFont, color: ink.primary).size().width)
        let valueWidth = attributed("999K", font: rateFont, color: ink.primary).size().width
        let width = ceil(prefixWidth + 2 + valueWidth)
        return Piece(width: width) { x, height in
            let top0 = (height - 21) / 2
            for (row, line) in [top, bottom].enumerated() {
                let y = top0 + CGFloat(row) * 10
                let prefix = attributed(line.0, font: labelFont, color: ink.faint(0.7))
                prefix.draw(at: NSPoint(x: x, y: y + 1.5))
                let value = attributed(Format.compactRate(line.1), font: rateFont, color: ink.primary)
                value.draw(at: NSPoint(x: x + width - value.size().width, y: y))
            }
        }
    }

    /// A column sparkline: one 1pt column per sample, each colored by its own severity.
    private static func graph(_ values: [Double?], ink: Ink, severity: @escaping (Double) -> Severity) -> Piece {
        Piece(width: graphWidth) { x, height in
            let frame = NSRect(x: x, y: (height - graphHeight) / 2, width: graphWidth, height: graphHeight)
            ink.faint(0.13).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 2.5, yRadius: 2.5).fill()
            let inner = frame.insetBy(dx: 1, dy: 1)
            let count = Int(inner.width)
            let tail = Array(values.suffix(count))
            let offset = count - tail.count
            for (i, value) in tail.enumerated() {
                guard let value, value > 0.005 else { continue }
                let h = max(1, inner.height * CGFloat(min(1, value)))
                let color = ink.highlight ? (Palette.severity(severity(value)) ?? ink.faint(0.85)) : ink.faint(0.85)
                color.setFill()
                NSRect(x: inner.minX + CGFloat(offset + i), y: inner.maxY - h, width: 1, height: h).fill()
            }
        }
    }

    /// Read/in grows up from the middle, write/out grows down; both share one auto scale.
    private static func dualGraph(_ up: [Double], _ down: [Double], minScale: Double, ink: Ink) -> Piece {
        Piece(width: graphWidth) { x, height in
            let frame = NSRect(x: x, y: (height - graphHeight) / 2, width: graphWidth, height: graphHeight)
            ink.faint(0.13).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 2.5, yRadius: 2.5).fill()
            let inner = frame.insetBy(dx: 1, dy: 1)
            let count = Int(inner.width)
            let ups = Array(up.suffix(count)), downs = Array(down.suffix(count))
            let scale = max(minScale, ups.max() ?? 0, downs.max() ?? 0)
            let mid = inner.midY
            let half = inner.height / 2
            for (i, value) in ups.enumerated() where value > 0 {
                let h = max(0.5, half * CGFloat(value / scale))
                ink.faint(0.9).setFill()
                NSRect(x: inner.minX + CGFloat(count - ups.count + i), y: mid - h, width: 1, height: h).fill()
            }
            for (i, value) in downs.enumerated() where value > 0 {
                let h = max(0.5, half * CGFloat(value / scale))
                ink.faint(0.5).setFill()
                NSRect(x: inner.minX + CGFloat(count - downs.count + i), y: mid, width: 1, height: h).fill()
            }
        }
    }

    private static func bar(_ value: Double, color: NSColor, ink: Ink) -> Piece {
        let width: CGFloat = 6
        return Piece(width: width) { x, height in
            let frame = NSRect(x: x, y: (height - graphHeight) / 2, width: width, height: graphHeight)
            ink.faint(0.18).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 2, yRadius: 2).fill()
            let h = frame.height * CGFloat(min(1, max(0, value)))
            guard h > 0.3 else { return }
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: frame.minX, y: frame.maxY - h, width: width, height: h),
                         xRadius: min(2, h / 2), yRadius: min(2, h / 2)).fill()
        }
    }

    private static func ring(_ value: Double, color: NSColor, ink: Ink) -> Piece {
        let diameter: CGFloat = 16
        return Piece(width: diameter) { x, height in
            let lineWidth: CGFloat = 2.6
            let center = NSPoint(x: x + diameter / 2, y: height / 2)
            let radius = (diameter - lineWidth) / 2
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            ink.faint(0.2).setStroke()
            track.stroke()
            let fraction = min(1, max(0, value))
            guard fraction > 0.004 else { return }
            // Flipped context: increasing angles run clockwise on screen, -90° is 12 o'clock.
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: -90, endAngle: -90 + 360 * fraction,
                          clockwise: false)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }
    }

    /// One thin bar per core, efficiency and performance clusters separated by a wider gap.
    private static func cores(_ loads: [CoreLoad], kinds: [CoreKind], ink: Ink) -> Piece {
        let barWidth: CGFloat = loads.count > 12 ? 2 : 3
        let spacing: CGFloat = 1
        let clusterGap: CGFloat = 3
        var xs: [CGFloat] = []
        var cursor: CGFloat = 0
        for i in loads.indices {
            if i > 0 {
                cursor += spacing
                if i < kinds.count, kinds[i] != kinds[i - 1] { cursor += clusterGap - spacing }
            }
            xs.append(cursor)
            cursor += barWidth
        }
        return Piece(width: max(cursor, 4)) { x, height in
            let top = (height - graphHeight) / 2
            for (i, load) in loads.enumerated() {
                let frame = NSRect(x: x + xs[i], y: top, width: barWidth, height: graphHeight)
                ink.faint(0.16).setFill()
                frame.fill()
                let h = frame.height * CGFloat(load.total)
                guard h > 0.3 else { continue }
                ink.fill(.load(load.total)).setFill()
                NSRect(x: frame.minX, y: frame.maxY - h, width: barWidth, height: h).fill()
            }
        }
    }

    private static func symbolPiece(_ name: String, ink: Ink) -> Piece {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Pulse")?
            .withSymbolConfiguration(configuration)
        let size = symbol?.size ?? NSSize(width: 16, height: 16)
        return Piece(width: size.width) { x, height in
            guard let symbol else { return }
            let tinted = NSImage(size: size, flipped: false) { rect in
                symbol.draw(in: rect)
                ink.primary.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height))
        }
    }
}
