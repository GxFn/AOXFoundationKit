import Foundation

// MARK: - App Environment

/// 应用运行环境，通过编译条件区分
/// - Debug: 开发调试，完整日志，可连调试器
/// - Release: 正式发布，最小日志，性能优化
public enum AppEnvironment: String, Sendable {
    case debug
    case release

    // MARK: - Current

    /// 当前运行环境
    public static let current: AppEnvironment = {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }()

    // MARK: - Properties

    /// 环境显示名称
    public var displayName: String {
        switch self {
        case .debug:   return "Debug"
        case .release: return "Release"
        }
    }

    /// 是否为调试环境
    public var isDebug: Bool { self == .debug }

    /// 是否允许详细日志
    public var verboseLoggingEnabled: Bool { self == .debug }

    /// 是否显示调试浮窗/入口
    public var showsDebugUI: Bool { self == .debug }

    // MARK: - API Configuration

    /// B 站主 API 域名
    public var apiBaseURL: String { "https://api.bilibili.com" }

    /// B 站 App API 域名（feed 流专用）
    public var appBaseURL: String { "https://app.bilibili.com" }

    /// B 站直播 API 域名
    public var liveBaseURL: String { "https://api.live.bilibili.com" }
}
