import UIKit
import os

// MARK: - ModulePriority

/// 模块初始化优先级
///
/// 值越大越先初始化。可用预设值或自定义值。
public struct ModulePriority: RawRepresentable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let `default` = ModulePriority(rawValue: 0)
    public static let low       = ModulePriority(rawValue: 100)
    public static let medium    = ModulePriority(rawValue: 500)
    public static let high      = ModulePriority(rawValue: 1000)
    public static let critical  = ModulePriority(rawValue: 2000)

    public static func custom(_ value: Int) -> ModulePriority {
        ModulePriority(rawValue: value)
    }

    public static func < (lhs: ModulePriority, rhs: ModulePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch rawValue {
        case 2000: return "critical"
        case 1000: return "high"
        case 500:  return "medium"
        case 100:  return "low"
        case 0:    return "default"
        default:   return "custom(\(rawValue))"
        }
    }
}

// MARK: - AppContext

/// 应用上下文，在模块间传递启动信息
///
/// 携带 application、launchOptions、mainWindow 等共享状态。
/// 生命周期与 App 一致，由 ModuleManager 持有。
@MainActor
public final class AppContext {
    public let application: UIApplication
    public let launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    public var mainWindow: UIWindow?

    /// 自定义扩展数据（模块间传递数据）
    public var userInfo: [String: Any] = [:]

    public init(
        application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) {
        self.application = application
        self.launchOptions = launchOptions
    }
}

// MARK: - ModuleEvent

/// 模块间自定义事件
public struct ModuleEvent: Sendable {
    public let name: String
    public let userInfo: [String: any Sendable]

    public init(name: String, userInfo: [String: any Sendable] = [:]) {
        self.name = name
        self.userInfo = userInfo
    }
}

// MARK: - AppModule Protocol

/// 模块生命周期协议
///
/// 每个业务模块实现此协议，在 `register` 中注册服务和路由，
/// 在 `initialize` 中执行重量级初始化（网络请求、DB 等）。
///
/// ```swift
/// final class AccountModule: AppModule {
///     static let priority: ModulePriority = .high
///     static let supportsPrivacyMode = true
///
///     func register(context: AppContext) {
///         ServiceRegistry.shared.register(UserIdentityProviding.self) { ... }
///     }
///
///     func initialize(context: AppContext) {
///         // 拉取用户信息等重量级操作
///     }
/// }
/// ```
@MainActor
public protocol AppModule: AnyObject {
    /// 模块优先级（值越大越先初始化）
    static var priority: ModulePriority { get }

    /// 是否支持隐私合规前初始化
    /// true: 用户同意隐私协议前即可注册（如崩溃监控、基础网络）
    /// false: 需要用户同意后才注册（如分析、广告等）
    static var supportsPrivacyMode: Bool { get }

    /// 轻量级注册阶段
    /// - 注册服务到 ServiceRegistry
    /// - 注册路由到 SchemeRouter
    /// - 订阅通知
    /// - 不应执行网络请求、磁盘 I/O 等耗时操作
    func register(context: AppContext)

    /// 重量级初始化阶段（在 register 之后延迟调用）
    /// - 可执行网络请求、数据库初始化等
    /// - 此时所有模块的服务已注册完毕，可安全 resolve
    func initialize(context: AppContext)

    /// 模块清理（App 终止或模块卸载）
    func tearDown()

    /// 自定义事件（模块间通信的补充手段）
    func handleEvent(_ event: ModuleEvent)
}

// MARK: - AppModule Defaults

@MainActor
public extension AppModule {
    static var priority: ModulePriority { .default }
    static var supportsPrivacyMode: Bool { false }
    func initialize(context: AppContext) {}
    func tearDown() {}
    func handleEvent(_ event: ModuleEvent) {}
}
