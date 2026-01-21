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

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: String? = nil,
        files: [File] = [],
        usage: CreditsResult? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.files = files
        self.usage = usage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.role = try container.decodeIfPresent(ChatMessageContent.Role.self, forKey: .role) ?? .assistant
        self.content = try container.decodeIfPresent(String.self, forKey: .content)
        self.files = try container.decodeIfPresent([ChatMessageContent.File].self, forKey: .files)
        self.usage = try container.decodeIfPresent(CreditsResult.self, forKey: .usage)
    }

    public enum Role: String, ContentModel {
        case system
        case user
        case assistant

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
