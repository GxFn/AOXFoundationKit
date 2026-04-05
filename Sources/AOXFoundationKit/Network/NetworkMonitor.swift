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

/// 网络状态监测器
/// 使用 NWPathMonitor 实现（iOS 12+ 原生 API，替代 SCNetworkReachability）
public final class NetworkMonitor: @unchecked Sendable {

    public static let shared = NetworkMonitor()

    /// 网络状态变化通知
    public static let statusDidChangeNotification = Notification.Name("AOXNetworkStatusDidChangeNotification")

    /// 当前网络状态
    private var _currentStatus: NetworkStatus = .unknown
    private let statusLock = NSLock()

    public var currentStatus: NetworkStatus {
        get {
            statusLock.withLock { _currentStatus }
        }
        set {
            statusLock.withLock { _currentStatus = newValue }
        }
    }

    /// 是否正在监测
    private var _isMonitoring = false
    public var isMonitoring: Bool {
        statusLock.withLock { _isMonitoring }
    }

    private let monitor = NWPathMonitor()
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
        let shouldStart = statusLock.withLock { () -> Bool in
            guard !_isMonitoring else { return false }
            _isMonitoring = true
            return true
        }
        guard shouldStart else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let oldStatus = self.currentStatus
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

            self.currentStatus = newStatus

            if oldStatus != newStatus {
                FoundationLogger.network.info("网络状态变化: \(oldStatus.localizedDescription) -> \(newStatus.localizedDescription)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NetworkMonitor.statusDidChangeNotification,
                        object: self,
                        userInfo: [
                            "currentStatus": newStatus.rawValue,
                            "oldStatus": oldStatus.rawValue,
                            "isReachable": newStatus.isReachable,
                            "isWiFi": newStatus.isWiFi,
                            "isCellular": newStatus.isCellular,
                            "isExpensive": path.isExpensive,
                            "isConstrained": path.isConstrained,
                        ]
                    )
                }
            }
        }

        monitor.start(queue: monitorQueue)
        FoundationLogger.network.debug("开始监测网络状态")
    }

    public func stopMonitoring() {
        let shouldStop = statusLock.withLock { () -> Bool in
            guard _isMonitoring else { return false }
            _isMonitoring = false
            return true
        }
        guard shouldStop else { return }
        monitor.cancel()
        FoundationLogger.network.debug("停止监测网络状态")
    }

    // MARK: - Convenience

    public var isReachable: Bool { currentStatus.isReachable }
    public var isReachableViaWiFi: Bool { currentStatus.isWiFi }
    public var isReachableViaCellular: Bool { currentStatus.isCellular }
}
