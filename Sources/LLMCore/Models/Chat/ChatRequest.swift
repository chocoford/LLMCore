//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 11/12/25.
//

import Foundation

public protocol ChatRequestMetadata: ContentModel {}

/// Empty metadata type for requests without custom metadata
public struct EmptyMetadata: ChatRequestMetadata {
    public init() {}
}

public struct ChatRequest<Metadata: ChatRequestMetadata>: ContentModel {
    /// Protocol for chat request metadata
    /// Conform to this protocol to pass custom metadata with chat requests
    public var model: SupportedModel
    public var messages: [ChatMessageContent]
    public var metadata: Metadata?

    public init(model: SupportedModel, messages: [ChatMessageContent], metadata: Metadata? = nil) {
        self.model = model
        self.messages = messages
        self.metadata = metadata
    }

    public init(model: SupportedModel, systemPrompt: String?, userPrompt: String, metadata: Metadata? = nil) {
        self.model = model
        var msgs: [ChatMessageContent] = []
        if let systemPrompt {
            msgs.append(ChatMessageContent(role: .system, content: systemPrompt))
        }
        msgs.append(ChatMessageContent(role: .user, content: userPrompt))
        self.messages = msgs
        self.metadata = metadata
    }
}
