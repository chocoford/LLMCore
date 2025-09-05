//
//  ChatModels.swift
//  LLMServer
//
//  Created by Chocoford on 9/3/25.
//

import Foundation
import OpenAI


public struct ChatRequest: ContentModel {
    public var model: SupportedModel
    public var messages: [ChatMessage]
    
    public init(model: SupportedModel, messages: [ChatMessage]) {
        self.model = model
        self.messages = messages
    }
    
    public init(model: SupportedModel, systemPrompt: String?, userPrompt: String) {
        self.model = model
        var msgs: [ChatMessage] = []
        if let systemPrompt {
            msgs.append(ChatMessage(role: .system, content: systemPrompt))
        }
        msgs.append(ChatMessage(role: .user, content: userPrompt))
        self.messages = msgs
    }
}

public struct ChatMessage: ContentModel {
    public var role: Role
    public var content: String?
    
    public var images: [NanoBananaMessageExtra.Choice.Message.Image]? = nil
    
    public init(
        role: Role,
        content: String? = nil,
        images: [NanoBananaMessageExtra.Choice.Message.Image]? = nil
    ) {
        self.role = role
        self.content = content
        self.images = images
    }

    public enum Role: String, ContentModel {
        case system
        case user
        case assistant
        
        public var asOpenAIRole: ChatQuery.ChatCompletionMessageParam.Role {
            .init(rawValue: self.rawValue) ?? .user
        }
    }
}

public struct ChatChoice: ContentModel {
    public var index: Int
    public var message: ChatMessage
    
    public init(index: Int, message: ChatMessage) {
        self.index = index
        self.message = message
    }
}

public struct ChatResponse: ContentModel {
    public var model: String
    public var choices: [ChatChoice]
    
    public init(model: String, choices: [ChatChoice]) {
        self.model = model
        self.choices = choices
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
