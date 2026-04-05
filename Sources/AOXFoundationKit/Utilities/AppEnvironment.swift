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

    /// API 基础 URL 配置，由宿主 App 通过 `AppEnvironment.configure(apiConfig:)` 注入
    public struct APIConfig: Sendable {
        public let apiBaseURL: String
        public let appBaseURL: String
        public let liveBaseURL: String

        public init(apiBaseURL: String, appBaseURL: String, liveBaseURL: String) {
            self.apiBaseURL = apiBaseURL
            self.appBaseURL = appBaseURL
            self.liveBaseURL = liveBaseURL
        }
    }

    /// 当前 API 配置（宿主 App 必须在启动时调用 `configure(apiConfig:)` 设置）
    private nonisolated(unsafe) static var _apiConfig: APIConfig?

    /// 配置 API 基础 URL
    public static func configure(apiConfig: APIConfig) {
        _apiConfig = apiConfig
    }

    /// API 基础 URL
    public var apiBaseURL: String {
        guard let config = Self._apiConfig else {
            fatalError("AppEnvironment.configure(apiConfig:) must be called before accessing apiBaseURL")
        }
        return config.apiBaseURL
    }

    /// App API 基础 URL
    public var appBaseURL: String {
        guard let config = Self._apiConfig else {
            fatalError("AppEnvironment.configure(apiConfig:) must be called before accessing appBaseURL")
        }
        return config.appBaseURL
    }

    /// 直播 API 基础 URL
    public var liveBaseURL: String {
        guard let config = Self._apiConfig else {
            fatalError("AppEnvironment.configure(apiConfig:) must be called before accessing liveBaseURL")
        }
        return config.liveBaseURL
    }
}
