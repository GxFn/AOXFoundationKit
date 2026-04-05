import UIKit
import os

// MARK: - ModuleManager

/// 模块生命周期管理器
///
/// 对应 BiliDemo 的 BDPyramid + BDPModuleCenter。
/// 管理所有模块的注册、初始化、清理，以及系统事件转发。
///
/// **生命周期流程**:
/// ```
/// add() → registerAll(context:) → [延迟] initializeAll() → tearDownAll()
///            │                         │
///            ├── 按优先级降序排序       ├── 按优先级降序执行
///            ├── 逐个调 module.register │
///            └── os_signpost 记录耗时   └── os_signpost 记录耗时
/// ```
@MainActor
public final class ModuleManager {

    // MARK: - Singleton

    public static let shared = ModuleManager()

    // MARK: - Properties

    private var modules: [any AppModule] = []
    private var isRegistered = false
    private var isInitialized = false
    private(set) public var context: AppContext?

    /// 延迟初始化的时间间隔（默认 3 秒）
    public var initializeDelay: TimeInterval = 3.0

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BDModuleKit",
        category: "ModuleManager"
    )

    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "BDModuleKit",
        category: .pointsOfInterest
    )

    // MARK: - Init

    /// 创建独立实例（用于测试；生产使用 `.shared`）
    public init() {}

    // MARK: - Module Registration

    /// 添加模块
    ///
    /// 必须在 `registerAll()` 之前调用。
    public func add(_ module: any AppModule) {
        guard !isRegistered else {
            assertionFailure("❌ ModuleManager: 不能在 registerAll() 之后添加模块 [\(type(of: module))]")
            Self.logger.error("尝试在 registerAll 之后添加模块: \(String(describing: type(of: module)))")
            return
        }
        modules.append(module)
    }

    /// 批量添加
    public func add(_ modules: [any AppModule]) {
        for module in modules { add(module) }
    }

    // MARK: - Lifecycle: Register Phase

    /// 执行注册阶段
    ///
    /// 1. 按优先级降序排序
    /// 2. 逐个调用 module.register(context:)
    /// 3. 记录每个模块的注册耗时
    ///
    /// 调用一次后再次调用无效。
    public func registerAll(context: AppContext) {
        guard !isRegistered else {
            Self.logger.warning("registerAll 重复调用，已忽略")
            return
        }
        self.context = context
        isRegistered = true

        // 按优先级降序排序（高优先级先注册）
        modules.sort { type(of: $0).priority > type(of: $1).priority }

        let totalState = Self.signposter.beginInterval("registerAll")
        let totalStart = CFAbsoluteTimeGetCurrent()

        for module in modules {
            let name = String(describing: type(of: module))
            let state = Self.signposter.beginInterval("register", "\(name)")
            let start = CFAbsoluteTimeGetCurrent()

            module.register(context: context)

            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            Self.signposter.endInterval("register", state)
            Self.logger.info("[\(name)] register: \(String(format: "%.1f", elapsed))ms (priority: \(type(of: module).priority))")
        }

        let totalElapsed = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        Self.signposter.endInterval("registerAll", totalState)
        Self.logger.info("✅ 全部 \(self.modules.count) 个模块注册完成，总耗时: \(String(format: "%.1f", totalElapsed))ms")
    }

    // MARK: - Lifecycle: Initialize Phase

    /// 执行初始化阶段
    ///
    /// 通常在 register 后延迟调用。此时所有服务已注册，可安全 resolve。
    public func initializeAll() {
        guard isRegistered, !isInitialized else { return }
        guard let context else { return }
        isInitialized = true

        let totalState = Self.signposter.beginInterval("initializeAll")

        for module in modules {
            let name = String(describing: type(of: module))
            let start = CFAbsoluteTimeGetCurrent()

            module.initialize(context: context)

            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if elapsed > 50 {
                Self.logger.warning("⚠️ [\(name)] initialize 耗时 \(String(format: "%.1f", elapsed))ms (>50ms)")
            } else {
                Self.logger.info("[\(name)] initialize: \(String(format: "%.1f", elapsed))ms")
            }
        }

        Self.signposter.endInterval("initializeAll", totalState)
    }

    /// 自动延迟初始化
    ///
    /// 在 registerAll 之后调用，延迟 `initializeDelay` 秒后自动执行 initializeAll。
    public func scheduleInitialization() {
        DispatchQueue.main.asyncAfter(deadline: .now() + initializeDelay) { [weak self] in
            self?.initializeAll()
        }
    }

    // MARK: - Lifecycle: Privacy Mode

    /// 隐私合规模式：仅注册 supportsPrivacyMode=true 的模块
    public func registerPrivacyModules(context: AppContext) {
        guard !isRegistered else { return }
        self.context = context

        modules.sort { type(of: $0).priority > type(of: $1).priority }

        for module in modules where type(of: module).supportsPrivacyMode {
            let name = String(describing: type(of: module))
            module.register(context: context)
            Self.logger.info("[\(name)] privacy register")
        }
    }

    /// 用户同意隐私协议后：注册剩余模块
    public func registerRemainingModules() {
        guard let context else { return }
        isRegistered = true

        for module in modules where !type(of: module).supportsPrivacyMode {
            let name = String(describing: type(of: module))
            module.register(context: context)
            Self.logger.info("[\(name)] register (post-privacy)")
        }
    }

    // MARK: - Events

    /// 向所有模块广播自定义事件
    public func broadcast(_ event: ModuleEvent) {
        for module in modules {
            module.handleEvent(event)
        }
    }

    // MARK: - System Event Forwarding

    /// 开始监听系统事件并转发到所有模块
    ///
    /// ```swift
    /// // AppDelegate.didFinishLaunching:
    /// ModuleManager.shared.startSystemEventForwarding()
    /// ```
    public func startSystemEventForwarding() {
        let nc = NotificationCenter.default

        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.broadcast(ModuleEvent(name: "applicationDidBecomeActive"))
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.broadcast(ModuleEvent(name: "applicationDidEnterBackground"))
        }
        nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tearDownAll()
        }
        nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.broadcast(ModuleEvent(name: "didReceiveMemoryWarning"))
        }
    }

    // MARK: - Lifecycle: Teardown

    /// 清理所有模块（逆序）
    public func tearDownAll() {
        for module in modules.reversed() {
            module.tearDown()
        }
        Self.logger.info("✅ 全部模块已清理")
    }

    // MARK: - Diagnostics

    /// 所有已注册模块的信息
    public var moduleDescriptions: [String] {
        modules.map { module in
            let name = String(describing: type(of: module))
            let priority = type(of: module).priority
            let privacy = type(of: module).supportsPrivacyMode ? " [privacy]" : ""
            return "\(name) (priority: \(priority))\(privacy)"
        }
    }

    /// 重置（仅测试用）
    public func reset() {
        tearDownAll()
        modules.removeAll()
        context = nil
        isRegistered = false
        isInitialized = false
    }
}
