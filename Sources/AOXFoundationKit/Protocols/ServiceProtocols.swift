import Foundation

// MARK: - Dependency Container

/// 轻量级依赖注入容器（向后兼容层）
///
/// 内部转发到 `ServiceRegistry.shared`。新代码请直接使用 `ServiceRegistry` 或 `@Injected`。
public enum DIContainer: Sendable {

    /// 注册依赖
    public static func register<T>(_ type: T.Type, factory: @escaping @Sendable () -> T) {
        ServiceRegistry.shared.register(type, scope: .singleton, factory: factory)
    }

    /// 获取依赖
    public static func resolve<T>(_ type: T.Type) -> T {
        ServiceRegistry.shared.resolve(type)
    }

    /// 尝试获取依赖（不存在时返回 nil）
    public static func resolveOptional<T>(_ type: T.Type) -> T? {
        ServiceRegistry.shared.resolveOptional(type)
    }

    /// 清空所有注册（仅用于测试）
    public static func reset() {
        ServiceRegistry.shared.reset()
    }
}
