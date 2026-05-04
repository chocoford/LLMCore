//
//  ChatRequest+LogSummary.swift
//  LLMCore
//
//  生成日志友好的 ChatRequest 摘要。
//
//  之前服务端用 `chatReq.prettyPrintedJSON(maxValueLength: 4096)` 把整个请求体
//  打到日志里, 一条 chat 日志能撑到 几十 KB (尤其带 base64 图片或多轮长上下文)。
//  这里给一个"信息量足够定位问题、但不噪音"的紧凑格式。
//

import Foundation

extension ChatRequest {
    /// 一行式日志摘要, 适合 logger.info 用。
    /// 例:
    ///   [chat] model=gpt-4o-mini agentID=excalidraw-canvas turns=5 tools=7 stream=true
    ///     last-user: "请帮我画一个流程图..." (28 chars)
    ///     context: system=1 user=2 assistant=2 tool=0, files=1, prior_tool_calls=1
    public var logSummary: String {
        var lines: [String] = []

        // 头一行: 关键标识
        var head = "[chat] model=\(model.rawValue)"
        if let agentID, !agentID.isEmpty { head += " agentID=\(agentID)" }
        head += " turns=\(messages.count)"
        if let tools, !tools.isEmpty { head += " tools=\(tools.count)" }
        lines.append(head)

        // 最后一条 user 消息(用户当前的请求, 最有价值)
        if let lastUser = messages.last(where: { $0.role == .user }) {
            let preview = Self.previewContent(lastUser.content ?? "")
            lines.append("  last-user: \(preview)")
        }

        // 上下文画像
        var roleCounts: [ChatMessageContent.Role: Int] = [:]
        var fileCount = 0
        var priorToolCalls = 0
        for msg in messages {
            roleCounts[msg.role, default: 0] += 1
            fileCount += msg.files?.count ?? 0
            priorToolCalls += msg.toolCalls?.count ?? 0
        }
        let rolePart = ChatMessageContent.Role.allCases
            .compactMap { role -> String? in
                guard let c = roleCounts[role], c > 0 else { return nil }
                return "\(role.rawValue)=\(c)"
            }
            .joined(separator: " ")
        var ctx = "  context: \(rolePart)"
        if fileCount > 0 { ctx += ", files=\(fileCount)" }
        if priorToolCalls > 0 { ctx += ", prior_tool_calls=\(priorToolCalls)" }
        lines.append(ctx)

        return lines.joined(separator: "\n")
    }

    /// 单行内容预览, 长内容截断, base64/dataURI 用占位符代替。
    static func previewContent(_ raw: String, maxLen: Int = 800) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(empty)" }
        // dataURI 直接占位
        if trimmed.hasPrefix("data:") { return "(data URI \(trimmed.count) chars)" }
        let single = trimmed.replacingOccurrences(of: "\n", with: " ")
        if single.count > maxLen {
            let prefix = single.prefix(maxLen)
            return "\"\(prefix)…\" (\(single.count) chars)"
        }
        return "\"\(single)\" (\(single.count) chars)"
    }
}

extension ChatMessageContent.Role: CaseIterable {
    public static var allCases: [ChatMessageContent.Role] {
        [.system, .developer, .user, .assistant, .tool]
    }
}

// MARK: - Response side

extension ChatMessageContent {
    /// 模型一次响应的紧凑摘要, 用于 logger.info。
    /// 包含 content 预览 + 每个 toolCall 的名字与参数预览 + usage(如有)。
    public var logSummary: String {
        var lines: [String] = []
        lines.append("[chat-resp] role=\(role.rawValue)")

        if let content, !content.isEmpty {
            lines.append("  content: \(ChatRequest<EmptyMetadata>.previewContent(content))")
        }

        if let toolCalls, !toolCalls.isEmpty {
            lines.append("  toolCalls:")
            for tc in toolCalls {
                let args = ChatRequest<EmptyMetadata>.previewContent(tc.arguments, maxLen: 600)
                lines.append("    - \(tc.name)\(tc.id.isEmpty ? "" : "[\(tc.id)]"): \(args)")
            }
        }

        if let files, !files.isEmpty {
            lines.append("  files: \(files.count)")
        }

        if let usage {
            lines.append("  credits: consumed=\(usage.consumed) remains=\(usage.remains)")
        }

        return lines.joined(separator: "\n")
    }
}
