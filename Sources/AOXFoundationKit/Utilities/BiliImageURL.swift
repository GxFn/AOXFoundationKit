import Foundation

// MARK: - Bilibili Image URL Builder

/// B 站图片 URL 统一处理工具
/// 处理协议修复（http → https）、CDN 缩略图参数拼接
public enum BiliImageURL {

    /// 缩略图尺寸预设
    public enum Thumbnail: String {
        /// 首页卡片封面 480×270
        case cover = "@480w_270h_1c.jpg"
        /// 相关推荐/UP 主投稿列表封面 320×200
        case small = "@320w_200h_1c.jpg"
        /// 头像 68×68
        case avatar = "@68w_68h_1c.jpg"
    }

    /// 修复并构建完整图片 URL
    /// - Parameters:
    ///   - raw: 原始 URL 字符串（可能是 http://、//、https:// 等格式）
    ///   - thumbnail: 可选的缩略图尺寸，仅对 hdslb.com CDN 生效
    /// - Returns: 修复后的 URL，nil 表示输入为空
    public static func build(_ raw: String, thumbnail: Thumbnail? = nil) -> URL? {
        guard !raw.isEmpty else { return nil }

        var urlStr = raw
        // 协议修复
        if urlStr.hasPrefix("http://") {
            urlStr = urlStr.replacingOccurrences(of: "http://", with: "https://")
        } else if !urlStr.hasPrefix("https://") {
            urlStr = "https:" + urlStr
        }

        // CDN 缩略图参数
        if let thumbnail, urlStr.contains("hdslb.com"), !urlStr.contains("@") {
            urlStr += thumbnail.rawValue
        }

        return URL(string: urlStr)
    }
}
