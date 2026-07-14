import Foundation

enum MetricFormatting {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file))/s"
    }

    static func percent(_ value: Double) -> String {
        min(max(value, 0), 1).formatted(.percent.precision(.fractionLength(0)))
    }

    static func uptime(_ interval: TimeInterval) -> String {
        let totalHours = max(Int(interval) / 3600, 0)
        if totalHours >= 24 { return "\(totalHours / 24)天\(totalHours % 24)小时" }
        return "\(totalHours)小时"
    }
}
