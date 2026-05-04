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
    public var toolCalls: [ToolCall]?

    /// 当 role == .tool 时填, 表示这条消息是哪一个 tool_call 的结果。
    /// 跟前一条 assistant 消息里某个 toolCall 的 id 对应。
    public var toolCallId: String?

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: String? = nil,
        files: [File] = [],
        usage: CreditsResult? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.files = files
        self.usage = usage
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
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
                default:
                    return nil
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

            let messageParam: ChatQuery.ChatCompletionMessageParam
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
                                    message.files?.compactMap { file in
                                        switch file {
                                            case .image(let url):
                                                return .image(.init(imageUrl: .init(url: url.absoluteString, detail: nil)))
                                            default:
                                                return nil
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
                    // NOTE: OpenAI 官方要求 tool message 关联一个 tool_call_id。
                    // 我们目前没有单独的字段，用 message.id 兜底；
                    // 若要走 OpenAI 的原生 function-calling，需要在 ChatMessageContent 上新增 toolCallId 字段。
                    messageParam = .tool(
                        .init(
                            content: .contentParts([
                                .init(text: message.content ?? "")
                            ]),
                            toolCallId: message.id
                        )
                    )
                case .assistant:
                    if let files = message.files {
                        filesNeedToBring = files
                    }

                    messageParam = .assistant(
                        .init(
                            content: .contentParts([
                                .text(.init(text: message.content ?? "")),
                            ]),
                            audio: nil,
                            name: nil,
                            toolCalls: nil
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
