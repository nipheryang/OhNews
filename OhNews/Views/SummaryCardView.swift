import OhNewsKit
import SwiftUI

/// 列表行内的 AI 摘要。
///
/// 摘要是一层「阅读辅助」，不是第二张卡片：没有独立底色，只用一道极细的
/// 强调线和缩进与标题区分。背景色一旦加上去，一条新闻就会被切成两个视觉单元。
struct SummaryBlockView: View {
    let summary: StorySummary

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.summaryIndent) {
            Capsule()
                .fill(Palette.aiAccent.opacity(0.3))
                .frame(width: Metrics.summaryRuleWidth)

            VStack(alignment: .leading, spacing: 4) {
                // AI 中文标题是辅助标题：原文标题必须是整行唯一的最高层级，
                // 所以这里降为次级文字，靠字重而不是亮度来区分正文。
                Text(summary.chineseTitle)
                    .font(Typography.summaryTitle)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // 摘要不设上限时，一条长摘要能把行高撑到相邻行的两三倍，
                // 列表的扫描节奏就没了。截断到 4 行，完整内容留给后续的阅读区。
                Text(summary.summary)
                    .font(Typography.summaryBody)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(Typography.summaryBodyLineSpacing)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let consensus = summary.commentConsensus {
                    Label(consensus, systemImage: "bubble.left.and.bubble.right")
                        .font(Typography.summaryFootnote)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if summary.tags.isEmpty == false {
                    HStack(spacing: 6) {
                        ForEach(summary.tags, id: \.self) { tag in
                            Text(tag)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.aiAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(
                                    Palette.aiAccent.opacity(0.12),
                                    in: RoundedRectangle(
                                        cornerRadius: Metrics.tagCornerRadius,
                                        style: .continuous
                                    )
                                )
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.top, 8)
    }
}

/// 摘要生成中的占位。
///
/// 用与摘要同宽的两条灰条，而不是「转圈 + 文字」：生成完成时文字直接替换占位，
/// 行的几何形状不变，列表不会因此跳动。
struct SummarySkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.summaryIndent) {
            Capsule()
                .fill(Palette.aiAccent.opacity(0.2))
                .frame(width: Metrics.summaryRuleWidth)

            VStack(alignment: .leading, spacing: 7) {
                bar(trailingInset: 200)
                bar(trailingInset: 40)
            }
        }
        .padding(.top, 8)
        .opacity(reduceMotion ? 0.7 : (isDimmed ? 0.55 : 1))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
            value: isDimmed
        )
        .onAppear { if reduceMotion == false { isDimmed = true } }
        .accessibilityLabel("正在生成摘要")
    }

    private func bar(trailingInset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Palette.textTertiary.opacity(0.28))
            .frame(height: 9)
            .padding(.trailing, trailingInset)
    }
}

/// AI 不可用时的提示条。整个列表只显示一条，不逐行重复。
///
/// 用「抬起表面」表达这是一条状态提示，语义上与摘要彻底分开——
/// 之前两者共用同一个 `.quaternary` 底色，含义就糊在一起了。
struct AIUnavailableBanner: View {
    let title: String
    let message: String
    /// 一次性问题（比如某次请求失败）可以关掉；配置类问题传 nil。
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Palette.aiAccent.opacity(0.8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text(message)
                    .font(Typography.summaryFootnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let onDismiss {
                Button(action: onDismiss) {
                    Label("关闭", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.textSecondary)
                .help("关闭提示")
            }

            SettingsLink {
                Text("去设置")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Palette.raisedSurface,
            in: RoundedRectangle(cornerRadius: Metrics.bannerCornerRadius, style: .continuous)
        )
        .padding(.horizontal, Metrics.listHorizontalInset)
        .padding(.top, 8)
    }
}
