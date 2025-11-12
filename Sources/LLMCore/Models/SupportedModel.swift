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
    case gpt4o
    case gpt4oMini
    case gpt4oLatest
    case gpt35Turbo

    // --- Anthropic 系 ---
    case claudeSonnet
    case claudeHaiku

    // --- Mistral 系 ---
    case mistral7b
    case mixtral8x7b

    // --- Google Gemini 系 ---
    case gemini15Pro
    case gemini15Flash
    
    
    // --- Image ---
    case nanoBananaFree
    case nanoBanana
    
    // --- Non-OpenRouter Models ---
    case minimaxM2
    
    case other(String)
    
    public var rawValue: String {
        switch self {
            case .gpt4o: return "openai/gpt-4o"
            case .gpt4oMini: return "openai/gpt-4o-mini"
            case .gpt4oLatest: return "openai/gpt-4o-latest"
            case .gpt35Turbo: return "openai/gpt-3.5-turbo"
            case .claudeSonnet: return "claude-3.5-sonnet"
            case .claudeHaiku: return "claude-3.5-haiku"
            case .mistral7b: return "mistral-7b-instruct"
            case .mixtral8x7b: return "mixtral-8x7b-instruct"
            case .gemini15Pro: return "gemini-1.5-pro"
            case .gemini15Flash: return "gemini-1.5-flash"
            case .nanoBananaFree: return "google/gemini-2.5-flash-image-preview:free"
            case .nanoBanana: return "google/gemini-2.5-flash-image-preview"
                
            case .minimaxM2: return "minimax/minimax-m2"
            case .other(let value): return value
        }
    }
    
    /// 转换成 MacPaw OpenAI SDK 的 `Model`
    public var asOpenAIModel: Model { self.rawValue }
    
    public init(rawValue: String) {
        switch rawValue {
            case "openai/gpt-4o": self = .gpt4o
            case "openai/gpt-4o-mini": self = .gpt4oMini
            case "openai/gpt-4o-latest": self = .gpt4oLatest
            case "openai/gpt-3.5-turbo": self = .gpt35Turbo
            case "claude-3.5-sonnet": self = .claudeSonnet
            case "claude-3.5-haiku": self = .claudeHaiku
            case "mistral-7b-instruct": self = .mistral7b
            case "mixtral-8x7b-instruct": self = .mixtral8x7b
            case "gemini-1.5-pro": self = .gemini15Pro
            case "gemini-1.5-flash": self = .gemini15Flash
            case "google/gemini-2.5-flash-image-preview:free": self = .nanoBananaFree
            case "google/gemini-2.5-flash-image-preview": self = .nanoBanana
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
public extension SupportedModel {
    /// 显示名称
    var displayName: String {
        switch self {
            case .gpt4o: return "GPT-4o"
            case .gpt4oMini: return "GPT-4o Mini"
            case .gpt4oLatest: return "GPT-4o Latest"
            case .gpt35Turbo: return "GPT-3.5 Turbo"
            case .claudeSonnet: return "Claude 3.5 Sonnet"
            case .claudeHaiku: return "Claude 3.5 Haiku"
            case .mistral7b: return "Mistral 7B"
            case .mixtral8x7b: return "Mixtral 8x7B"
            case .gemini15Pro: return "Gemini 1.5 Pro"
            case .gemini15Flash: return "Gemini 1.5 Flash"
            case .nanoBananaFree: return "Nano Banana (Free)"
            case .nanoBanana: return "Nano Banana"
            
            case .minimaxM2: return "Minimax-M2"
            
            case .other(let value): return value
        }
    }
    
    /// 模型提供商
    var provider: String {
        switch self {
            case .gpt4o, .gpt4oMini, .gpt4oLatest, .gpt35Turbo:
                return "OpenAI"
            case .claudeSonnet, .claudeHaiku:
                return "Anthropic"
            case .mistral7b, .mixtral8x7b:
                return "Mistral"
            case .gemini15Pro, .gemini15Flash, .nanoBananaFree, .nanoBanana:
                return "Google"
            case .minimaxM2:
                return "Minimax"
            case .other:
                return "Other"
        }
    }
    
    /// 是否为图像模型
    var isImageModel: Bool {
        switch self {
        case .nanoBananaFree, .nanoBanana:
            return true
        default:
            return false
        }
    }
    
    /// 获取所有聊天模型（排除图像模型）
    static var allChatModels: [SupportedModel] {
        return [
            .gpt4oMini, .gpt4o, .gpt4oLatest, .gpt35Turbo,
            .claudeHaiku, .claudeSonnet,
            .gemini15Flash, .gemini15Pro,
            .mistral7b, .mixtral8x7b,
            .nanoBanana, .nanoBananaFree
        ]
    }
    
    /// 按提供商分组的聊天模型
    static var chatModelsByProvider: [String: [SupportedModel]] {
        return Dictionary(grouping: allChatModels) { $0.provider }
    }
}
