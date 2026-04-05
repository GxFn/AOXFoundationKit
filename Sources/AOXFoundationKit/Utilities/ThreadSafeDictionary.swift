import Foundation

// MARK: - Thread-Safe Dictionary

/// 线程安全的字典封装，使用并发队列 + barrier 实现读写分离
public final class ThreadSafeDictionary<Key: Hashable, Value>: @unchecked Sendable {

    private var storage: [Key: Value] = [:]
    private let queue: DispatchQueue

    public init(label: String = "com.bilidili.threadsafe-dict") {
        self.queue = DispatchQueue(label: label, attributes: .concurrent)
    }

    /// 读取值
    public subscript(key: Key) -> Value? {
        get {
            queue.sync { storage[key] }
        }
        set {
            queue.async(flags: .barrier) { [weak self] in
                self?.storage[key] = newValue
            }
        }
    }

    /// 同步读取值
    public func value(forKey key: Key) -> Value? {
        queue.sync { storage[key] }
    }

    /// 写入值
    public func setValue(_ value: Value?, forKey key: Key) {
        queue.async(flags: .barrier) { [weak self] in
            self?.storage[key] = value
        }
    }

    /// 移除值并返回
    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        queue.sync(flags: .barrier) { storage.removeValue(forKey: key) }
    }

    /// 移除所有值
    public func removeAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.storage.removeAll()
        }
    }

    /// 当前元素数量
    public var count: Int {
        queue.sync { storage.count }
    }

    /// 所有键
    public var keys: [Key] {
        queue.sync { Array(storage.keys) }
    }

    /// 所有值
    public var values: [Value] {
        queue.sync { Array(storage.values) }
    }

    /// 是否包含指定键
    public func contains(_ key: Key) -> Bool {
        queue.sync { storage[key] != nil }
    }

    /// 原子性地获取或插入默认值
    public func getOrInsert(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        queue.sync(flags: .barrier) {
            if let existing = storage[key] { return existing }
            let value = defaultValue()
            storage[key] = value
            return value
        }
    }
}
