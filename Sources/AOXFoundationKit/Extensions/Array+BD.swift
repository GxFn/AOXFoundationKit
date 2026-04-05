import Foundation

// MARK: - Array Safe Access

public extension Array {
    /// 安全下标访问，越界返回 nil
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
