import Foundation

// MARK: - MiddlewareNext

/// 中间件 next 函数类型
public typealias MiddlewareNext = @MainActor (inout SchemeRoute) async -> RouteResult

// MARK: - RouteMiddleware

/// 路由中间件协议（洋葱模型）
///
/// 每个中间件可以：
/// 1. 修改 route（如补充参数、重写 module/action）
/// 2. 拦截并直接返回结果（如鉴权失败）
/// 3. 调用 next() 继续链路，并对结果做后处理（如日志）
///
/// ```swift
/// struct LoggingMiddleware: RouteMiddleware {
///     func process(route: inout SchemeRoute, next: MiddlewareNext) async -> RouteResult {
///         let start = CFAbsoluteTimeGetCurrent()
///         let result = await next(&route)
///         let elapsed = CFAbsoluteTimeGetCurrent() - start
///         print("Route \(route.module)/\(route.action): \(elapsed)s")
///         return result
///     }
/// }
/// ```
@MainActor
public protocol RouteMiddleware {
    func process(route: inout SchemeRoute, next: MiddlewareNext) async -> RouteResult
}

// MARK: - AuthGuardMiddleware

/// 通用鉴权守卫中间件
public struct AuthGuardMiddleware: RouteMiddleware {
    private let checker: @MainActor (SchemeRoute) -> Bool

    public init(checker: @escaping @MainActor (SchemeRoute) -> Bool) {
        self.checker = checker
    }

    @MainActor
    public func process(route: inout SchemeRoute, next: MiddlewareNext) async -> RouteResult {
        guard checker(route) else {
            return .failure(.guardRejected(reason: "AuthGuard 校验未通过"))
        }
        return await next(&route)
    }
}

// MARK: - LoginGuardMiddleware

/// 登录拦截中间件
///
/// 对指定模块进行登录校验，未登录时调用 onLoginRequired 回调
public struct LoginGuardMiddleware: RouteMiddleware {
    private let protectedModules: Set<String>
    private let isLoggedIn: @MainActor () -> Bool
    private let onLoginRequired: @MainActor (SchemeRoute) -> Void

    public init(
        protectedModules: Set<String>,
        isLoggedIn: @escaping @MainActor () -> Bool,
        onLoginRequired: @escaping @MainActor (SchemeRoute) -> Void
    ) {
        self.protectedModules = Set(protectedModules.map { $0.lowercased() })
        self.isLoggedIn = isLoggedIn
        self.onLoginRequired = onLoginRequired
    }

    @MainActor
    public func process(route: inout SchemeRoute, next: MiddlewareNext) async -> RouteResult {
        if protectedModules.contains(route.module.lowercased()) && !isLoggedIn() {
            onLoginRequired(route)
            return .failure(.guardRejected(reason: "需要登录: \(route.module)"))
        }
        return await next(&route)
    }
}

// MARK: - AnalyticsMiddleware

/// 日志 / 打点中间件
public struct AnalyticsMiddleware: RouteMiddleware {
    private let tracker: @MainActor (SchemeRoute, RouteResult, TimeInterval) -> Void

    public init(tracker: @escaping @MainActor (SchemeRoute, RouteResult, TimeInterval) -> Void) {
        self.tracker = tracker
    }

    @MainActor
    public func process(route: inout SchemeRoute, next: MiddlewareNext) async -> RouteResult {
        let start = CFAbsoluteTimeGetCurrent()
        let result = await next(&route)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        tracker(route, result, elapsed)
        return result
    }
}

// MARK: - ParamInjectionMiddleware

/// 参数注入中间件（在分发前自动补充参数）
public struct ParamInjectionMiddleware: RouteMiddleware {
    private let injector: @MainActor (inout SchemeRoute) -> Void

    public init(injector: @escaping @MainActor (inout SchemeRoute) -> Void) {
        self.injector = injector
    }

    @MainActor
    public func process(route: inout SchemeRoute, next: MiddlewareNext) async -> RouteResult {
        injector(&route)
        return await next(&route)
    }
}
