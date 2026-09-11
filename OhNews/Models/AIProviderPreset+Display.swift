import OhNewsKit
import SwiftUI

/// 供应商在界面上的名称与说明。文案属于界面层，不放进 OhNewsKit。
extension AIProviderPreset {
    var displayName: String {
        switch self {
        case .deepseek: "DeepSeek"
        case .openai: "OpenAI"
        case .ollama: "Ollama（本地）"
        case .custom: "自定义（OpenAI 兼容）"
        }
    }

    var hint: String {
        switch self {
        case .deepseek: "国内可直连，价格低，中文摘要质量足够。"
        case .openai: "需要能够访问 api.openai.com 的网络环境。"
        case .ollama: "本机运行 ollama serve，模型名按 ollama list 的结果填写。"
        case .custom: "任何兼容 /chat/completions 的服务，例如 OpenRouter、通义、智谱、Kimi。"
        }
    }
}
