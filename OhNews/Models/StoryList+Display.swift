import OhNewsKit
import SwiftUI

/// 榜单在界面上的文案与图标。文案属于界面层，因此不放进 OhNewsKit。
extension StoryList {
    var displayName: String {
        switch self {
        case .top: "首页"
        case .best: "最佳"
        case .new: "最新"
        case .ask: "提问"
        case .show: "展示"
        }
    }

    var systemImage: String {
        switch self {
        case .top: "flame"
        case .best: "star"
        case .new: "clock"
        case .ask: "questionmark.bubble"
        case .show: "sparkles"
        }
    }
}
