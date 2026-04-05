import Foundation
import CoreTelephony

// MARK: - Network Permission State

/// 网络权限状态
public enum NetworkPermissionState: Int, Sendable {
    case unknown = 0       // 未知（首次安装，未确定）
    case restricted = 1    // 受限（用户拒绝了网络权限）
    case notRestricted = 2 // 未受限（用户允许）
}

// MARK: - Network Permission Manager

/// 网络权限管理器
/// 检测首次安装时的网络权限状态，引导用户授权
public final class NetworkPermissionManager: @unchecked Sendable {

    public static let shared = NetworkPermissionManager()

    private static let firstLaunchKey = "AOXNetworkPermissionFirstLaunchHandled"

    /// 当前网络权限状态
    public private(set) var permissionState: NetworkPermissionState = .unknown

    /// 是否已处理过首次安装的权限请求
    public var hasHandledFirstLaunch: Bool {
        UserDefaults.standard.bool(forKey: Self.firstLaunchKey)
    }

    private let cellularData = CTCellularData()
    private var permissionChangeHandler: (@Sendable (NetworkPermissionState) -> Void)?

    private init() {
        // 设置权限状态变化监听
        cellularData.cellularDataRestrictionDidUpdateNotifier = { [weak self] state in
            guard let self else { return }
            let newState = Self.convert(state)
            self.updateStateIfNeeded(newState)
        }
        // 初始检查
        checkPermission(completion: nil)
    }

    // MARK: - Public

    /// 检查网络权限状态
    public func checkPermission(completion: (@Sendable (NetworkPermissionState) -> Void)?) {
        let state = Self.convert(cellularData.restrictedState)
        updateStateIfNeeded(state)
        completion?(state)
    }

    /// 检查网络权限状态（结合网络可达性）
    /// 如果网络实际可达，即使 restrictedState 显示受限，也认为权限已授权
    public func checkPermissionWithReachability(completion: @escaping @Sendable (NetworkPermissionState) -> Void) {
        let cellularState = Self.convert(cellularData.restrictedState)

        if cellularState == .notRestricted {
            updateStateIfNeeded(cellularState)
            completion(cellularState)
            return
        }

        // CTCellularData 可能延迟更新，检查实际网络状态
        let monitor = NetworkMonitor.shared
        if !monitor.isMonitoring {
            monitor.startMonitoring()
        }

        if monitor.isReachable {
            let finalState: NetworkPermissionState = .notRestricted
            updateStateIfNeeded(finalState)
            completion(finalState)
        } else {
            // 延迟 0.3s 再检查一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                let finalState: NetworkPermissionState = monitor.isReachable ? .notRestricted : cellularState
                self.updateStateIfNeeded(finalState)
                completion(finalState)
            }
        }
    }

    /// 处理首次安装的网络权限请求
    public func handleFirstLaunchPermission(completion: @escaping @Sendable (_ shouldShowAlert: Bool) -> Void) {
        guard !hasHandledFirstLaunch else {
            completion(false)
            return
        }

        checkPermissionWithReachability { state in
            let shouldShow = (state == .unknown || state == .restricted)
            completion(shouldShow)
        }
    }

    /// 标记已处理过首次安装
    public func markFirstLaunchHandled() {
        UserDefaults.standard.set(true, forKey: Self.firstLaunchKey)
    }

    /// 监听权限状态变化
    public func observePermissionStateChange(_ handler: @escaping @Sendable (NetworkPermissionState) -> Void) {
        self.permissionChangeHandler = handler
    }

    // MARK: - Private

    private func updateStateIfNeeded(_ newState: NetworkPermissionState) {
        guard permissionState != newState else { return }
        permissionState = newState
        permissionChangeHandler?(newState)
    }

    private static func convert(_ state: CTCellularDataRestrictedState) -> NetworkPermissionState {
        switch state {
        case .restrictedStateUnknown: return .unknown
        case .restricted: return .restricted
        case .notRestricted: return .notRestricted
        @unknown default: return .unknown
        }
    }
}
