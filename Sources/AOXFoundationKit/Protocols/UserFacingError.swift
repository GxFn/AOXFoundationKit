import Foundation

// MARK: - User Facing Error

/// 可展示给用户的错误协议
/// 各模块的 Error 类型遵循此协议，提供用户友好的错误文案
public protocol UserFacingError: Error {
    /// 用户可读的错误消息（非技术性描述）
    var userMessage: String { get }
}

// MARK: - Error Extension

extension Error {
    /// 获取用户可读的错误消息
    /// 优先使用 UserFacingError.userMessage，否则降级使用 localizedDescription
    public var userFacingMessage: String {
        (self as? UserFacingError)?.userMessage ?? self.localizedDescription
    }
}
