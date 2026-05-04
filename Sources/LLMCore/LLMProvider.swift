//
//  LLMProvider.swift
//  LLMCore
//
//  Created by Chocoford
//

import Foundation

public struct ChatRequestInternalMetadata: ContentModel {
    public var conversationID: String
    public var agentStep: Int
    public var source: LLMCallSource?

    public init(conversationID: String, agentStep: Int, source: LLMCallSource? = nil) {
        self.conversationID = conversationID
        self.agentStep = agentStep
        self.source = source
    }
}

public struct ChatRequestMetadata<T: ContentModel>: ContentModel {
    public var id = UUID().uuidString
    public var date = Date()
    
    public var userInfo: T
    public var context: ChatRequestInternalMetadata?
    
    public init(
        userInfo: T,
        context: ChatRequestInternalMetadata
    ) {
        self.userInfo = userInfo
        self.context = context
    }
    
    public init() where T == EmptyMetadata {
        self.userInfo = EmptyMetadata()
        self.context = nil
    }
}

/// 统一的 LLM 服务提供者协议
/// 由客户端和服务端分别实现
public protocol LLMProvider: Sendable {
    /// 非流式聊天
    func chat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?,
        agentID: String?,
        tools: [ToolSchema]?
    ) async throws -> APIResponse<ChatMessageContent>

    /// 流式聊天
    func streamChat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?,
        agentID: String?,
        tools: [ToolSchema]?
    ) async throws -> AsyncThrowingStream<StreamChatResponse, Error>
}

// MARK: - Defaults

extension LLMProvider {
    /// 老的签名兜底, 让没显式传 agentID/tools 的调用点继续工作。
    public func chat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?,
        agentID: String? = nil
    ) async throws -> APIResponse<ChatMessageContent> {
        try await chat(model: model, messages: messages, metadata: metadata, agentID: agentID, tools: nil)
    }

    public func streamChat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?,
        agentID: String? = nil
    ) async throws -> AsyncThrowingStream<StreamChatResponse, Error> {
        try await streamChat(model: model, messages: messages, metadata: metadata, agentID: agentID, tools: nil)
    }

    public func chat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?
    ) async throws -> APIResponse<ChatMessageContent> {
        try await chat(model: model, messages: messages, metadata: metadata, agentID: nil, tools: nil)
    }

    public func streamChat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?
    ) async throws -> AsyncThrowingStream<StreamChatResponse, Error> {
        try await streamChat(model: model, messages: messages, metadata: metadata, agentID: nil, tools: nil)
    }
}
