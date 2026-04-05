import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bilidili"

    /// 网络层（NetworkMonitor 使用）
    static let network = Logger(subsystem: subsystem, category: "Network")
}
