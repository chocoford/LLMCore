//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 11/12/25.
//

import Foundation

public struct ChatRequest: ContentModel {
    public var model: SupportedModel
    public var messages: [ChatMessageContent]
    
    public init(model: SupportedModel, messages: [ChatMessageContent]) {
        self.model = model
        self.messages = messages
    }
    
    public init(model: SupportedModel, systemPrompt: String?, userPrompt: String) {
        self.model = model
        var msgs: [ChatMessageContent] = []
        if let systemPrompt {
            msgs.append(ChatMessageContent(role: .system, content: systemPrompt))
        }
        msgs.append(ChatMessageContent(role: .user, content: userPrompt))
        self.messages = msgs
    }
}
