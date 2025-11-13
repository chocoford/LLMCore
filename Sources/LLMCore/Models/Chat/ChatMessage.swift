//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 11/12/25.
//

import Foundation
import OpenAI

public enum ChatMessage: ContentModel, Identifiable {
    case loading(UUID = UUID())
    case content(ChatMessageContent)
    case error(UUID, String)
    
    public var id: String {
        switch self {
            case .loading(let id):
                return id.uuidString
            case .content(let content):
                return content.id
            case .error(let id, _):
                return id.uuidString
        }
    }
    
    public var content: String? {
        get {
            switch self {
                case .content(let content):
                    content.content
                case .error(_, let errorMessage):
                    errorMessage
                default:
                    nil
            }
        }
        set {
            switch self {
                case .content(var content):
                    content.content = newValue
                    self = .content(content)
                default:
                    return
            }
        }
    }
    public var usage: CreditsResult? {
        get {
            switch self {
                case .content(let content):
                    content.usage
                default:
                    nil
            }
        }
        set {
            switch self {
                case .content(var content):
                    content.usage = newValue
                    self = .content(content)
                default:
                    return
            }
        }
    }
    
    public init(from decoder: any Decoder) throws {
        self = .content(try ChatMessageContent(from: decoder))
    }
    
    public func encode(to encoder: any Encoder) throws {
        switch self {
            case .content(let content):
                try content.encode(to: encoder)
            default:
                return
        }
    }
}

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

//    public init(from decoder: any Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        // OpenAI无论是stream还是non-stream，这里都没有id
//        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
//        self.role = try container.decode(ChatMessageContent.Role.self, forKey: .role)
//        self.content = try container.decodeIfPresent(String.self, forKey: .content)
//        self.files = try container.decodeIfPresent([ChatMessageContent.File].self, forKey: .files)
//        self.usage = try container.decodeIfPresent(CreditsResult.self, forKey: .usage)
//    }
    
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

extension [ChatMessage] {
    public var contentMessages: [ChatMessageContent] {
        get {
            self.compactMap {
                switch $0 {
                    case .content(let content):
                        content
                    default:
                        nil
                }
            }
        }
        set {
            var j = newValue.startIndex
            for i in self.indices {
                if j >= newValue.endIndex {
                    break
                }
                if case .content = self[i] {
                    self[i] = .content(newValue[j])
                    j += 1
                }
            }
        }
    }
    
    public var asOpenAIMessages: [ChatQuery.ChatCompletionMessageParam] {
        contentMessages.asOpenAIMessages
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
