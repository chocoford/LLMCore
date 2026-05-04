//
//  ToolCall.swift
//  LLMCore
//
//  Native tool-use 协议下的核心数据类型。
//
//  Provider (OpenAI / Anthropic / Gemini 等) 在 LLM 响应里直接给结构化的 tool_calls,
//  不再让模型在 content 里写 JSON 字符串。这两个类型把 provider 的格式归一化:
//
//  - ToolCall:   LLM 决定调一个工具的结构化结果
//  - ToolSchema: 客户端注册工具时声明它的契约 (用于发给 provider 的 tools 字段)
//

import Foundation
@preconcurrency import AnyCodable

/// LLM 决定调一个工具时返回的结构。从 provider 原生 tool_calls 字段归一化而来。
public struct ToolCall: ContentModel {
    /// Provider 给的唯一 id, 后续构造 tool result 消息时要带上 (用于关联)。
    public var id: String
    /// 工具名 (跟 client 注册的 Tool.name 对应)。
    public var name: String
    /// 工具参数 JSON 字符串。Provider 通常以字符串形式返回(即使内容是 JSON 对象)。
    /// 客户端 `Tool.execute(_:)` 接收的就是这个字符串。
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// 客户端注册一个工具给 provider 时的声明 (= function schema)。
/// 客户端把它放进 `ChatRequest.tools` 一起发给服务端, 服务端转成 OpenAI/Anthropic 各自的格式。
public struct ToolSchema: ContentModel {
    public var name: String
    public var description: String
    /// JSON Schema (object 形态), 描述工具参数。
    /// 用 AnyCodable 包是因为 schema 可能任意嵌套 (object / array / oneOf / 等),
    /// 强类型表达不划算。客户端 / 服务端两侧只需把它当成 opaque 字典透传给 provider。
    public var parameters: AnyCodable

    public init(name: String, description: String, parameters: AnyCodable) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}
