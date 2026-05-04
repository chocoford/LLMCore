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
    /// Returns a stream of `ChatMessage` events for the UI:
    ///   - `.content(ChatMessageContent)` for assistant messages (intermediate reasoning + final answer)
    ///   - `.agentStep(AgentStep)` is emitted via `onStep` callback (not in this stream) for richer UI
    @MainActor
    public func execute<Metadata: Codable & Equatable & Sendable>(
        conversationID: String,
        agentConfig: AgentConfig,
        contextMessages: [ChatMessageContent],
        model: SupportedModel,
        metadata: Metadata = EmptyMetadata(),
        invocationContext: (any ChatInvocationContext)? = nil,
        onStep: @escaping (AgentStep) async -> Void
    ) async throws -> AsyncThrowingStream<ChatMessage, Error> {
        let tools = await toolRegistry.get(agentConfig.tools)
        let toolSchemas = tools.map { $0.schema }
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

        // Direct chat mode: no tools registered, just pass through.
        if agentConfig.allowedSteps.isEmpty || tools.isEmpty {
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
            Task {
                do {
                    var context = contextMessages
                    var thoughtCount = 0
                    var lastUsage: CreditsResult?
                    var accumulatedFiles: [ChatMessageContent.File] = []

                    while thoughtCount < agentConfig.maxThoughts {
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

                        // Run one LLM round
                        let final = try await self.runOneRound(
                            model: model,
                            context: context,
                            stream: canStream,
                            thoughtNumber: thoughtCount,
                            metadata: requestMetadata,
                            agentID: agentConfig.agentID,
                            toolSchemas: toolSchemas,
                            onStep: onStep,
                            continuation: continuation
                        )

                        if let usage = final.usage { lastUsage = usage }
                        if let files = final.files { accumulatedFiles.append(contentsOf: files) }

                        let toolCalls = final.toolCalls ?? []

                        // No tool call → the assistant message is the final answer.
                        if toolCalls.isEmpty {
                            self.logger.info("No tool calls; final answer after \(thoughtCount) thought(s)")
                            // 流式过程中已经把 content 增量 yield 给 client 了,
                            // 这里再 yield 一次完整版, 带上 accumulatedFiles 和 lastUsage。
                            continuation.yield(.content(ChatMessageContent(
                                id: final.id,
                                role: .assistant,
                                content: final.content,
                                files: accumulatedFiles,
                                usage: lastUsage
                            )))
                            continuation.finish()
                            return
                        }

                        // Has tool calls → record the assistant message into context, then execute each.
                        context.append(ChatMessageContent(
                            id: final.id,
                            role: .assistant,
                            content: final.content,
                            toolCalls: toolCalls
                        ))

                        for toolCall in toolCalls {
                            await onStep(AgentStep(
                                stepNumber: thoughtCount,
                                type: .action,
                                content: "\(toolCall.name) \(toolCall.arguments)",
                                title: toolCall.name
                            ))

                            let observation: String
                            do {
                                if let tool = tools.first(where: { $0.name == toolCall.name }) {
                                    observation = try await tool.execute(
                                        toolCall.arguments,
                                        context: invocationContext
                                    )
                                    self.logger.debug("Tool \(toolCall.name) → \(observation.prefix(100))…")
                                } else {
                                    observation = "Error: tool '\(toolCall.name)' not found"
                                    self.logger.error("\(observation)")
                                }
                            } catch {
                                observation = "Tool execution failed: \(error.localizedDescription)"
                                self.logger.error("\(observation)")
                            }

                            // Tool result message — use .tool role + toolCallId so OpenAI/Anthropic can pair.
                            context.append(ChatMessageContent(
                                role: .tool,
                                content: observation,
                                toolCallId: toolCall.id
                            ))

                            await onStep(AgentStep(
                                stepNumber: thoughtCount,
                                type: .observation,
                                content: observation
                            ))
                        }
                    }

                    throw AgentError.maxThoughtsReached
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Single round helpers

    /// Run one LLM round (streaming or not). Returns the final accumulated assistant message.
    /// During streaming, content chunks are emitted via `continuation.yield(.content(...))`
    /// and thought steps via `onStep`. Tool-call deltas are accumulated server-side and
    /// arrive on `final.toolCalls` once the round completes.
    @MainActor
    private func runOneRound<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        context: [ChatMessageContent],
        stream: Bool,
        thoughtNumber: Int,
        metadata: Metadata?,
        agentID: String?,
        toolSchemas: [ToolSchema],
        onStep: @escaping (AgentStep) async -> Void,
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
            var thoughtStepID: UUID? = nil
            var streamedContentLength = 0

            for try await event in responseStream {
                switch event {
                case .message(let chunk):
                    // Merge into accumulated state. Provider's stream mode usually gives
                    // already-cumulative content + tool_calls in each chunk, but we also
                    // tolerate per-delta chunks.
                    let merged = Self.merge(into: accumulated, chunk: chunk)
                    accumulated = merged

                    // Emit thought step from streaming content for UI rendering
                    if let content = merged.content, content.count > streamedContentLength {
                        streamedContentLength = content.count
                        let stepID = thoughtStepID ?? UUID()
                        thoughtStepID = stepID
                        await onStep(AgentStep(
                            id: stepID,
                            stepNumber: thoughtNumber,
                            type: .thought,
                            content: content
                        ))
                    }

                    // Yield the assistant message stream to UI
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
            // 非流式: 直接发一次 thought + content 给 UI
            if let content = message.content, !content.isEmpty {
                await onStep(AgentStep(
                    stepNumber: thoughtNumber,
                    type: .thought,
                    content: content
                ))
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
                Task {
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
            }
        } else {
            return AsyncThrowingStream { continuation in
                Task {
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
            }
        }
    }
}
