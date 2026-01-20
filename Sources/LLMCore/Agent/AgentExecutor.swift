//
//  AgentExecutor.swift
//  LLMCore
//
//  Created by Claude Code
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
                return "Agent reached maximum thought steps without finding an answer"
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

/// Agent executor that handles execution based on configuration
public final class AgentExecutor: Sendable {
    private let logger = Logger(label: "AgentExecutor")
    private let llmProvider: LLMProvider
    private let toolRegistry: ToolRegistry
    private let finalAnswerToolName = "final_answer"

    public init(llmProvider: LLMProvider, toolRegistry: ToolRegistry) {
        self.llmProvider = llmProvider
        self.toolRegistry = toolRegistry
    }

    /// Execute agent based on configuration
    /// Returns a stream of chat messages (always streaming, even if model doesn't support it)
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
        let canStream = model.supportsStreaming

        logger.info("""
                    ==== Executing agent ====
                    - conversationID: \(conversationID)
                    - steps: \(agentConfig.allowedSteps)
                    - tools: \(agentConfig.tools) (\(tools.count) loaded)
                    - maxThoughts: \(agentConfig.maxThoughts)
                    - canStream: \(canStream)
                    ==== Executing agent end ====
                    """)

        // If no agent steps are enabled, use direct chat mode
        if agentConfig.allowedSteps.isEmpty {
            logger.info("Direct chat mode (no agent steps)")
            return try await directChat(
                model: model,
                context: contextMessages,
                stream: canStream,
                metadata: metadata
            )
        }

        // Wrap the agent loop in an AsyncThrowingStream
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var context = contextMessages
                    self.logger.info("Context messages count: \(context.count)")
                    for (index, msg) in context.enumerated() {
                        self.logger.info("[\(index)] role: \(msg.role), content: \(msg.content?.prefix(50) ?? "nil")...")
                    }

                    var thoughtCount = 0
                    var accumulatedFiles: [ChatMessageContent.File] = []  // Track files from streaming responses
                    var lastUsage: CreditsResult?  // Track usage from the last thought

                    // Main thought loop - every iteration starts with a thought
                    while thoughtCount < agentConfig.maxThoughts {
                        thoughtCount += 1
                        self.logger.debug("Thought \(thoughtCount)/\(agentConfig.maxThoughts)")

                        let requestMetadata = ChatRequestMetadata(
                            userInfo: metadata,
                            context: ChatRequestInternalMetadata(
                                conversationID: conversationID,
                                agentStep: thoughtCount
                            )
                        )

                        // Step 1: Get thought response from LLM (as stream)
                        let thoughtStream = try await self.requestThought(
                            model: model,
                            context: context,
                            stream: canStream,
                            thoughtNumber: thoughtCount,
                            metadata: requestMetadata,
                            onStep: onStep
                        )

                        // Consume the stream and capture the final accumulated thought
                        var thoughtMessage: ChatMessageContent?

                        for try await chunk in thoughtStream {
                            thoughtMessage = chunk
                        }

                        guard let finalMessage = thoughtMessage else {
                            throw AgentError.toolExecutionFailed("No response from LLM")
                        }

                        // Accumulate files and usage from this thought
                        if let files = finalMessage.files {
                            accumulatedFiles.append(contentsOf: files)
                        }
                        if let usage = finalMessage.usage {
                            lastUsage = usage
                        }

                        let thoughtContent = finalMessage.content ?? ""

                        // Step 2: Parse the thought response
                        self.logger.debug("Thought content (first 200 chars): \(thoughtContent.prefix(200))")
                        let response = self.parseThoughtResponse(thoughtContent)

                        // Step 3: Handle the directive
                        if let response {
                            switch response {
                            case .action(let toolCall):
                                self.logger.debug("Next step: action")

                                // Emit action step
                                let actionStep = AgentStep(
                                    stepNumber: thoughtCount,
                                    type: .action,
                                    content: "Action: \(toolCall.tool)\nInput: \(toolCall.input)"
                                )
                                await onStep(actionStep)

                                // Execute tool
                                guard let tool = tools.first(where: { $0.name == toolCall.tool }) else {
                                    throw AgentError.toolNotFound(toolCall.tool)
                                }

                                do {
                                    let observation = try await tool.execute(
                                        toolCall.input,
                                        context: invocationContext
                                    )
                                    self.logger.debug("Tool execution result: \(observation.prefix(100))...")

                                    if toolCall.tool == self.finalAnswerToolName {
                                        self.logger.info("Final answer tool executed after \(thoughtCount) thought(s)")
                                        continuation.yield(.content(ChatMessageContent(
                                            role: .assistant,
                                            content: observation,
                                            files: accumulatedFiles,
                                            usage: lastUsage
                                        )))
                                        continuation.finish()
                                        return
                                    }

                                    // Emit observation (action needs observation)
                                    await self.emitObservation(
                                        stepNumber: thoughtCount,
                                        content: "Observation: \(observation)",
                                        onStep: onStep
                                    )

                                    // Add thought and observation to context
                                    context.append(ChatMessageContent(role: .assistant, content: thoughtContent))
                                    context.append(ChatMessageContent(role: .system, content: "Observation: \(observation)"))

                                } catch {
                                    let errorMsg = "Tool execution failed: \(error.localizedDescription)"
                                    self.logger.error("\(errorMsg)")

                                    // Emit error observation
                                    await self.emitObservation(
                                        stepNumber: thoughtCount,
                                        content: "Error: \(errorMsg)",
                                        onStep: onStep
                                    )

                                    context.append(ChatMessageContent(role: .assistant, content: thoughtContent))
                                    // Add error to context
                                    context.append(ChatMessageContent(role: .system, content: errorMsg))
                                }

                                continue

                            case .finalAnswer(let answer):
                                self.logger.info("Final answer directive after \(thoughtCount) thought(s)")

                                let actionInput = self.makeFinalAnswerInput(answer)
                                let actionStep = AgentStep(
                                    stepNumber: thoughtCount,
                                    type: .action,
                                    content: "Action: \(self.finalAnswerToolName)\nInput: \(actionInput)"
                                )
                                await onStep(actionStep)

                                guard let tool = tools.first(where: { $0.name == self.finalAnswerToolName }) else {
                                    throw AgentError.toolNotFound(self.finalAnswerToolName)
                                }

                                let observation = try await tool.execute(
                                    actionInput,
                                    context: invocationContext
                                )
                                self.logger.debug("Final answer tool result: \(observation.prefix(100))...")

                                continuation.yield(.content(ChatMessageContent(
                                    role: .assistant,
                                    content: observation,
                                    files: accumulatedFiles,
                                    usage: lastUsage
                                )))
                                continuation.finish()
                                return

                            case .plan(let textContent):
                                self.logger.debug("Next step: plan")

                                let step = AgentStep(
                                    stepNumber: thoughtCount,
                                    type: .plan,
                                    content: textContent
                                )
                                await onStep(step)

                                // Add thought and step to context
                                context.append(ChatMessageContent(role: .assistant, content: thoughtContent))
                                context.append(ChatMessageContent(role: .assistant, content: "Plan: \(textContent)"))

                                continue

                            case .reflection(let textContent):
                                self.logger.debug("Next step: reflection")

                                let step = AgentStep(
                                    stepNumber: thoughtCount,
                                    type: .reflection,
                                    content: textContent
                                )
                                await onStep(step)

                                // Add thought and step to context
                                context.append(ChatMessageContent(role: .assistant, content: thoughtContent))
                                context.append(ChatMessageContent(role: .assistant, content: "Reflection: \(textContent)"))

                                continue
                            }
                        } else {
                            // No specific action detected - yield as final answer
                            self.logger.info("No specific action detected after \(thoughtCount) thought(s), treating as final answer")
                            self.logger.debug("Content: \(thoughtContent.prefix(200))")
                            continuation.yield(.content(ChatMessageContent(
                                role: .assistant,
                                content: thoughtContent,
                                files: accumulatedFiles,
                                usage: lastUsage
                            )))
                            continuation.finish()
                            return
                        }
                    }

                    throw AgentError.maxThoughtsReached
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Request a thought step from LLM
    /// Returns a stream of ChatMessageContent chunks (accumulating content over time)
    @MainActor
    private func requestThought<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        context: [ChatMessageContent],
        stream: Bool,
        thoughtNumber: Int,
        metadata: Metadata?,
        onStep: @escaping  (AgentStep) async -> Void
    ) async throws -> AsyncThrowingStream<ChatMessageContent, Error> {
        if stream {
            // Streaming mode - return a stream that yields accumulated chunks
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let responseStream: AsyncThrowingStream<StreamChatResponse, Error> = try await self.llmProvider.streamChat(
                            model: model,
                            messages: context,
                            metadata: metadata
                        )

                        var accumulatedMessage: ChatMessageContent?
                        var streamStepId: UUID? = nil
                        var creditsResult: CreditsResult?

                        for try await result in responseStream {
                            switch result {
                                case .message(let chunk):
                                    if let existing = accumulatedMessage {
                                        // Accumulate content and files
                                        let newContent = (existing.content ?? "") + (chunk.content ?? "")
                                        let newFiles = (existing.files ?? []) + (chunk.files ?? [])
                                        accumulatedMessage = ChatMessageContent(
                                            id: existing.id,
                                            role: existing.role,
                                            content: newContent,
                                            files: newFiles,
                                            usage: creditsResult
                                        )
                                    } else {
                                        // First chunk
                                        accumulatedMessage = ChatMessageContent(
                                            id: chunk.id,
                                            role: chunk.role,
                                            content: chunk.content,
                                            files: chunk.files ?? [],
                                            usage: creditsResult
                                        )
                                    }

                                    guard let message = accumulatedMessage, let content = message.content else { continue }

                                    // Emit/update thought step in real-time
                                    // Truncate thought content at first action keyword to avoid duplication
                                    let thoughtContent = self.truncateAtActionKeyword(content)

                                    let thoughtStep = AgentStep(
                                        id: streamStepId ?? UUID(),
                                        stepNumber: thoughtNumber,
                                        type: .thought,
                                        content: thoughtContent
                                    )
                                    if streamStepId == nil {
                                        streamStepId = thoughtStep.id
                                    }
                                    await onStep(thoughtStep)

                                    // Yield the accumulated message
                                    continuation.yield(message)

                                case .settlement(let credits):
                                    creditsResult = credits
                                    // Update accumulated message with usage
                                    if var message = accumulatedMessage {
                                        message.usage = credits
                                        accumulatedMessage = message
                                        continuation.yield(message)
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
            // Non-streaming mode - return a stream that yields once
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let result = try await self.llmProvider.chat(
                            model: model,
                            messages: context,
                            metadata: metadata
                        )

                        guard let message = result.data else {
                            if let error = result.error {
                                throw AgentError.toolExecutionFailed(error.message)
                            }
                            throw AgentError.toolExecutionFailed("No response from LLM")
                        }

                        guard let content = message.content, !content.isEmpty else {
                            throw AgentError.toolExecutionFailed("Empty response from LLM")
                        }

                        // Always emit thought step for non-streaming mode
                        let thoughtStep = AgentStep(
                            stepNumber: thoughtNumber,
                            type: .thought,
                            content: content
                        )
                        await onStep(thoughtStep)

                        continuation.yield(message)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// Helper to emit observation step
    @MainActor
    private func emitObservation(
        stepNumber: Int,
        content: String,
        onStep:  (AgentStep) async -> Void
    ) async {
        let observationStep = AgentStep(
            stepNumber: stepNumber,
            type: .observation,
            content: content
        )
        await onStep(observationStep)
    }

    /// Truncate content at first action keyword to prevent duplication in streaming
    private func truncateAtActionKeyword(_ text: String) -> String {
        let keywords = ["Action:", "Plan:", "Reflection:"]

        var earliestRange: Range<String.Index>? = nil

        for keyword in keywords {
            if let range = text.range(of: keyword) {
                if earliestRange == nil || range.lowerBound < earliestRange!.lowerBound {
                    earliestRange = range
                }
            }
        }

        guard let range = earliestRange else {
            return text
        }

        // Return content before the keyword, trimmed
        return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse thought response to determine next directive
    /// Always tries to parse all possible formats based on actual content
    private func parseThoughtResponse(_ text: String) -> AgentDirective? {
        // Priority 1: Check for each step type based on actual content
        // Order matters: final_answer action > action > plan > reflection
        if let toolCall = parseToolCall(from: text) {
            if toolCall.tool == finalAnswerToolName,
               let answer = parseFinalAnswerInput(toolCall.input) {
                return .finalAnswer(answer)
            }
            return .action(toolCall)
        }

        if let plan = parsePlan(from: text) {
            return .plan(plan)
        }

        if let reflection = parseReflection(from: text) {
            return .reflection(reflection)
        }

        // Priority 3: Unknown - no specific action detected
        return nil
    }

    private func parseFinalAnswerInput(_ input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = json["answer"] as? String,
              !answer.isEmpty else {
            return nil
        }
        return answer
    }

    private func makeFinalAnswerInput(_ answer: String) -> String {
        let payload: [String: Any] = ["answer": answer]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        let escaped = answer.replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"answer\":\"\(escaped)\"}"
    }

    /// Parse tool call from LLM response
    private func parseToolCall(from text: String) -> ToolCall? {
        let lines = text.components(separatedBy: "\n")

        var action: String?
        var input: String?

        for line in lines {
            if line.hasPrefix("Action:") {
                action = line.replacingOccurrences(of: "Action:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Input:") {
                input = line.replacingOccurrences(of: "Input:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        guard let action = action, let input = input else {
            return nil
        }

        return ToolCall(tool: action, input: input)
    }

    /// Parse plan from LLM response
    private func parsePlan(from text: String) -> String? {
        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            if line.hasPrefix("Plan:") {
                let plan = line.replacingOccurrences(of: "Plan:", with: "").trimmingCharacters(in: .whitespaces)

                if !plan.isEmpty {
                    let remainingLines = lines[(index + 1)...].joined(separator: "\n")
                    if !remainingLines.isEmpty {
                        return plan + "\n" + remainingLines
                    }
                    return plan
                }

                let remainingLines = lines[(index + 1)...].joined(separator: "\n")
                return remainingLines.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    /// Parse reflection from LLM response
    private func parseReflection(from text: String) -> String? {
        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            if line.hasPrefix("Reflection:") {
                let reflection = line.replacingOccurrences(of: "Reflection:", with: "").trimmingCharacters(in: .whitespaces)

                if !reflection.isEmpty {
                    let remainingLines = lines[(index + 1)...].joined(separator: "\n")
                    if !remainingLines.isEmpty {
                        return reflection + "\n" + remainingLines
                    }
                    return reflection
                }

                let remainingLines = lines[(index + 1)...].joined(separator: "\n")
                return remainingLines.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    /// Direct chat without agent steps
    /// This is used when agentConfig.allowedSteps is empty
    /// Always returns a stream (yields chunks if streaming, or yields once if not)
    private func directChat<Metadata: Codable & Equatable & Sendable>(
        model: SupportedModel,
        context: [ChatMessageContent],
        stream: Bool,
        metadata: Metadata?
    ) async throws -> AsyncThrowingStream<ChatMessage, Error> {
        if stream {
            // Streaming mode - convert StreamChatResponse to ChatMessage
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let responseStream = try await self.llmProvider.streamChat(
                            model: model,
                            messages: context,
                            metadata: metadata
                        )

                        var accumulatedMessage: ChatMessageContent?
                        var creditsResult: CreditsResult?

                        for try await result in responseStream {
                            switch result {
                                case .message(let chunk):
                                    if let existing = accumulatedMessage {
                                        // Accumulate content and files
                                        let newContent = (existing.content ?? "") + (chunk.content ?? "")
                                        let newFiles = (existing.files ?? []) + (chunk.files ?? [])
                                        accumulatedMessage = ChatMessageContent(
                                            id: existing.id,
                                            role: existing.role,
                                            content: newContent,
                                            files: newFiles,
                                            usage: creditsResult
                                        )
                                    } else {
                                        // First chunk
                                        accumulatedMessage = chunk
                                    }

                                    // Yield the accumulated message
                                    if let message = accumulatedMessage {
                                        continuation.yield(.content(message))
                                    }

                                case .settlement(let credits):
                                    creditsResult = credits
                                    // Update accumulated message with usage
                                    if var message = accumulatedMessage {
                                        message.usage = credits
                                        accumulatedMessage = message
                                        continuation.yield(.content(message))
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
            // Non-streaming mode - return a stream that yields once
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let result = try await self.llmProvider.chat(
                            model: model,
                            messages: context,
                            metadata: metadata
                        )

                        guard let message = result.data else {
                            if let error = result.error {
                                throw AgentError.toolExecutionFailed(error.message)
                            }
                            throw AgentError.toolExecutionFailed("No response from LLM")
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
