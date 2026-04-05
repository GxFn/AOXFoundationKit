import Foundation

// MARK: - RouteResult

/// 路由处理结果
public enum RouteResult: Sendable {
    case success(data: (any Sendable)? = nil)
    case failure(RouteError)

    /// 是否成功
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - RouteError

/// 路由错误类型
public enum RouteError: Error, CustomStringConvertible, Sendable {
    case unsupportedScheme(String)
    case invalidURL(String)
    case moduleNotFound(String)
    case actionNotFound(module: String, action: String)
    case guardRejected(reason: String)
    case invalidParams(String)
    case handlerError(String)
    case noNavigationController

    public var description: String {
        switch self {
        case .unsupportedScheme(let s): return "不支持的 scheme: \(s)"
        case .invalidURL(let u): return "无效 URL: \(u)"
        case .moduleNotFound(let m): return "未注册的 module: \(m)"
        case .actionNotFound(let m, let a): return "未注册的 action: \(m)/\(a)"
        case .guardRejected(let r): return "鉴权拒绝: \(r)"
        case .invalidParams(let p): return "参数无效: \(p)"
        case .handlerError(let e): return "处理器错误: \(e)"
        case .noNavigationController: return "未找到 NavigationController"
        }
    }
}

// MARK: - RouteSource

/// 路由调起来源
public enum RouteSource: Sendable {
    /// App 内部
    case app
    /// 外部 App
    case external(app: String?)
    /// WebView 调起
    case webView
    /// Universal Link
    case deepLink
    /// 推送通知
    case push
}

// MARK: - SchemeRoute

/// 路由解析结果（值类型，中间件无法意外修改原始路由引用）
public struct SchemeRoute {
    public let originalURL: URL
    public let scheme: String
    public var module: String
    public var action: String

    /// URL query 参数
    public let queryParams: [String: String]

    /// 从 query 中 "params" / "options" 字段解析出的二级 JSON
    public let options: [String: Any]?

    /// 附加上下文（middleware 可写入）
    public var userInfo: [String: Any]

    /// 调起来源
    public let source: RouteSource

    public init(
        originalURL: URL,
        scheme: String,
        module: String,
        action: String,
        queryParams: [String: String] = [:],
        options: [String: Any]? = nil,
        userInfo: [String: Any] = [:],
        source: RouteSource = .app
    ) {
        self.originalURL = originalURL
        self.scheme = scheme
        self.module = module
        self.action = action
        self.queryParams = queryParams
        self.options = options
        self.userInfo = userInfo
        self.source = source
    }

    // MARK: - Convenience

    /// 获取 query 参数
    public func param(_ key: String) -> String? {
        queryParams[key]
    }

    /// 获取 Int 参数
    public func intParam(_ key: String) -> Int? {
        guard let str = queryParams[key] else { return nil }
        return Int(str)
    }

    /// 获取 Bool 参数
    public func boolParam(_ key: String) -> Bool? {
        guard let str = queryParams[key]?.lowercased() else { return nil }
        switch str {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    /// 获取 options 中的值
    public func option<T>(_ key: String) -> T? {
        options?[key] as? T
    }
}

// MARK: - RouteParams Protocol

/// 强类型路由参数协议
///
/// ```swift
/// struct VideoPlayParams: RouteParams {
///     let bvid: String
///     let aid: Int?
///
///     init?(route: SchemeRoute) {
///         guard let bvid = route.param("bvid"), !bvid.isEmpty else { return nil }
///         self.bvid = bvid
///         self.aid = route.intParam("aid")
///     }
/// }
/// ```
public protocol RouteParams {
    init?(route: SchemeRoute)
}

// MARK: - RouteHandler

/// 路由处理闭包
public typealias RouteHandler = @MainActor (SchemeRoute) async -> RouteResult
