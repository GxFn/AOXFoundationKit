import Foundation
import OSLog

private let durationFormattingLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.aoxkit",
    category: "DurationFormatting"
)

// MARK: - Number Formatting

public extension Int {
    /// 格式化为短数字，如 1.2万、352.1万
    var aox_shortText: String {
        if self >= 100_000_000 {
            return String(format: "%.1f亿", Double(self) / 100_000_000)
        } else if self >= 10_000 {
            return String(format: "%.1f万", Double(self) / 10_000)
        }
        return "\(self)"
    }

    /// 时长格式化，如 02:30、1:02:30
    var aox_durationText: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        if hours > 0 {
            // hours 可能超过 C int；直接插值避免 %d 将 64 位 Int 截断。
            return "\(hours):" + String(format: "%02d:%02d", minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - TimeInterval Formatting

public extension TimeInterval {
    /// 时长格式化，如 02:30、1:02:30
    var aox_durationText: String {
        // AVFoundation 的未知时间可能是 NaN/∞；浮点转 Int 对这些值会直接 trap。
        // Double(Int.max) 会向上舍入，必须用严格小于，不能把该边界本身转回 Int。
        guard isFinite, self >= 0, self < Double(Int.max) else {
            durationFormattingLogger.warning(
                "无效媒体时长，使用 00:00: finite=\(self.isFinite), negative=\(self < 0), integerRange=\(self < Double(Int.max))"
            )
            return "00:00"
        }
        return Int(self).aox_durationText
    }
}
