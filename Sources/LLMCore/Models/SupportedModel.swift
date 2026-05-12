//
//  SupportedModel.swift
//  LLMServer
//
//  Created by Chocoford on 9/4/25.
//

import Foundation
import OpenAI

public enum SupportedModel: ContentModel {
    // --- OpenAI 系 ---
    case gpt5_5
    case gpt5_4
    case gpt4o
    case gpt4oMini
    case gpt4oLatest
    case gpt35Turbo

    // --- Anthropic 系 ---
    case claudeOpus4_7
    case claudeOpus4_6
    case claudeSonnet4_6
    case claudeHaiku4_5

    // --- Mistral 系 ---
    case mistral7b
    case mixtral8x7b

    // --- Google Gemini 系 ---
    case gemini15Pro
    case gemini15Flash

    // --- Image ---
    case nanoBananaFree
    case nanoBanana
    case nanoBanana2

    // --- Minimax ---
    case minimaxM2_7
    case minimaxM2_5
    case minimaxM2

    // --- Kimi ---
    case kimiK2_6

    // --- Qwen ---
    case qwen3_6Plus

    // --- Tenent ---
    case hy3Preview

    // --- Xiaomi ---
    case mimoV2_5Pro

    case other(String)

    public var rawValue: String {
        switch self {
            case .gpt5_5: return "openai/gpt-5.5"
            case .gpt5_4: return "openai/gpt-5.4"
            case .gpt4o: return "openai/gpt-4o"
            case .gpt4oMini: return "openai/gpt-4o-mini"
            case .gpt4oLatest: return "openai/gpt-4o-latest"
            case .gpt35Turbo: return "openai/gpt-3.5-turbo"
            case .claudeOpus4_7: return "anthropic/claude-opus-4.7"
            case .claudeOpus4_6: return "anthropic/claude-opus-4.6"
            case .claudeSonnet4_6: return "anthropic/claude-sonnet-4.6"
            case .claudeHaiku4_5: return "anthropic/claude-haiku-4.5"
            case .mistral7b: return "mistral-7b-instruct"
            case .mixtral8x7b: return "mixtral-8x7b-instruct"
            case .gemini15Pro: return "gemini-1.5-pro"
            case .gemini15Flash: return "gemini-1.5-flash"
            case .nanoBananaFree: return "google/gemini-2.5-flash-image-preview:free"
            case .nanoBanana: return "google/gemini-2.5-flash-image-preview"
            case .nanoBanana2: return "google/gemini-3.1-flash-image-preview"
            case .minimaxM2_7: return "minimax/minimax-m2.7"
            case .minimaxM2_5: return "minimax/minimax-m2.5"
            case .minimaxM2: return "minimax/minimax-m2"
            case .kimiK2_6: return "moonshotai/kimi-k2.6"
            case .qwen3_6Plus: return "qwen/qwen3.6-plus"
            case .hy3Preview: return "tencent/hy3-preview"
            case .mimoV2_5Pro: return "xiaomi/mimo-v2.5-pro"
            case .other(let value): return value
        }
    }

    /// 转换成 MacPaw OpenAI SDK 的 `Model`
    public var asOpenAIModel: Model { self.rawValue }

    public init(rawValue: String) {
        switch rawValue {
            case "openai/gpt-5.5": self = .gpt5_5
            case "openai/gpt-5.4": self = .gpt5_4
            case "openai/gpt-4o": self = .gpt4o
            case "openai/gpt-4o-mini": self = .gpt4oMini
            case "openai/gpt-4o-latest": self = .gpt4oLatest
            case "openai/gpt-3.5-turbo": self = .gpt35Turbo
            case "anthropic/claude-opus-4.7": self = .claudeOpus4_7
            case "anthropic/claude-opus-4.6": self = .claudeOpus4_6
            case "anthropic/claude-sonnet-4.6": self = .claudeSonnet4_6
            case "anthropic/claude-haiku-4.5": self = .claudeHaiku4_5
            case "mistral-7b-instruct": self = .mistral7b
            case "mixtral-8x7b-instruct": self = .mixtral8x7b
            case "gemini-1.5-pro": self = .gemini15Pro
            case "gemini-1.5-flash": self = .gemini15Flash
            case "google/gemini-2.5-flash-image-preview:free": self = .nanoBananaFree
            case "google/gemini-2.5-flash-image-preview": self = .nanoBanana
            case "google/gemini-3.1-flash-image-preview": self = .nanoBanana2
            case "minimax/minimax-m2.7": self = .minimaxM2_7
            case "minimax/minimax-m2.5": self = .minimaxM2_5
            case "minimax/minimax-m2": self = .minimaxM2
            case "moonshotai/kimi-k2.6": self = .kimiK2_6
            case "qwen/qwen3.6-plus": self = .qwen3_6Plus
            case "tencent/hy3-preview": self = .hy3Preview
            case "xiaomi/mimo-v2.5-pro": self = .mimoV2_5Pro
            default: self = .other(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        self.init(rawValue: rawValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }

    public var supportsStreaming: Bool {
        switch self {
        default:
            return true
        }
    }

    /// 模型是否接受图像输入 (消息里夹带 image 类型的 content/file 给它看)。
    ///
    /// 用法:
    /// - 客户端模型选择器: 加 badge / 过滤
    /// - send 按钮: 用户附了图 + 当前模型不支持 → 禁用或换模型提示
    /// - 跟 `prepareUploadFiles` 链路对应, 不支持的模型走纯文本路径
    ///
    /// 注: 这只表达 image **输入** 能力。"输出图像"(image generation) 跟这个不同, 由专门的模型类别
    /// 处理 (例如 nanoBanana 系列既能输入也能生成, 这里仍标 true 因为它确实接受 image input)。
    public var supportsImageInput: Bool {
        switch self {
            // --- OpenAI ---
            case .gpt5_5, .gpt5_4, .gpt4o, .gpt4oMini, .gpt4oLatest:
                return true
            case .gpt35Turbo:
                return false

            // --- Anthropic ---
            case .claudeOpus4_7, .claudeOpus4_6, .claudeSonnet4_6, .claudeHaiku4_5:
                return true

            // --- Mistral (纯文本) ---
            case .mistral7b, .mixtral8x7b:
                return false

            // --- Gemini ---
            case .gemini15Pro, .gemini15Flash:
                return true

            // --- nanoBanana 系列 (image-in-out) ---
            case .nanoBananaFree, .nanoBanana, .nanoBanana2:
                return true

            // --- Minimax (不确定, 先 true 方便测试; 实测确认后再 toggle) ---
            case .minimaxM2_7, .minimaxM2_5, .minimaxM2:
                return true

            // --- Kimi ---
            case .kimiK2_6:
                return true

            // --- Qwen (不确定, 先 true 方便测试; 非 -VL 变体可能不支持) ---
            case .qwen3_6Plus:
                return true

            // --- Tenent ---
            case .hy3Preview:
                return false

            // --- XiaoMi ---
            case .mimoV2_5Pro:
                return true

            // --- 未知模型 ---
            // 上游对图像输入的拒绝是硬错误 (400), 误开比误关风险大, 默认 false。
            // 用户用自定义 model 又需要 vision, 自己包一层 wrap 重写这个属性即可。
            case .other:
                return false
        }
    }
}

// MARK: - UI Helper Extensions
extension SupportedModel {
    /// 显示名称
    public var displayName: String {
        switch self {
            case .gpt5_5: return "GPT-5.5"
            case .gpt5_4: return "GPT-5.4"
            case .gpt4o: return "GPT-4o"
            case .gpt4oMini: return "GPT-4o Mini"
            case .gpt4oLatest: return "GPT-4o Latest"
            case .gpt35Turbo: return "GPT-3.5 Turbo"
            case .claudeOpus4_7: return "Claude Opus 4.7"
            case .claudeOpus4_6: return "Claude Opus 4.6"
            case .claudeSonnet4_6: return "Claude Sonnet 4.6"
            case .claudeHaiku4_5: return "Claude Haiku 4.5"
            case .mistral7b: return "Mistral 7B"
            case .mixtral8x7b: return "Mixtral 8x7B"
            case .gemini15Pro: return "Gemini 1.5 Pro"
            case .gemini15Flash: return "Gemini 1.5 Flash"
            case .nanoBananaFree: return "Nano Banana (Free)"
            case .nanoBanana: return "Nano Banana"
            case .nanoBanana2: return "Nano Banana 2"
            case .minimaxM2_7: return "Minimax-M2.7" 
            case .minimaxM2_5: return "Minimax-M2.5"
            case .minimaxM2: return "Minimax-M2"
            case .kimiK2_6: return "Kimi K2.6"
            case .qwen3_6Plus: return "Qwen3.6 Plus"
            case .hy3Preview: return "HY3 Preview"
            case .mimoV2_5Pro: return "MIMO v2.5 Pro"

            case .other(let value): return value
        }
    }

    /// 模型提供商
    public var provider: String {
        switch self {
            case .gpt5_5, .gpt5_4, .gpt4o, .gpt4oMini, .gpt4oLatest, .gpt35Turbo:
                return "OpenAI"
            case .claudeOpus4_7, .claudeOpus4_6, .claudeSonnet4_6, .claudeHaiku4_5:
                return "Anthropic"
            case .mistral7b, .mixtral8x7b:
                return "Mistral"
            case .gemini15Pro, .gemini15Flash, .nanoBananaFree, .nanoBanana, .nanoBanana2:
                return "Google"
            case .minimaxM2_7, .minimaxM2_5, .minimaxM2:
                return "Minimax"
            case .kimiK2_6:
                return "MoonshotAI"
            case .qwen3_6Plus:
                return "Qwen"
            case .hy3Preview:
                return "Tencent"
            case .mimoV2_5Pro:
                return "Xiaomi"
            case .other:
                return "Other"
        }
    }

    /// 是否为图像模型
    public var isImageModel: Bool {
        switch self {
            case .nanoBananaFree, .nanoBanana, .nanoBanana2:
                return true
            default:
                return false
        }
    }

    public static var allChatModels: [SupportedModel] {
        return [
            .gpt5_5, .gpt5_4, .gpt4oMini, .gpt4o, .gpt4oLatest, .gpt35Turbo,
            .claudeHaiku4_5, .claudeOpus4_6, .claudeOpus4_7, .claudeSonnet4_6,
            .gemini15Flash, .gemini15Pro,
            .mistral7b, .mixtral8x7b,
            .minimaxM2_7, .minimaxM2_5, .minimaxM2,
            .kimiK2_6,
            .qwen3_6Plus,
            .hy3Preview,
            .mimoV2_5Pro,
            // Image models (也算聊天模型, 因为它们支持 vision 输入):
            .nanoBanana, .nanoBananaFree, .nanoBanana2,
        ]
    }

    /// 按提供商分组的聊天模型
    public static var chatModelsByProvider: [String: [SupportedModel]] {
        return Dictionary(grouping: allChatModels) { $0.provider }
    }
}
