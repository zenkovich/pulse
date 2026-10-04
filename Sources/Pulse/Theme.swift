import AppKit
import SwiftUI
import PulseCore

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(hex: appearance.isDark ? dark : light)
        }
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Chart colors: the first categorical slots of the validated palette, stepped per mode,
/// and the reserved status colors (used only for severity, never as a series).
enum Palette {
    static let series1 = NSColor.dynamic(light: 0x2a78d6, dark: 0x3987e5)   // blue
    static let series2 = NSColor.dynamic(light: 0xeb6834, dark: 0xd95926)   // orange
    static let series3 = NSColor.dynamic(light: 0x1baf7a, dark: 0x199e70)   // aqua

    static let good = NSColor(hex: 0x0ca30c)
    static let warning = NSColor(hex: 0xfab219)
    static let serious = NSColor(hex: 0xec835a)
    static let critical = NSColor(hex: 0xd03b3b)

    /// Opaque dashboard surfaces (System Settings' grouped look). The popover's own material is translucent,
    /// and in dark mode over a white window it turns mid-grey and washes the text out.
    static let surface = NSColor.dynamic(light: 0xf2f2f4, dark: 0x1e1e1e)
    static let cardSurface = NSColor.dynamic(light: 0xffffff, dark: 0x2c2c2e)
    static let cardBorder = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.07)
    }

    static func severity(_ severity: Severity) -> NSColor? {
        switch severity {
        case .normal: return nil
        case .warning: return warning
        case .serious: return serious
        case .critical: return critical
        }
    }
}

extension Color {
    static let series1 = Color(nsColor: Palette.series1)
    static let series2 = Color(nsColor: Palette.series2)
    static let series3 = Color(nsColor: Palette.series3)
    static let statusGood = Color(nsColor: Palette.good)

    /// Neutral fill for meter tracks and chart gridlines.
    static let track = Color.primary.opacity(0.08)
    static let surface = Color(nsColor: Palette.surface)
    static let card = Color(nsColor: Palette.cardSurface)
    static let cardBorder = Color(nsColor: Palette.cardBorder)

    static func severity(_ severity: Severity) -> Color? {
        Palette.severity(severity).map { Color(nsColor: $0) }
    }
}
