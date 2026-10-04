import Foundation

/// Russian-style number formatting (comma decimals, Cyrillic units) independent of the system locale.
public enum Format {
    public static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, fraction) * 100).rounded()))%"
    }

    public static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Memory sizes are binary (64 ГБ of RAM is 2^36 bytes); disk sizes and traffic are decimal, like Finder.
    public static func bytes(_ value: Double, binary: Bool = true) -> String {
        let (number, unit) = scaled(value, base: binary ? 1024 : 1000, units: ["Б", "КБ", "МБ", "ГБ", "ТБ", "ПБ"])
        return "\(number) \(unit)"
    }

    public static func bytes(_ value: UInt64, binary: Bool = true) -> String {
        bytes(Double(value), binary: binary)
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        bytes(bytesPerSecond, binary: false) + "/с"
    }

    /// Tight form for the menu bar, at most three characters before the unit: "0K", "870K", "12M", "1,2G".
    public static func compactRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1000 { return "0K" }
        var v = bytesPerSecond
        var index = 0
        let units = ["", "K", "M", "G", "T"]
        while v >= 999.5 && index < units.count - 1 {
            v /= 1000
            index += 1
        }
        return (v < 9.95 ? decimal(v, digits: 1) : "\(Int(v.rounded()))") + units[index]
    }

    public static func temperature(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86400, hours = total % 86400 / 3600, minutes = total % 3600 / 60
        if days > 0 { return "\(days) д \(hours) ч" }
        if hours > 0 { return "\(hours) ч \(minutes) мин" }
        if minutes > 0 { return "\(minutes) мин" }
        return "\(total) с"
    }

    /// Keeps at most three significant figures: "4,2", "42,1", "421".
    static func scaled(_ value: Double, base: Double, units: [String]) -> (String, String) {
        var v = max(0, value)
        var index = 0
        while v >= 999.5 && index < units.count - 1 {
            v /= base
            index += 1
        }
        if index == 0 { return ("\(Int(v.rounded()))", units[0]) }
        let digits = v < 99.95 ? 1 : 0
        return (decimal(v, digits: digits), units[index])
    }
}
