import UIKit
import os

// MARK: - SchemeRouter

/// URL 路由引擎
///
/// 替代 NavigationRouter + AppCoordinator 的硬编码导航。
///
/// **核心能力**:
/// - 二级路由 (module/action)
/// - 中间件链 (洋葱模型)
/// - 重定向 / 降级
/// - async/await 分发
/// - 与 NavigationRouter 兼容（可并行使用过渡）
///
/// **调用流程**:
/// ```
/// dispatch(url:) → parse → applyRedirect → middleware chain → handler → observers
/// ```
@MainActor
public final class SchemeRouter {

    // MARK: - Singleton

    public static let shared = SchemeRouter()

    // MARK: - Types

    private struct RedirectTarget {
        let module: String
        let action: String
    }

    // MARK: - Properties

    /// 支持的 scheme 列表 (lowercase)
    private var supportedSchemes: Set<String> = []

    /// 路由表: [module: [action: handler]]
    private var routeTable: [String: [String: RouteHandler]] = [:]

    /// 模块默认 handler（未匹配 action 时回退）
    private var moduleDefaults: [String: RouteHandler] = [:]

    /// 重定向表
    private var redirects: [String: RedirectTarget] = [:]

    /// 中间件链（按添加顺序执行）
    private var middlewares: [any RouteMiddleware] = []

    /// 全局完成监听
    private var completionObservers: [(SchemeRoute, RouteResult) -> Void] = []

    /// 导航控制器提供者（解耦 Router 对 App 结构的依赖）
    public var navigationProvider: (() -> UINavigationController?)?

    /// 当前视图控制器提供者（用于 present）
    public var topViewControllerProvider: (() -> UIViewController?)?

    /// 递归分发深度限制
    private var dispatchDepth = 0
    private let maxDispatchDepth = 10

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AOXModuleKit",
        category: "SchemeRouter"
    )

    // MARK: - Init

    public init() {}

    // MARK: - Scheme Management

    /// 注册支持的 scheme
    public func registerSchemes(_ schemes: [String]) {
        for scheme in schemes {
            supportedSchemes.insert(scheme.lowercased())
        }
    }

    /// 检查 scheme 是否支持
    public func isSupported(scheme: String) -> Bool {
        supportedSchemes.contains(scheme.lowercased())
    }

    // MARK: - Route Registration

    /// 注册路由 handler
    public func register(module: String, action: String, handler: @escaping RouteHandler) {
        let m = module.lowercased()
        let a = action.lowercased()
        if routeTable[m] == nil { routeTable[m] = [:] }

        if routeTable[m]?[a] != nil {
            Self.logger.warning("⚠️ 覆盖已注册路由: \(m)/\(a)")
        }
        routeTable[m]?[a] = handler
    }

    /// 批量注册一个模块的路由
    public func register(module: String, actions: [String: RouteHandler]) {
        for (action, handler) in actions {
            register(module: module, action: action, handler: handler)
        }
    }

    /// 注册强类型路由（自动解析参数）
    public func register<P: RouteParams>(
        module: String,
        action: String,
        paramsType: P.Type,
        handler: @escaping @MainActor (P, SchemeRoute) async -> RouteResult
    ) {
        register(module: module, action: action) { route in
            guard let params = P(route: route) else {
                return .failure(.invalidParams("参数不符合 \(String(describing: P.self)) 要求"))
            }
            return await handler(params, route)
        }
    }

    /// 注册模块默认 handler
    public func registerDefault(module: String, handler: @escaping RouteHandler) {
        moduleDefaults[module.lowercased()] = handler
    }

    /// 取消注册
    public func unregister(module: String, action: String) {
        routeTable[module.lowercased()]?[action.lowercased()] = nil
    }

    // MARK: - Redirect

    /// 注册重定向
    public func registerRedirect(
        from fromModule: String, action fromAction: String,
        to toModule: String, action toAction: String
    ) {
        let key = "\(fromModule.lowercased())/\(fromAction.lowercased())"
        redirects[key] = RedirectTarget(module: toModule.lowercased(), action: toAction.lowercased())
    }

    // MARK: - Middleware

    /// 添加中间件（按添加顺序执行）
    public func use(_ middleware: any RouteMiddleware) {
        middlewares.append(middleware)
    }

    /// 添加完成观察者
    public func onCompletion(_ observer: @escaping (SchemeRoute, RouteResult) -> Void) {
        completionObservers.append(observer)
    }

    // MARK: - Dispatch (Main Entry)

    /// 分发 URL
    ///
    /// 完整流程: parse → redirect → middleware chain → handler → observers
    @discardableResult
    public func dispatch(
        url: URL,
        source: RouteSource = .app,
        userInfo: [String: Any] = [:]
    ) async -> RouteResult {
        // 递归深度检查
        guard dispatchDepth < maxDispatchDepth else {
            Self.logger.error("❌ 路由递归分发超过 \(self.maxDispatchDepth) 层，中止: \(url.absoluteString)")
            return .failure(.handlerError("递归分发深度超限"))
        }

        // 1. 解析 URL
        guard var route = parse(url: url, source: source, userInfo: userInfo) else {
            let result: RouteResult = .failure(.invalidURL(url.absoluteString))
            return result
        }

        // 2. 应用重定向
        applyRedirect(&route)

        // 3. 执行中间件链 + 最终分发
        dispatchDepth += 1
        let result = await executeMiddlewareChain(route: &route, index: 0)
        dispatchDepth -= 1

        // 4. 降级处理 (backup)
        if !result.isSuccess, let backup = route.param("backup"),
           let backupURL = URL(string: backup) {
            Self.logger.info("路由失败，执行降级: \(backup)")
            return await dispatch(url: backupURL, source: source, userInfo: userInfo)
        }

        // 5. 链式调起 (next)
        if result.isSuccess, let next = route.param("next"),
           let nextURL = URL(string: next) {
            let delay = Double(route.param("delaytime") ?? "") ?? 0.35
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            Self.logger.info("链式调起: \(next)")
            return await dispatch(url: nextURL, source: source, userInfo: userInfo)
        }

        // 6. 通知观察者
        notifyObservers(route: route, result: result)

        return result
    }

    /// 快捷分发（字符串 URL）
    @discardableResult
    public func dispatch(
        urlString: String,
        source: RouteSource = .app,
        userInfo: [String: Any] = [:]
    ) async -> RouteResult {
        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL(urlString))
        }
        return await dispatch(url: url, source: source, userInfo: userInfo)
    }

    // MARK: - Fire-and-Forget

    /// 发起路由（fire-and-forget，无需 await）
    ///
    /// 在 UIKit 回调（按钮、手势、cellDidSelect 等）中使用，
    /// 内部创建 Task 驱动 async dispatch。
    public func open(
        _ urlString: String,
        source: RouteSource = .app,
        userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor in
            _ = await dispatch(urlString: urlString, source: source, userInfo: userInfo)
        }
    }

    /// 发起路由（fire-and-forget，URL 版本）
    public func open(
        url: URL,
        source: RouteSource = .app,
        userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor in
            _ = await dispatch(url: url, source: source, userInfo: userInfo)
        }
    }

    // MARK: - URL Parsing

    /// 解析 URL 为 SchemeRoute
    ///
    /// 支持三种格式:
    /// 1. `scheme://v{n}/module/action?params`  (版本前缀)
    /// 2. `scheme://module/action?params`        (标准)
    /// 3. `scheme://module?params`               (仅 module)
    public func parse(
        url: URL,
        source: RouteSource = .app,
        userInfo: [String: Any] = [:]
    ) -> SchemeRoute? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        guard isSupported(scheme: scheme) else {
            Self.logger.debug("不支持的 scheme: \(scheme)")
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // 解析 query
        var queryParams: [String: String] = [:]
        for item in components.queryItems ?? [] {
            let value = item.value?.replacingOccurrences(of: "+", with: " ") ?? ""
            queryParams[item.name] = value
        }

        // 解析二级 JSON
        let options = parseNestedJSON(from: queryParams)

        // 解析 module / action
        let host = components.host?.lowercased() ?? ""
        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        let (module, action) = resolveModuleAction(host: host, pathComponents: pathComponents)

        guard !module.isEmpty else {
            Self.logger.debug("无法解析 module: \(url.absoluteString)")
            return nil
        }

        return SchemeRoute(
            originalURL: url,
            scheme: scheme,
            module: module,
            action: action,
            queryParams: queryParams,
            options: options,
            userInfo: userInfo,
            source: source
        )
    }

    // MARK: - Navigation Helpers

    /// Push VC 到当前导航栈
    public func pushViewController(_ vc: UIViewController, animated: Bool = true) {
        guard let nav = navigationProvider?() else {
            Self.logger.warning("navigationProvider 未设置，无法 push")
            return
        }
        nav.pushViewController(vc, animated: animated)
    }

    /// Present VC
    public func presentViewController(_ vc: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let top = topViewControllerProvider?() else {
            Self.logger.warning("topViewControllerProvider 未设置，无法 present")
            return
        }
        top.present(vc, animated: animated, completion: completion)
    }

    // MARK: - NavigationRouter Compatibility

    /// 兼容 NavigationRouter 的页面注册方式
    ///
    /// 内部注册为 `module=pageName, action=""` 的路由
    public func registerPage(
        _ pageName: String,
        factory: @escaping @MainActor ([String: Any]) -> UIViewController?
    ) {
        register(module: pageName.lowercased(), action: "") { [weak self] route in
            var params: [String: Any] = Dictionary(uniqueKeysWithValues: route.queryParams.map { ($0.key, $0.value as Any) })
            for (key, value) in route.userInfo {
                params[key] = value
            }
            guard let vc = factory(params) else {
                return .failure(.invalidParams("工厂返回 nil: \(pageName)"))
            }
            self?.pushViewController(vc)
            return .success(data: nil)
        }
    }

    // MARK: - Diagnostics

    /// 所有已注册路由
    public var registeredRoutes: [(module: String, action: String)] {
        var result: [(String, String)] = []
        for (module, actions) in routeTable.sorted(by: { $0.key < $1.key }) {
            for action in actions.keys.sorted() {
                result.append((module, action))
            }
        }
        return result
    }

    /// 所有已注册重定向
    public var registeredRedirects: [(from: String, to: String)] {
        redirects.map { (from: $0.key, to: "\($0.value.module)/\($0.value.action)") }
            .sorted { $0.from < $1.from }
    }

    /// 检查路由是否已注册
    public func isRegistered(module: String, action: String) -> Bool {
        routeTable[module.lowercased()]?[action.lowercased()] != nil
    }

    /// 重置（仅测试用）
    public func reset() {
        supportedSchemes.removeAll()
        routeTable.removeAll()
        moduleDefaults.removeAll()
        redirects.removeAll()
        middlewares.removeAll()
        completionObservers.removeAll()
        navigationProvider = nil
        topViewControllerProvider = nil
    }

    // MARK: - Private: Parsing Helpers

    private func resolveModuleAction(host: String, pathComponents: [String]) -> (module: String, action: String) {
        // 格式 1: scheme://v5/module/action (版本前缀)
        if host.range(of: #"^v\d+$"#, options: .regularExpression) != nil {
            if pathComponents.count >= 2 {
                let module = pathComponents.dropLast().joined(separator: "/")
                let action = pathComponents.last ?? ""
                return (module, action)
            } else if pathComponents.count == 1 {
                return (pathComponents[0], "")
            }
            return ("", "")
        }

        // 格式 2: scheme://module/action (标准)
        if !pathComponents.isEmpty {
            let action = pathComponents.last ?? ""
            let moduleParts = [host] + pathComponents.dropLast()
            let module = moduleParts.joined(separator: "/")
            return (module, action)
        }

        // 格式 3: scheme://module (仅 host)
        return (host, "")
    }

    private func parseNestedJSON(from queryParams: [String: String]) -> [String: Any]? {
        for key in ["params", "options", "param"] {
            if let jsonStr = queryParams[key],
               let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        }
        return nil
    }

    // MARK: - Private: Redirect

    private func applyRedirect(_ route: inout SchemeRoute) {
        let key = "\(route.module)/\(route.action)"
        guard let target = redirects[key] else { return }

        let fromModule = route.module
        let fromAction = route.action
        Self.logger.info("重定向: \(fromModule)/\(fromAction) → \(target.module)/\(target.action)")
        route.module = target.module
        route.action = target.action
    }

    // MARK: - Private: Middleware Chain

    private func executeMiddlewareChain(route: inout SchemeRoute, index: Int) async -> RouteResult {
        if index < middlewares.count {
            let middleware = middlewares[index]
            return await middleware.process(route: &route) { [self] innerRoute in
                return await self.executeMiddlewareChain(route: &innerRoute, index: index + 1)
            }
        }
        return await dispatchToHandler(route: route)
    }

    // MARK: - Private: Final Dispatch

    private func dispatchToHandler(route: SchemeRoute) async -> RouteResult {
        let m = route.module
        let a = route.action

        // 精确匹配
        if let handler = routeTable[m]?[a] {
            Self.logger.debug("匹配路由: \(m)/\(a)")
            return await handler(route)
        }

        // 仅 module，使用模块默认 handler
        if a.isEmpty, let handler = moduleDefaults[m] {
            Self.logger.debug("匹配模块默认: \(m)")
            return await handler(route)
        }

        // action 不为空但未匹配，尝试模块默认
        if let handler = moduleDefaults[m] {
            Self.logger.debug("action 未匹配，回退到模块默认: \(m) (action=\(a))")
            return await handler(route)
        }

        Self.logger.warning("❌ 路由未匹配: \(m)/\(a)")
        if a.isEmpty {
            return .failure(.moduleNotFound(route.module))
        }
        return .failure(.actionNotFound(module: route.module, action: route.action))
    }

    // MARK: - Private: Observers

    private func notifyObservers(route: SchemeRoute, result: RouteResult) {
        for observer in completionObservers {
            observer(route, result)
        }
    }
}
