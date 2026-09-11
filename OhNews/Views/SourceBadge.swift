import OhNewsKit
import SwiftUI

/// 来源徽标。
///
/// 用 host 的首字母生成一个本地浮雕方块，**不请求任何远程 favicon 服务**——
/// 这与 OhNews「100% 本地处理、不联网读取图片内容」的定位一致。
///
/// 取色走 FNV-1a 稳定哈希：不能用 Swift 的 `hashValue`，它每次启动都会重新加盐，
/// 会导致同一个 host 每次打开应用换个颜色。
struct SourceBadge: View {
    let host: String?

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.badgeCornerRadius, style: .continuous)
            .fill(background)
            .frame(width: Metrics.badgeSize, height: Metrics.badgeSize)
            .overlay { content }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let initial {
            Text(initial)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))
        } else {
            // 自述帖没有外链站点，用中性的文档图标，而不是空白方块。
            Image(systemName: "text.alignleft")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var background: Color {
        guard let host, host.isEmpty == false else { return Palette.raisedSurface }
        return Self.tints[Self.bucket(for: host)]
    }

    private var initial: String? {
        guard let host, let character = host.first(where: \.isLetter) else { return nil }
        return String(character).uppercased()
    }

    /// 低饱和度的一组底色，在深色卡片与白色卡片上都有足够对比。
    private static let tints: [Color] = [
        Color(red: 0.27, green: 0.41, blue: 0.66),
        Color(red: 0.18, green: 0.56, blue: 0.53),
        Color(red: 0.66, green: 0.46, blue: 0.23),
        Color(red: 0.66, green: 0.33, blue: 0.40),
        Color(red: 0.35, green: 0.37, blue: 0.66),
        Color(red: 0.29, green: 0.49, blue: 0.27),
    ]

    private static func bucket(for host: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in host.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(tints.count))
    }
}
