import UIKit
import OSLog

// MARK: - Navigation Router

/// URL 路由跳转管理器
///
/// > 已被 `SchemeRouter` 替代。新代码请使用 `SchemeRouter.shared`。
/// > 现有调用仍正常工作，内部实现保持不变以确保向后兼容。
///
/// 注册方式：
/// ```
/// NavigationRouter.register("videoPlayer", factory: { params in
///     guard let video = params["videoModel"] as? VideoModel else { return nil }
///     return VideoPlayViewController(video: video)
/// })
/// ```
///
/// 跳转方式：
/// ```
/// NavigationRouter.push("videoPlayer", params: ["videoModel": video], from: nav)
/// ```
@MainActor
public final class NavigationRouter {

    public static let shared = NavigationRouter()

    // MARK: - Types

    public typealias ViewControllerFactory = (_ params: [String: Any]) -> UIViewController?

    // MARK: - Properties

    /// 页面名称 → 工厂闭包映射表
    private var pageMap: [String: ViewControllerFactory] = [:]

    private init() {}

    // MARK: - Registration

    /// 注册页面名称对应的 ViewController 工厂
    public func register(_ pageName: String, factory: @escaping ViewControllerFactory) {
        pageMap[pageName] = factory
    }

    /// 批量注册
    public func register(_ entries: [String: ViewControllerFactory]) {
        for (name, factory) in entries {
            pageMap[name] = factory
        }
    }

    // MARK: - ViewController Creation

    /// 根据页面名称和参数创建 ViewController
    public func viewController(for pageName: String, params: [String: Any] = [:]) -> UIViewController? {
        guard let factory = pageMap[pageName] else {
            Logger.navigation.warning("未注册的页面: \\(pageName)")
            return nil
        }
        return factory(params)
    }

    // MARK: - Navigation

    /// Push 跳转到指定页面
    @discardableResult
    public func push(
        _ pageName: String,
        params: [String: Any] = [:],
        from navigationController: UINavigationController?,
        animated: Bool = true
    ) -> UIViewController? {
        guard let vc = viewController(for: pageName, params: params) else { return nil }
        navigationController?.pushViewController(vc, animated: animated)
        return vc
    }

    /// Present 跳转到指定页面
    @discardableResult
    public func present(
        _ pageName: String,
        params: [String: Any] = [:],
        from viewController: UIViewController?,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) -> UIViewController? {
        guard let vc = self.viewController(for: pageName, params: params) else { return nil }
        viewController?.present(vc, animated: animated, completion: completion)
        return vc
    }

    // MARK: - URL Scheme

    /// 处理 URL Scheme 跳转（bilidili://pageName?key=value&key2=value2）
    /// 返回是否成功处理
    @discardableResult
    public func handleURL(
        _ url: URL,
        from navigationController: UINavigationController?,
        animated: Bool = true
    ) -> Bool {
        // 仅允许 bilibili scheme，防止恶意 URL 注入
        guard url.scheme == "bilidili" else { return false }
        guard let pageName = url.host else { return false }

        // 解析 URL 查询参数为字典
        var params: [String: Any] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                params[item.name] = item.value ?? ""
            }
        }

        return push(pageName, params: params, from: navigationController, animated: animated) != nil
    }

    // MARK: - Query

    /// 检查页面是否已注册
    public func isRegistered(_ pageName: String) -> Bool {
        pageMap[pageName] != nil
    }

    /// 获取所有已注册的页面名称
    public var registeredPages: [String] {
        Array(pageMap.keys).sorted()
    }
}

// MARK: - Page Names

/// 预定义页面名称常量
public enum RouterPage {
    public static let home = "home"
    public static let videoFeed = "videoFeed"
    public static let videoPlayer = "videoPlayer"
    public static let profile = "profile"
    public static let author = "author"
    public static let webLogin = "webLogin"
    public static let web = "web"
    public static let liveRoom = "liveRoom"
}
