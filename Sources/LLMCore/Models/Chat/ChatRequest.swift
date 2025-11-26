//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 11/12/25.
//

import Foundation

public struct ChatRequest<T: ContentModel>: ContentModel {
    /// Protocol for chat request metadata
    /// Conform to this protocol to pass custom metadata with chat requests
    public var model: SupportedModel
    public var messages: [ChatMessageContent]
    public var metadata: T?

    public init(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: T? = nil
    ) {
        self.model = model
        self.messages = messages
        self.metadata = metadata
    }

    public init(
        model: SupportedModel,
        systemPrompt: String?,
        userPrompt: String,
        metadata: T? = nil
    ) {
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


//public struct CreditsTransactionMetadata<T: ContentModel>: ContentModel {
//    public var id = UUID().uuidString
//    public var date = Date()
//    
//    public var userInfo: T
//    public var context: ChatRequestInternalMetadata
//    
//    public init(
//        userInfo: T,
//        context: ChatRequestInternalMetadata
//    ) {
//        self.userInfo = userInfo
//        self.context = context
//    }
//}
