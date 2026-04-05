import Foundation

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
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - TimeInterval Formatting

public extension TimeInterval {
    /// 时长格式化，如 02:30、1:02:30
    var aox_durationText: String {
        Int(self).aox_durationText
    }
}
