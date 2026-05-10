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
            // Image models (也算聊天模型, 因为它们支持 vision 输入):
            .nanoBanana, .nanoBananaFree, .nanoBanana2,
        ]
    }

    /// 按提供商分组的聊天模型
    public static var chatModelsByProvider: [String: [SupportedModel]] {
        return Dictionary(grouping: allChatModels) { $0.provider }
    }
}
