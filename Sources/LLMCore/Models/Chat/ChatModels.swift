//
//  ChatModels.swift
//  LLMServer
//
//  Created by Chocoford on 9/3/25.
//

import Foundation
import OpenAI



public struct StreamChatChoiceDelta: ContentModel {
    public var index: Int
    public var delta: ChatMessageContent
    public var finishReason: ChatResult.Choice.FinishReason?
    
    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }
    
    public init(index: Int, delta: ChatMessageContent, finishReason: ChatResult.Choice.FinishReason? = nil) {
        self.index = index
        self.delta = delta
        self.finishReason = finishReason
    }
}

public struct Usage: ContentModel {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
    
    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public struct AskRequest: ContentModel {
    public var systemPrompt: String?
    public var userPrompt: String
    public var model: SupportedModel? // 可选，默认为 gpt4oMini
    
    public init(systemPrompt: String? = nil, userPrompt: String, model: SupportedModel? = nil) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.model = model
    }
}


