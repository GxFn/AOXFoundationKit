import OSLog

// MARK: - Structured Logging

/// 统一日志系统，替代 NSLog，使用 os.Logger（Swift 原生结构化日志）
/// 优势：性能更优（惰性求值）、支持 Console.app 过滤、支持 signpost
/// Release 环境下 debug 级别日志自动被系统丢弃（os_log 特性），无需手动过滤
public extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bilidili"

    /// 应用生命周期
    static let app = Logger(subsystem: subsystem, category: "App")
    /// 路由导航
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")
    /// 网络层
    static let network = Logger(subsystem: subsystem, category: "Network")
    /// 账号管理
    static let account = Logger(subsystem: subsystem, category: "Account")
    /// 视频播放器
    static let player = Logger(subsystem: subsystem, category: "Player")
    /// 视频 Feed
    static let videoFeed = Logger(subsystem: subsystem, category: "VideoFeed")
    /// 视频缓存
    static let videoCache = Logger(subsystem: subsystem, category: "VideoCache")
    /// 首页
    static let home = Logger(subsystem: subsystem, category: "Home")
    /// WBI 签名
    static let wbi = Logger(subsystem: subsystem, category: "WBI")
    /// 资源加载
    static let resourceLoader = Logger(subsystem: subsystem, category: "ResourceLoader")
    /// 预加载
    static let preloader = Logger(subsystem: subsystem, category: "Preloader")
    /// 作者页
    static let author = Logger(subsystem: subsystem, category: "Author")
    /// WebSocket连接
    static let webSocket = Logger(subsystem: subsystem, category: "WebSocket")
    /// 直播弹幕
    static let liveChat = Logger(subsystem: subsystem, category: "LiveChat")
    /// 心跳
    static let heartbeat = Logger(subsystem: subsystem, category: "Heartbeat")
    /// 关注
    static let following = Logger(subsystem: subsystem, category: "Following")
}

// MARK: - Debug-only Logging

public extension Logger {
    /// 仅在 Debug/Beta 环境输出的日志（Release 编译期直接移除）
    /// 用于高频调试信息，避免 Release 包中的字符串插值开销
    @inlinable
    func verbose(_ message: @autoclosure () -> String) {
        #if DEBUG
        let msg = message()
        self.debug("\(msg)")
        #endif
    }
}
