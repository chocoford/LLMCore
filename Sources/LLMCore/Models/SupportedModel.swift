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
    
    case other(String)
    
    public var rawValue: String {
        switch self {
            case .gpt4o: return "gpt-4o"
            case .gpt4oMini: return "gpt-4o-mini"
            case .gpt4oLatest: return "gpt-4o-latest"
            case .gpt35Turbo: return "gpt-3.5-turbo"
            case .claudeSonnet: return "claude-3.5-sonnet"
            case .claudeHaiku: return "claude-3.5-haiku"
            case .mistral7b: return "mistral-7b-instruct"
            case .mixtral8x7b: return "mixtral-8x7b-instruct"
            case .gemini15Pro: return "gemini-1.5-pro"
            case .gemini15Flash: return "gemini-1.5-flash"
            case .nanoBananaFree: return "google/gemini-2.5-flash-image-preview:free"
            case .nanoBanana: return "google/gemini-2.5-flash-image-preview"
            case .other(let value): return value
        }
    }
    
    /// 转换成 MacPaw OpenAI SDK 的 `Model`
    public var asOpenAIModel: Model { self.rawValue }
    
    public init(rawValue: String) {
        switch rawValue {
            case "gpt-4o": self = .gpt4o
            case "gpt-4o-mini": self = .gpt4oMini
            case "gpt-4o-latest": self = .gpt4oLatest
            case "gpt-3.5-turbo": self = .gpt35Turbo
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
}
