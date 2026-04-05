import Foundation

// MARK: - String Utilities

public extension String {
    /// 安全判空（nil 和空字符串均返回 true）
    var aox_isEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// URL 参数编码
    var aox_urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

public extension Optional where Wrapped == String {
    /// 可选字符串安全判空
    var aox_isEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let value): return value.aox_isEmpty
        }
    }
}
