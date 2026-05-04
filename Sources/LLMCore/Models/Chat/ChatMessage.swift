//
//  ChatMessage.swift
//  LLMKit
//
//  Created by Claude Code
//

import Foundation

/// Client-side message representation with UI states.
///
/// 历史: 之前还有一个 `.agentStep(AgentStep)` case 用来表达 plan / reflection / action /
/// observation 等 prompt-based ReAct 步骤。切到 native tool_use 后所有信息都已经在
/// `ChatMessageContent` 里 (role + content + toolCalls + toolCallId), 不再需要单独的
/// step type 概念。UI 直接看字段渲染。
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

    public var role: ChatMessageContent.Role? {
        switch self {
            case .loading:
                nil
            case .content(let chatMessageContent):
                chatMessageContent.role
            case .error:
                nil
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

    public var files: [ChatMessageContent.File]? {
        get {
            if case .content(let content) = self {
                return content.files
            }
            return nil
        }

        set {
            switch self {
                case .content(var content):
                    content.files = newValue
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
        // ChatMessage 持久化时只会 encode 出 ChatMessageContent 形态 (loading/error 不存),
        // 所以 decode 一律走 .content 路径。
        self = .content(try ChatMessageContent(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
            case .content(let content):
                try content.encode(to: encoder)
            default:
                // loading and error are not persisted
                return
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
}
