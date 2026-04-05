import UIKit

// MARK: - Screen Utilities

@MainActor
public enum Screen {
    public static var width: CGFloat { UIScreen.main.bounds.width }
    public static var height: CGFloat { UIScreen.main.bounds.height }
    public static var scale: CGFloat { UIScreen.main.scale }
    public static var safeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets ?? .zero
    }
    public static var statusBarHeight: CGFloat { safeAreaInsets.top }
    public static var bottomSafeHeight: CGFloat { safeAreaInsets.bottom }
    public static var navigationBarHeight: CGFloat { 44 + statusBarHeight }
    public static var tabBarHeight: CGFloat { 49 + bottomSafeHeight }
}
