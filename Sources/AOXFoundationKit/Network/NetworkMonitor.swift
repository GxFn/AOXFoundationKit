import Foundation
import Network
import UIKit
import OSLog
import Combine

// MARK: - Network Status

/// 网络状态枚举
public enum NetworkStatus: Int, Sendable {
    case unknown = -1
    case notReachable = 0
    case wifi = 1
    case cellular = 2

    public var isReachable: Bool {
        self == .wifi || self == .cellular
    }

    public var isWiFi: Bool {
        self == .wifi
    }

    public var isCellular: Bool {
        self == .cellular
    }

    /// 蜂窝网络视为昂贵网络
    public var isExpensive: Bool {
        self == .cellular
    }

    public var localizedDescription: String {
        switch self {
        case .unknown: return "未知"
        case .notReachable: return "无网络"
        case .wifi: return "WiFi"
        case .cellular: return "蜂窝网络"
        }
    }
}

// MARK: - Network Monitor

/// `NWPathMonitor` 单次运行周期的代次状态。
///
/// 该类型不持有系统对象，便于单元测试 start/stop 乱序下的失效语义；真实 monitor 实例仍由
/// `NetworkMonitor.statusLock` 与本状态放在同一同步域内管理。
struct NetworkMonitorLifecycleState: Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var isMonitoring = false

    /// 开始一个新周期。重复 start 不创建新代次。
    mutating func beginMonitoring() -> UInt64? {
        guard !isMonitoring else { return nil }
        generation &+= 1
        isMonitoring = true
        return generation
    }

    /// 结束当前周期并立即推进代次，使已经排队的旧回调失效。
    @discardableResult
    mutating func endMonitoring() -> UInt64? {
        guard isMonitoring else { return nil }
        isMonitoring = false
        generation &+= 1
        return generation
    }

    func acceptsCallback(generation callbackGeneration: UInt64) -> Bool {
        isMonitoring && generation == callbackGeneration
    }
}

/// 网络状态监测器
/// 使用 NWPathMonitor 实现（iOS 12+ 原生 API，替代 SCNetworkReachability）
public final class NetworkMonitor: @unchecked Sendable {

    public static let shared = NetworkMonitor()

    /// 网络状态变化通知
    public static let statusDidChangeNotification = Notification.Name("AOXNetworkStatusDidChangeNotification")

    /// 当前网络状态
    private var _currentStatus: NetworkStatus = .unknown
    private var _isExpensiveConnection = false
    private var _isConstrainedConnection = false
    private let statusLock = NSLock()

    public var currentStatus: NetworkStatus {
        get {
            statusLock.withLock { _currentStatus }
        }
        set {
            statusLock.withLock { _currentStatus = newValue }
        }
    }

    /// 当前路径是否昂贵（蜂窝、热点或系统判定的昂贵链路）。
    public var isExpensiveConnection: Bool {
        statusLock.withLock { _isExpensiveConnection }
    }

    /// 当前路径是否处于 Low Data Mode 等受限状态。
    public var isConstrainedConnection: Bool {
        statusLock.withLock { _isConstrainedConnection }
    }

    /// monitor 生命周期、路径状态和 monitor 引用必须由同一把锁保护。
    /// generation 用于拒绝 cancel 前已经排进 monitorQueue / main queue 的迟到回调。
    private var lifecycle = NetworkMonitorLifecycleState()
    public var isMonitoring: Bool {
        statusLock.withLock { lifecycle.isMonitoring }
    }

    // NWPathMonitor 一旦 cancel() 就不能再 start()（Apple 要求 cancel 后新建实例），
    // 因此不能用 let 复用同一实例，需在每次 startMonitoring 时重建。
    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.aoxkit.network.monitor")
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // 监听前后台切换（使用 Combine 替代 @objc + #selector）
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.stopMonitoring() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.startMonitoring() }
            .store(in: &cancellables)
    }

    deinit {
        stopMonitoring()
        cancellables.removeAll()
    }

    // MARK: - Public

    public func startMonitoring() {
        let startedGeneration: UInt64? = statusLock.withLock {
            guard let generation = lifecycle.beginMonitoring() else { return nil }

            // 创建、发布、start 必须处在同一个同步域：否则 stop 可能在发布后、真正 start 前取消
            // monitor，而旧 start 随后才执行。NWPathMonitor 的回调始终异步投递到 monitorQueue，
            // 因此锁内 start 不会同步重入 statusLock。
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                self?.handlePathUpdate(path, generation: generation)
            }
            self.monitor = monitor
            monitor.start(queue: monitorQueue)
            return generation
        }
        guard let startedGeneration else {
            FoundationLogger.network.debug("网络监测已经运行，忽略重复 start")
            return
        }

        FoundationLogger.network.debug("开始监测网络状态: generation=\(startedGeneration)")
    }

    public func stopMonitoring() {
        let stopContext: (monitor: NWPathMonitor?, invalidatedGeneration: UInt64)? = statusLock.withLock {
            guard let invalidatedGeneration = lifecycle.endMonitoring() else { return nil }
            let monitorToCancel = monitor
            monitor = nil
            return (monitorToCancel, invalidatedGeneration)
        }
        guard let stopContext else {
            FoundationLogger.network.debug("网络监测未运行，忽略重复 stop")
            return
        }

        // 锁外 cancel，避免系统实现同步触发回调时与 statusLock 形成重入；generation 已先在锁内失效。
        stopContext.monitor?.cancel()
        FoundationLogger.network.debug("停止监测网络状态: generation=\(stopContext.invalidatedGeneration)")
    }

    // MARK: - Path Updates

    private enum PathUpdateDecision {
        case accepted(oldStatus: NetworkStatus, oldExpensive: Bool, oldConstrained: Bool)
        case stale(activeGeneration: UInt64, isMonitoring: Bool)
    }

    private func handlePathUpdate(_ path: NWPath, generation: UInt64) {
        let newStatus: NetworkStatus
        if path.status == .satisfied {
            if path.usesInterfaceType(.wifi) {
                newStatus = .wifi
            } else if path.usesInterfaceType(.cellular) {
                newStatus = .cellular
            } else {
                newStatus = .wifi // 默认有线/其他走 wifi
            }
        } else {
            newStatus = .notReachable
        }

        // 不把 NWPath 跨队列捕获；只传递 Sendable 的值快照。
        let newExpensive = path.isExpensive
        let newConstrained = path.isConstrained
        let decision: PathUpdateDecision = statusLock.withLock {
            guard lifecycle.acceptsCallback(generation: generation) else {
                return .stale(
                    activeGeneration: lifecycle.generation,
                    isMonitoring: lifecycle.isMonitoring
                )
            }

            let old = (_currentStatus, _isExpensiveConnection, _isConstrainedConnection)
            _currentStatus = newStatus
            _isExpensiveConnection = newExpensive
            _isConstrainedConnection = newConstrained
            return .accepted(
                oldStatus: old.0,
                oldExpensive: old.1,
                oldConstrained: old.2
            )
        }

        guard case let .accepted(oldStatus, oldExpensive, oldConstrained) = decision else {
            if case let .stale(activeGeneration, isMonitoring) = decision {
                FoundationLogger.network.debug("忽略过期网络路径回调: callbackGeneration=\(generation), activeGeneration=\(activeGeneration), monitoring=\(isMonitoring)")
            }
            return
        }

        // Low Data Mode / 昂贵链路可能在接口类型不变时切换，仍必须通知预取和下载策略层。
        guard oldStatus != newStatus || oldExpensive != newExpensive || oldConstrained != newConstrained else {
            return
        }

        FoundationLogger.network.info("网络路径变化: status=\(oldStatus.localizedDescription)->\(newStatus.localizedDescription), expensive=\(oldExpensive)->\(newExpensive), constrained=\(oldConstrained)->\(newConstrained), generation=\(generation)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let isCurrent = self.statusLock.withLock {
                self.lifecycle.acceptsCallback(generation: generation)
            }
            guard isCurrent else {
                FoundationLogger.network.debug("通知投递前 generation 已失效，跳过旧网络状态通知: generation=\(generation)")
                return
            }

            NotificationCenter.default.post(
                name: NetworkMonitor.statusDidChangeNotification,
                object: self,
                userInfo: [
                    "currentStatus": newStatus.rawValue,
                    "oldStatus": oldStatus.rawValue,
                    "isReachable": newStatus.isReachable,
                    "isWiFi": newStatus.isWiFi,
                    "isCellular": newStatus.isCellular,
                    "isExpensive": newExpensive,
                    "isConstrained": newConstrained,
                ]
            )
        }
    }

    // MARK: - Convenience

    public var isReachable: Bool { currentStatus.isReachable }
    public var isReachableViaWiFi: Bool { currentStatus.isWiFi }
    public var isReachableViaCellular: Bool { currentStatus.isCellular }
}
