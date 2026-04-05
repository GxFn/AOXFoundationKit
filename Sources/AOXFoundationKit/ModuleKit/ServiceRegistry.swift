import Foundation
import os

// MARK: - ServiceScope

/// 服务作用域
public enum ServiceScope: Sendable {
    /// 全局单例：首次 resolve 时创建，后续返回相同实例
    case singleton
    /// 瞬态：每次 resolve 创建新实例
    case transient
}

// MARK: - ServiceRegistry

/// 类型安全的服务注册中心
///
/// 替代 DIContainer，增加 scope 管理、别名、循环依赖检测。
/// 线程安全：内部使用 NSRecursiveLock，支持 resolve 链中嵌套 resolve。
///
/// ```swift
/// // 注册
/// ServiceRegistry.shared.register(NetworkServiceProtocol.self, scope: .singleton) {
///     NetworkServiceImpl()
/// }
///
/// // 获取
/// let service = ServiceRegistry.shared.resolve(NetworkServiceProtocol.self)
///
/// // 属性包装器
/// @Injected var network: NetworkServiceProtocol
/// ```
public final class ServiceRegistry: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = ServiceRegistry()

    // MARK: - Types

    private struct Entry {
        let scope: ServiceScope
        let factory: () -> Any
        var instance: Any?
    }

    // MARK: - Properties

    /// NSRecursiveLock 允许同一线程递归加锁（A resolve B，B 的 factory 又 resolve C）
    private let lock = NSRecursiveLock()

    /// 主注册表: [typeKey → Entry]
    private var entries: [String: Entry] = [:]

    /// 别名表: [aliasKey → primaryKey]
    private var aliases: [String: String] = [:]

    /// 命名注册: [typeKey + "#" + tag → Entry]
    private var taggedEntries: [String: Entry] = [:]

    /// 循环依赖检测（仅 Debug）
    #if DEBUG
    private var resolvingStack: Set<String> = []
    #endif

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AOXModuleKit",
        category: "ServiceRegistry"
    )

    // MARK: - Init

    /// 创建独立实例（用于测试隔离；生产使用 `.shared`）
    public init() {}

    // MARK: - Registration

    /// 注册服务
    ///
    /// - Parameters:
    ///   - type: 服务协议类型
    ///   - scope: 作用域（默认 .singleton）
    ///   - factory: 创建实例的工厂闭包
    ///
    /// 重复注册同一类型时，新注册覆盖旧注册并打印警告。
    public func register<T>(
        _ type: T.Type,
        scope: ServiceScope = .singleton,
        factory: @escaping () -> T
    ) {
        let key = _key(type)
        lock.withLock {
            if entries[key] != nil {
                Self.logger.warning("⚠️ 重复注册 [\(key)]，新注册将覆盖旧注册")
            }
            entries[key] = Entry(scope: scope, factory: factory, instance: nil)
        }
    }

    /// 注册带标签的服务（同一协议多个实现）
    ///
    /// ```swift
    /// registry.register(LoggerProtocol.self, tag: "file") { FileLogger() }
    /// registry.register(LoggerProtocol.self, tag: "console") { ConsoleLogger() }
    /// let logger = registry.resolve(LoggerProtocol.self, tag: "file")
    /// ```
    public func register<T>(
        _ type: T.Type,
        tag: String,
        scope: ServiceScope = .singleton,
        factory: @escaping () -> T
    ) {
        let key = _taggedKey(type, tag: tag)
        lock.withLock {
            taggedEntries[key] = Entry(scope: scope, factory: factory, instance: nil)
        }
    }

    /// 注册别名：让 aliasType 解析到 primaryType 的注册
    ///
    /// ```swift
    /// registry.register(NetworkServiceProtocol.self) { NetworkServiceImpl() }
    /// registry.registerAlias(APIClient.self, for: NetworkServiceProtocol.self)
    /// // resolve(APIClient.self) 返回 NetworkServiceImpl 实例
    /// ```
    public func registerAlias<Alias, Primary>(_ aliasType: Alias.Type, for primaryType: Primary.Type) {
        let aliasKey = _key(aliasType)
        let primaryKey = _key(primaryType)
        lock.withLock {
            aliases[aliasKey] = primaryKey
        }
    }

    /// 直接注册一个现有实例（生命周期由调用方管理）
    public func registerInstance<T>(_ type: T.Type, instance: T) {
        let key = _key(type)
        lock.withLock {
            entries[key] = Entry(scope: .singleton, factory: { instance }, instance: instance)
        }
    }

    // MARK: - Resolution

    /// 获取服务（不存在则 fatalError，仅在开发期暴露注册遗漏）
    public func resolve<T>(_ type: T.Type) -> T {
        guard let service: T = resolveOptional(type) else {
            fatalError("""
            ❌ ServiceRegistry: [\(String(describing: type))] 未注册。
            已注册的服务: \(registeredTypes.joined(separator: ", "))
            """)
        }
        return service
    }

    /// 获取带标签的服务
    public func resolve<T>(_ type: T.Type, tag: String) -> T {
        guard let service: T = resolveOptional(type, tag: tag) else {
            fatalError("❌ ServiceRegistry: [\(String(describing: type))#\(tag)] 未注册")
        }
        return service
    }

    /// 尝试获取服务（不存在返回 nil）
    public func resolveOptional<T>(_ type: T.Type) -> T? {
        let key = _key(type)
        return _resolve(key: key)
    }

    /// 尝试获取带标签的服务
    public func resolveOptional<T>(_ type: T.Type, tag: String) -> T? {
        let key = _taggedKey(type, tag: tag)
        return lock.withLock {
            _resolveEntry(key: key, entries: &taggedEntries)
        }
    }

    // MARK: - Lifecycle

    /// 清空所有注册和缓存（仅用于测试）
    public func reset() {
        lock.withLock {
            entries.removeAll()
            aliases.removeAll()
            taggedEntries.removeAll()
            #if DEBUG
            resolvingStack.removeAll()
            #endif
        }
    }

    /// 释放所有 singleton 缓存（保留注册，下次 resolve 重新创建）
    public func resetSingletons() {
        lock.withLock {
            for key in entries.keys {
                entries[key]?.instance = nil
            }
            for key in taggedEntries.keys {
                taggedEntries[key]?.instance = nil
            }
        }
    }

    // MARK: - Diagnostics

    /// 所有已注册的类型名称
    public var registeredTypes: [String] {
        lock.withLock { Array(entries.keys).sorted() }
    }

    /// 所有已注册的别名
    public var registeredAliases: [(alias: String, primary: String)] {
        lock.withLock { aliases.map { (alias: $0.key, primary: $0.value) }.sorted { $0.alias < $1.alias } }
    }

    /// 检查某类型是否已注册
    public func isRegistered<T>(_ type: T.Type) -> Bool {
        let key = _key(type)
        return lock.withLock {
            let resolvedKey = aliases[key] ?? key
            return entries[resolvedKey] != nil
        }
    }

    // MARK: - Private

    private func _key<T>(_ type: T.Type) -> String {
        String(describing: type)
    }

    private func _taggedKey<T>(_ type: T.Type, tag: String) -> String {
        "\(String(describing: type))#\(tag)"
    }

    private func _resolve<T>(key: String) -> T? {
        lock.withLock {
            // 别名解析
            let resolvedKey = aliases[key] ?? key

            return _resolveEntry(key: resolvedKey, entries: &entries)
        }
    }

    /// 从指定注册表中解析条目
    /// - 调用时 lock 必须已持有
    private func _resolveEntry<T>(key: String, entries: inout [String: Entry]) -> T? {
        guard var entry = entries[key] else { return nil }

        #if DEBUG
        // 循环依赖检测
        if resolvingStack.contains(key) {
            fatalError("""
            ❌ ServiceRegistry 检测到循环依赖!
            解析链: \(resolvingStack.joined(separator: " → ")) → \(key)
            """)
        }
        resolvingStack.insert(key)
        defer { resolvingStack.remove(key) }
        #endif

        switch entry.scope {
        case .singleton:
            if let cached = entry.instance as? T {
                return cached
            }
            let instance = entry.factory()
            entry.instance = instance
            entries[key] = entry
            return instance as? T

        case .transient:
            return entry.factory() as? T
        }
    }
}

// MARK: - @Injected Property Wrapper

/// 属性包装器：声明式服务注入
///
/// ```swift
/// class VideoPlayViewModel {
///     @Injected var repository: VideoRepositoryProtocol
///     @Injected(tag: "file") var logger: LoggerProtocol
/// }
/// ```
///
/// 首次访问 wrappedValue 时才 resolve（懒加载），
/// 如果对应服务尚未注册会触发 fatalError。
@propertyWrapper
public final class Injected<T>: @unchecked Sendable {
    private let tag: String?
    private let registry: ServiceRegistry
    private var cached: T?
    private let lock = NSLock()

    public init(tag: String? = nil, registry: ServiceRegistry = .shared) {
        self.tag = tag
        self.registry = registry
    }

    public var wrappedValue: T {
        lock.withLock {
            if let cached { return cached }
            let value: T
            if let tag {
                value = registry.resolve(T.self, tag: tag)
            } else {
                value = registry.resolve(T.self)
            }
            cached = value
            return value
        }
    }
}
