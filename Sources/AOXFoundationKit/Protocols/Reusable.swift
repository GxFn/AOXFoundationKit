import UIKit

// MARK: - Reusable Protocol

public protocol Reusable: AnyObject {
    static var reuseIdentifier: String { get }
}

public extension Reusable {
    static var reuseIdentifier: String { String(describing: self) }
}

extension UITableViewCell: Reusable {}
extension UICollectionReusableView: Reusable {}
extension UITableViewHeaderFooterView: Reusable {}

// MARK: - UITableView Convenience

public extension UITableView {
    func aox_register<T: UITableViewCell>(_ cellType: T.Type) {
        register(cellType, forCellReuseIdentifier: T.reuseIdentifier)
    }

    func aox_dequeueCell<T: UITableViewCell>(_ cellType: T.Type, for indexPath: IndexPath) -> T {
        // swiftlint:disable:next force_cast
        dequeueReusableCell(withIdentifier: T.reuseIdentifier, for: indexPath) as! T
    }
}

// MARK: - UICollectionView Convenience

public extension UICollectionView {
    func aox_register<T: UICollectionViewCell>(_ cellType: T.Type) {
        register(cellType, forCellWithReuseIdentifier: T.reuseIdentifier)
    }

    func aox_dequeueCell<T: UICollectionViewCell>(_ cellType: T.Type, for indexPath: IndexPath) -> T {
        // swiftlint:disable:next force_cast
        dequeueReusableCell(withReuseIdentifier: T.reuseIdentifier, for: indexPath) as! T
    }
}
