import Foundation

// MARK: - Dictionary Safe Access

public extension Dictionary where Key == String {
    /// 安全取字符串值
    func aox_string(forKey key: String) -> String? {
        guard let value = self[key] else { return nil }
        if let str = value as? String { return str }
        return "\(value)"
    }

    /// 安全取 Int 值
    func aox_int(forKey key: String) -> Int? {
        guard let value = self[key] else { return nil }
        if let num = value as? Int { return num }
        if let str = value as? String { return Int(str) }
        return nil
    }
}
