import OSLog

/// AOXFoundationKit 内部使用的 Logger
/// 注意：不作为 Logger extension 暴露，避免与主仓库 ServiceKit 的 Logger 分类冲突
enum FoundationLogger {
    static let network = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.aoxkit",
        category: "Network"
    )
}
