//
//  ChatMessage.swift
//  LLMCore
//
//  Created by Chocoford on 11/12/25.
//

import Foundation
import OpenAI

/// Core message content structure for LLM communication
public struct ChatMessageContent: ContentModel, Identifiable {
    public var id: String
    public var role: Role
    public var content: String?
    public var files: [File]?

    public var usage: CreditsResult?

    /// LLM 决定调用的工具 (assistant 角色消息携带)。
    /// 一个 assistant 消息可以同时有 content (思考) 和 toolCalls (动作)。
    ///
    /// 流式状态约定:
    /// - `nil`: 还没开始流 toolCalls (本条消息可能根本没有 tool 调用, 也可能稍后才会出现)
    /// - `[]`: toolCalls 已开始流, 但还没累积出具体 item
    /// - `[items]`: toolCalls 已开始流, 已累积出至少一个调用
    ///
    /// 注: 这只表达 toolCalls 自身的进度, 不暗示 content 字段的状态。content 是流是停由调用方
    /// 结合 `isStreaming(messageID:in:)` / `usage` / 业务上下文自己决定。
    ///
    /// 实现保证: 一旦在累加流程里设为非 nil, 后续 chunk 不会再把它回退到 nil。
    public var toolCalls: [ToolCall]?

    /// 当 role == .tool 时填, 表示这条消息是哪一个 tool_call 的结果。
    /// 跟前一条 assistant 消息里某个 toolCall 的 id 对应。
    public var toolCallId: String?

    /// 这条消息已经被某次 compact 操作折叠掉, 发送给 LLM 时跳过 (filter 出 contextMessages)。
    /// UI 仍然完整显示 (默认折叠 / 灰色样式), 用户可以展开看历史。
    public var isCompactedOut: Bool

    /// 这条消息是 compact 操作生成的"earlier conversation"摘要。
    /// 用 role=.user 投递给 LLM, content 带固定前缀; UI 上渲染成"摘要卡"区分于普通用户消息。
    public var isCompactSummary: Bool

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: String? = nil,
        files: [File] = [],
        usage: CreditsResult? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        isCompactedOut: Bool = false,
        isCompactSummary: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.files = files
        self.usage = usage
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.isCompactedOut = isCompactedOut
        self.isCompactSummary = isCompactSummary
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.role = try container.decodeIfPresent(ChatMessageContent.Role.self, forKey: .role) ?? .assistant
        self.content = try container.decodeIfPresent(String.self, forKey: .content)
        self.files = try container.decodeIfPresent([ChatMessageContent.File].self, forKey: .files)
        self.usage = try container.decodeIfPresent(CreditsResult.self, forKey: .usage)
        self.toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        self.toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        self.isCompactedOut = try container.decodeIfPresent(Bool.self, forKey: .isCompactedOut) ?? false
        self.isCompactSummary = try container.decodeIfPresent(Bool.self, forKey: .isCompactSummary) ?? false
    }

    // MARK: - Render hints

    /// 这条 assistant 消息**附带工具调用** —— 是这一轮"边说话边动手", 在 UI 上紧接着会有工具卡片。
    /// 注意: 这并不意味着 content 是"内部思考"; native tool_use 模型里 content 仍是 user-facing 的话语。
    public var hasToolCalls: Bool {
        role == .assistant && (toolCalls?.isEmpty == false)
    }

    /// 这条 assistant 消息没有任何工具调用, 也就是 agent 这一轮决定收尾, content 即最终回复。
    public var isFinalAnswer: Bool {
        role == .assistant && (toolCalls?.isEmpty ?? true) && (content?.isEmpty == false)
    }

    /// 这条消息是工具执行结果, UI 默认折叠到对应 toolCall 下方。
    public var isToolResult: Bool {
        role == .tool
    }

    public enum Role: String, ContentModel {
        case system
        case developer
        case user
        case assistant
        case tool

        public var asOpenAIRole: ChatQuery.ChatCompletionMessageParam.Role {
            .init(rawValue: self.rawValue) ?? .user
        }
    }

    public enum File: ContentModel, Hashable, CustomStringConvertible {
        /// 关联值约定是**完整 data URI**, 形如 `data:image/png;base64,<...>`。
        /// 直接拿这个字符串塞进 OpenAI 的 `image_url` 即可被识别为图像;
        /// LLMR2UploadProvider 也按这个格式解析 mediaType。
        case base64EncodedImage(String)
        case image(URL)

        public var description: String {
            switch self {
                case .base64EncodedImage(let string):
                    "Image: \(string)"
                case .image(let url):
                    "Image: \(url.absoluteString)"
            }
        }

        public var asUserMessageContentPart: ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart? {
            switch self {
                case .image(let url):
                    return .image(.init(imageUrl: .init(url: url.absoluteString, detail: nil)))
                case .base64EncodedImage(let dataURI):
                    // dataURI 已是完整 `data:<mediaType>;base64,...`, OpenAI image_url 协议接受 data URI;
                    // base64 字符串只走 vision 通道, 不进文本 tokenizer, 不影响 context window。
                    return .image(.init(imageUrl: .init(url: dataURI, detail: nil)))
            }
        }
        
        // MARK: - Codable
        
        private enum CodingKeys: String, CodingKey {
            case type
            case data
        }
        
        private enum FileType: String, Codable {
            case base64EncodedImage
            case image
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(FileType.self, forKey: .type)
            
            switch type {
            case .base64EncodedImage:
                let data = try container.decode(String.self, forKey: .data)
                self = .base64EncodedImage(data)
            case .image:
                let urlString = try container.decode(String.self, forKey: .data)
                guard let url = URL(string: urlString) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .data,
                        in: container,
                        debugDescription: "Invalid URL string: \(urlString)"
                    )
                }
                self = .image(url)
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            switch self {
            case .base64EncodedImage(let data):
                try container.encode(FileType.base64EncodedImage, forKey: .type)
                try container.encode(data, forKey: .data)
            case .image(let url):
                try container.encode(FileType.image, forKey: .type)
                try container.encode(url.absoluteString, forKey: .data)
            }
        }
    }
}

extension [ChatMessageContent] {
    public var asOpenAIMessages: [ChatQuery.ChatCompletionMessageParam] {
        var results: [ChatQuery.ChatCompletionMessageParam] = []

        var filesNeedToBring: [ChatMessageContent.File] = []

        for message in self {

            var messageParam: ChatQuery.ChatCompletionMessageParam
            switch message.role {
                case .user:
                    messageParam = .user(
                        ChatQuery.ChatCompletionMessageParam.UserMessageParam(
                            content: .contentParts(
                                filesNeedToBring.compactMap {
                                    $0.asUserMessageContentPart
                                }
                                +
                                (
                                    message.content != nil
                                    ? [ .text(.init(text: message.content!)) ]
                                    : []
                                )
                                +
                                (
                                    message.files?.compactMap { file -> ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart? in
                                        switch file {
                                            case .image(let url):
                                                return .image(.init(imageUrl: .init(url: url.absoluteString, detail: nil)))
                                            case .base64EncodedImage(let dataURI):
                                                // dataURI 已是完整 data:...;base64,... 形态, OpenAI image_url 协议直接接收。
                                                return .image(.init(imageUrl: .init(url: dataURI, detail: nil)))
                                        }
                                    } ?? []
                                ),
                            ),
                            name: nil
                        )
                    )
                    filesNeedToBring = []
                case .system:
                    messageParam = .system(
                        .init(content: .contentParts([
                            .init(text: message.content ?? "")
                        ]))
                    )
                case .developer:
                    messageParam = .developer(
                        .init(content: .contentParts([
                            .init(text: message.content ?? "")
                        ]))
                    )
                case .tool:
                    // OpenAI/Anthropic 都要求 tool message 关联到前一条 assistant 消息里某个 tool_call 的 id。
                    // 用 message.toolCallId (provider 给的真实 id), 退而用 message.id 兜底。
                    //
                    // tool message 协议限制: OpenAI Swift SDK 当前的 ToolMessageParam.content 是
                    // TextContent 纯文本, 没法塞 image。所以这里 tool message 只放 text;
                    // 如果 tool 有产出图片 (message.files 非空), 在它后面追加一条 user role
                    // multimodal message 接力图片, 让 vision-capable 模型仍能看到。
                    // 等未来切到 Anthropic 原生 tool_result image block 时只改这一处即可。
                    messageParam = .tool(
                        .init(
                            content: .contentParts([
                                .init(text: message.content ?? "")
                            ]),
                            toolCallId: message.toolCallId ?? message.id
                        )
                    )

                    if let files = message.files, !files.isEmpty {
                        let imageParts = files.compactMap { file -> ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart? in
                            switch file {
                            case .image(let url):
                                return .image(.init(imageUrl: .init(url: url.absoluteString, detail: nil)))
                            case .base64EncodedImage(let dataURI):
                                // dataURI 已是完整 `data:<mediaType>;base64,...`, 见 File enum 注释
                                return .image(.init(imageUrl: .init(url: dataURI, detail: nil)))
                            }
                        }
                        if !imageParts.isEmpty {
                            results.append(messageParam)
                            messageParam = .user(
                                .init(
                                    content: .contentParts(
                                        [.text(.init(text: "[Above tool call returned the following image(s)]"))]
                                        + imageParts
                                    ),
                                    name: nil
                                )
                            )
                        }
                    }
                case .assistant:
                    if let files = message.files {
                        filesNeedToBring = files
                    }

                    // 把我们 ChatMessageContent.toolCalls (如果有) 翻译成 OpenAI SDK 的 ToolCallParam。
                    // 这是必须的: Anthropic 校验 tool_result 必须能在前一条 assistant 消息里找到对应的 tool_use,
                    // 之前我们一直传 nil, 所以多轮 tool 调用直接挂。
                    let toolCallParams: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam]?
                        = message.toolCalls?.map { tc in
                            .init(
                                id: tc.id,
                                function: .init(arguments: tc.arguments, name: tc.name)
                            )
                        }

                    messageParam = .assistant(
                        .init(
                            content: .contentParts([
                                .text(.init(text: message.content ?? "")),
                            ]),
                            audio: nil,
                            name: nil,
                            toolCalls: toolCallParams
                        )
                    )
            }

            results.append(messageParam)
        }

        return results
    }
}

extension [ChatMessageContent.File] {
    public func generatedDescription() -> String {
        """
        Generated files:
            \(self.map { "- \($0.description)" }.joined(separator: "\n    "))
        """
    }
}
