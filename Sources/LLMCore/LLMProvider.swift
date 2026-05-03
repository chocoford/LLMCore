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
    /// - Parameters:
    ///   - model: 使用的模型
    ///   - messages: 聊天消息列表
    ///   - metadata: 元数据(可选)
    ///   - agentID: 关联的服务端 domain agent (可选)。客户端跑 agent loop 时透传给服务端,
    ///              服务端用它注入 systemPrompt + 校验 model 权限。
    /// - Returns: 聊天结果
    func chat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?,
        agentID: String?
    ) async throws -> APIResponse<ChatMessageContent>

    /// 流式聊天
    func streamChat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?,
        agentID: String?
    ) async throws -> AsyncThrowingStream<StreamChatResponse, Error>
}

// MARK: - Defaults

extension LLMProvider {
    /// 老的 3-参数签名兜底, 让现有调用点 (没传 agentID 的) 自动走 agentID = nil。
    public func chat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?
    ) async throws -> APIResponse<ChatMessageContent> {
        try await chat(model: model, messages: messages, metadata: metadata, agentID: nil)
    }

    public func streamChat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        messages: [ChatMessageContent],
        metadata: Metadata?
    ) async throws -> AsyncThrowingStream<StreamChatResponse, Error> {
        try await streamChat(model: model, messages: messages, metadata: metadata, agentID: nil)
    }
}
