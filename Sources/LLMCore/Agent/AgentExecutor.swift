//
//  AgentExecutor.swift
//  LLMCore
//
//  ReAct agent loop, native tool-use 版本。
//
//  跟旧版 prompt-based 解析的差异:
//   - 不再让模型在 content 里写 `{"decision": {...}}` JSON 字符串
//   - LLMProvider 直接返回结构化的 ChatMessageContent.toolCalls
//   - 一轮 LLM 调用里 content 是模型的 reasoning (作为 thought 流式展示),
//     toolCalls 是模型决定的 action
//   - 没 toolCalls 就是终止条件 = final answer
//

import Foundation
import Logging

/// Agent execution errors
public enum AgentError: Error, LocalizedError {
    case maxThoughtsReached
    case toolNotFound(String)
    case toolExecutionFailed(String)
    case invalidToolCall(String)
    case conversationNotFound

    public var errorDescription: String? {
        switch self {
            case .maxThoughtsReached:
                return "Agent reached maximum thought steps without finishing"
            case .toolNotFound(let name):
                return "Tool not found: \(name)"
            case .toolExecutionFailed(let reason):
                return "Tool execution failed: \(reason)"
            case .invalidToolCall(let reason):
                return "Invalid tool call: \(reason)"
            case .conversationNotFound:
                return "Conversation not found"
        }
    }
}

public struct EmptyMetadata: ContentModel {
    public init() {}
}

/// Agent executor that drives a native tool-use ReAct loop on top of an LLMProvider.
public final class AgentExecutor: Sendable {
    private let logger = Logger(label: "AgentExecutor")
    private let llmProvider: LLMProvider
    private let toolRegistry: ToolRegistry

    public init(llmProvider: LLMProvider, toolRegistry: ToolRegistry) {
        self.llmProvider = llmProvider
        self.toolRegistry = toolRegistry
    }

    /// Execute agent based on configuration.
    ///
    /// Returns a stream of `ChatMessage` events for the UI. **All** intermediate state goes
    /// through this stream now; there is no separate step callback. Each event is one of:
    ///   - `.content(role=.assistant)` — model's reasoning + (optional) toolCalls for this round
    ///   - `.content(role=.tool, toolCallId)` — observation produced after running a tool
    ///
    /// The UI decides how to render based on `ChatMessageContent` fields:
    ///   - assistant + toolCalls present → text bubble + tool call card
    ///   - assistant + no toolCalls → final answer
    ///   - tool → folded result, attached to the matching toolCall
    /// - Parameter toolResultTransformer: 可选钩子, 在 tool 执行结果生成的 ChatMessageContent
    ///   被 append 进 context / yield 给 UI 之前过一遍。典型用途: 客户端把 tool 产出的
    ///   `.base64EncodedImage` 自动上传到 R2 升级成 `.image(URL)`, 避免大 body 反复发送。
    @MainActor
    public func execute<Metadata: Codable & Equatable & Sendable>(
        conversationID: String,
        agentConfig: AgentConfig,
        contextMessages: [ChatMessageContent],
        model: SupportedModel,
        metadata: Metadata = EmptyMetadata(),
        invocationContext: (any ChatInvocationContext)? = nil,
        toolResultTransformer: (@Sendable (ChatMessageContent) async throws -> ChatMessageContent)? = nil
    ) async throws -> AsyncThrowingStream<ChatMessage, Error> {
        let tools = await toolRegistry.get(agentConfig.tools)
        let toolSchemas = try tools.map { try $0.schema }
        let canStream = model.supportsStreaming

        logger.info("""
                    ==== Executing agent ====
                    - conversationID: \(conversationID)
                    - tools: \(agentConfig.tools) (\(tools.count) loaded)
                    - maxThoughts: \(agentConfig.maxThoughts)
                    - canStream: \(canStream)
                    - agentID: \(agentConfig.agentID ?? "<none>")
                    ==== Executing agent end ====
                    """)

        // No tools registered → straight chat passthrough, no agent loop.
        if tools.isEmpty {
            logger.info("Direct chat mode (no tools)")
            return try await directChat(
                model: model,
                context: contextMessages,
                stream: canStream,
                metadata: metadata,
                agentID: agentConfig.agentID,
                tools: nil
            )
        }

        return AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    var context = contextMessages
                    var thoughtCount = 0

                    while thoughtCount < agentConfig.maxThoughts {
                        // Consumer 端 (LLMStable._sendMessageBody) cancel 时, 这里能感知;
                        // 即便没 await 也每轮检查一下, 防止 round 之间空转。
                        try Task.checkCancellation()
                        thoughtCount += 1
                        self.logger.debug("Thought \(thoughtCount)/\(agentConfig.maxThoughts)")

                        // Budget notice when running out of steps so the model can wrap up.
                        let remaining = agentConfig.maxThoughts - thoughtCount + 1
                        if remaining <= 3 && thoughtCount > 1 {
                            let notice = """
                            Budget notice: \(remaining) turn(s) remaining before the loop is forced to stop. \
                            If you have not made clear progress, stop calling tools and answer the user with \
                            what you have so far.
                            """
                            context.append(ChatMessageContent(role: .user, content: notice))
                        }

                        let requestMetadata = ChatRequestMetadata(
                            userInfo: metadata,
                            context: ChatRequestInternalMetadata(
                                conversationID: conversationID,
                                agentStep: thoughtCount
                            )
                        )

                        // Run one LLM round; this yields .content(assistant) chunks along the way.
                        let final = try await self.runOneRound(
                            model: model,
                            context: context,
                            stream: canStream,
                            metadata: requestMetadata,
                            agentID: agentConfig.agentID,
                            toolSchemas: toolSchemas,
                            continuation: continuation
                        )

                        let toolCalls = final.toolCalls ?? []

                        // No tool calls → this assistant message is the final answer; loop ends.
                        if toolCalls.isEmpty {
                            self.logger.info("No tool calls; final answer after \(thoughtCount) thought(s)")
                            continuation.finish()
                            return
                        }

                        // Has tool calls → record the assistant decision + execute each tool.
                        context.append(ChatMessageContent(
                            id: final.id,
                            role: .assistant,
                            content: final.content,
                            toolCalls: toolCalls
                        ))

                        for toolCall in toolCalls {
                            let result: ToolResult
                            do {
                                if let tool = tools.first(where: { $0.name == toolCall.name }) {
                                    result = try await tool.execute(
                                        toolCall.arguments,
                                        context: invocationContext
                                    )
                                    self.logger.debug("Tool \(toolCall.name) → \(result.textObservation.prefix(100))… images=\(result.imageFiles.count)")
                                } else {
                                    result = .text("Error: tool '\(toolCall.name)' not found")
                                    self.logger.error("Tool '\(toolCall.name)' not found")
                                }
                            } catch {
                                result = .text("Tool execution failed: \(error.localizedDescription)")
                                self.logger.error("Tool execution failed: \(error.localizedDescription)")
                            }

                            // Tool result: appended to context (for next LLM round) AND yielded
                            // to the UI stream so the conversation appears inline.
                            // text 走 content; image 走 files (transport 层会按 provider 协议接力)。
                            var toolMessage = ChatMessageContent(
                                role: .tool,
                                content: result.textObservation,
                                files: result.imageFiles,
                                toolCallId: toolCall.id
                            )
                            // 让调用方有机会处理 (如自动上传 base64 → R2 URL), 失败时保持原样。
                            if let transformer = toolResultTransformer {
                                do {
                                    toolMessage = try await transformer(toolMessage)
                                } catch {
                                    self.logger.warning("toolResultTransformer failed, falling back to raw message: \(error)")
                                }
                            }
                            context.append(toolMessage)
                            continuation.yield(.content(toolMessage))
                        }
                    }

                    throw AgentError.maxThoughtsReached
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Consumer 释放 stream (LLMStable 那边 for-try-await 退出 / 抛错) 时触发,
            // cancel producer Task 让 ReAct loop 立刻停, 不再发起下一轮 LLM 调用。
            // CancellationError 会沿 await 链路到 LLMClient.streamChat → URLSession async →
            // 客户端 SSE 关闭 → 服务端 onTermination → 关 OpenRouter 连接。
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }
    }

    // MARK: - Single round helpers

    /// Run one LLM round (streaming or not). Returns the final accumulated assistant message.
    /// During streaming, accumulated content + toolCalls chunks are continuously yielded
    /// to the UI via `continuation.yield(.content(...))`. After the loop, the caller decides
    /// whether to keep going (toolCalls present) or terminate (no toolCalls = final answer).
    @MainActor
    private func runOneRound<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        context: [ChatMessageContent],
        stream: Bool,
        metadata: Metadata?,
        agentID: String?,
        toolSchemas: [ToolSchema],
        continuation: AsyncThrowingStream<ChatMessage, Error>.Continuation
    ) async throws -> ChatMessageContent {
        let toolsArg: [ToolSchema]? = toolSchemas.isEmpty ? nil : toolSchemas

        if stream {
            let responseStream = try await llmProvider.streamChat(
                model: model,
                messages: context,
                metadata: metadata,
                agentID: agentID,
                tools: toolsArg
            )

            var accumulated: ChatMessageContent?

            for try await event in responseStream {
                switch event {
                case .message(let chunk):
                    let merged = Self.merge(into: accumulated, chunk: chunk)
                    accumulated = merged
                    continuation.yield(.content(merged))

                case .settlement(let credits):
                    if var msg = accumulated {
                        msg.usage = credits
                        accumulated = msg
                        continuation.yield(.content(msg))
                    }
                }
            }

            guard let final = accumulated else {
                throw AgentError.toolExecutionFailed("No response from LLM")
            }
            return final
        } else {
            let result = try await llmProvider.chat(
                model: model,
                messages: context,
                metadata: metadata,
                agentID: agentID,
                tools: toolsArg
            )
            guard let message = result.data else {
                throw AgentError.toolExecutionFailed(result.error?.message ?? "No response from LLM")
            }
            continuation.yield(.content(message))
            return message
        }
    }

    /// Merge a streaming chunk into the accumulated message.
    /// Some providers stream cumulative content (each chunk has full content so far),
    /// others stream incremental deltas. We detect by comparing prefixes.
    private static func merge(
        into existing: ChatMessageContent?,
        chunk: ChatMessageContent
    ) -> ChatMessageContent {
        guard var existing else {
            return chunk
        }

        // Content
        if let newContent = chunk.content, !newContent.isEmpty {
            let existingContent = existing.content ?? ""
            if newContent.hasPrefix(existingContent) {
                // Cumulative: replace
                existing.content = newContent
            } else {
                // Delta: append
                existing.content = existingContent + newContent
            }
        }

        // Files
        if let newFiles = chunk.files, !newFiles.isEmpty {
            existing.files = (existing.files ?? []) + newFiles
        }

        // toolCalls: provider 的流式累加已经在 ServerLLMProvider 里做完了,
        // 它每次给的就是当前完整状态, 直接覆盖即可
        if let newToolCalls = chunk.toolCalls {
            existing.toolCalls = newToolCalls
        }

        // Usage / id 跟 chunk 走 (最新一次)
        if let usage = chunk.usage { existing.usage = usage }
        if !chunk.id.isEmpty { existing.id = chunk.id }

        return existing
    }

    // MARK: - Direct chat (no tools)

    /// Pass-through chat for the no-tool case.
    private func directChat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        context: [ChatMessageContent],
        stream: Bool,
        metadata: Metadata?,
        agentID: String?,
        tools: [ToolSchema]?
    ) async throws -> AsyncThrowingStream<ChatMessage, Error> {
        if stream {
            return AsyncThrowingStream { continuation in
                let producer = Task {
                    do {
                        let responseStream = try await self.llmProvider.streamChat(
                            model: model,
                            messages: context,
                            metadata: metadata,
                            agentID: agentID,
                            tools: tools
                        )
                        var accumulated: ChatMessageContent?
                        for try await event in responseStream {
                            switch event {
                            case .message(let chunk):
                                let merged = Self.merge(into: accumulated, chunk: chunk)
                                accumulated = merged
                                continuation.yield(.content(merged))
                            case .settlement(let credits):
                                if var msg = accumulated {
                                    msg.usage = credits
                                    accumulated = msg
                                    continuation.yield(.content(msg))
                                }
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    producer.cancel()
                }
            }
        } else {
            return AsyncThrowingStream { continuation in
                let producer = Task {
                    do {
                        let result = try await self.llmProvider.chat(
                            model: model,
                            messages: context,
                            metadata: metadata,
                            agentID: agentID,
                            tools: tools
                        )
                        guard let message = result.data else {
                            throw AgentError.toolExecutionFailed(result.error?.message ?? "No response from LLM")
                        }
                        continuation.yield(.content(message))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    producer.cancel()
                }
            }
        }
    }
}
