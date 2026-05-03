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
    /// 可选的领域 agent 标识。传了之后服务端会:
    ///   1. 校验 model 是否在该 agent 的 allowedModels 内
    ///   2. 剥掉 messages 里所有 system 消息, 注入服务端持有的 systemPrompt
    /// 客户端不需要也不应该自己拼 system prompt。
    public var agentID: String?

    public init(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: T? = nil,
        agentID: String? = nil
    ) {
        self.model = model
        self.messages = messages
        self.metadata = metadata
        self.agentID = agentID
    }

    public init(
        model: SupportedModel,
        systemPrompt: String?,
        userPrompt: String,
        metadata: T? = nil,
        agentID: String? = nil
    ) {
        self.model = model
        var msgs: [ChatMessageContent] = []
        if let systemPrompt {
            msgs.append(ChatMessageContent(role: .system, content: systemPrompt))
        }
        msgs.append(ChatMessageContent(role: .user, content: userPrompt))
        self.messages = msgs
        self.metadata = metadata
        self.agentID = agentID
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
