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

private struct ParsedDecision {
    let directive: AgentDirective
    let title: String?
}

public struct EmptyMetadata: ContentModel {
    public init() {}
}

/// Agent executor that handles execution based on configuration
public final class AgentExecutor: Sendable {
    private let logger = Logger(label: "AgentExecutor")
    private let llmProvider: LLMProvider
    private let toolRegistry: ToolRegistry

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
                        var lastStreamedFinalAnswer: String?
                        var streamedFinalAnswerId: String?

                        for try await chunk in thoughtStream {
                            thoughtMessage = chunk

                            guard canStream, let content = chunk.content else {
                                continue
                            }

                            if let answerContent = self.extractFinalAnswerFromPartialJSON(content),
                               answerContent != lastStreamedFinalAnswer {
                                lastStreamedFinalAnswer = answerContent
                                let messageId = streamedFinalAnswerId ?? chunk.id
                                streamedFinalAnswerId = messageId
                                continuation.yield(.content(ChatMessageContent(
                                    id: messageId,
                                    role: .assistant,
                                    content: answerContent,
                                    files: chunk.files ?? [],
                                    usage: chunk.usage
                                )))
                            }
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

                        let rawContent = finalMessage.content ?? ""
                        let thoughtContent = self.extractReasoning(from: rawContent) ?? rawContent

                        // Step 2: Parse the thought response
                        self.logger.debug("Thought content (first 200 chars): \(rawContent.prefix(200))")
                        let response = self.parseThoughtResponse(rawContent)

                        // Step 3: Handle the directive
                        if let response {
                            switch response.directive {
                            case .action(let toolCall):
                                self.logger.debug("Next step: action")

                                // Emit action step
                                let actionStep = AgentStep(
                                    stepNumber: thoughtCount,
                                    type: .action,
                                    content: "Action: \(toolCall.tool)\nInput: \(toolCall.input)",
                                    title: response.title
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
                                continuation.yield(.content(ChatMessageContent(
                                    id: finalMessage.id,
                                    role: .assistant,
                                    content: answer,
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
                                    content: textContent,
                                    title: response.title
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
                                    content: textContent,
                                    title: response.title
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
                                id: finalMessage.id,
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
                                    if let thoughtContent = self.extractReasoning(from: content) {
                                        let thoughtTitle = self.extractTitle(from: content)
                                        let thoughtStep = AgentStep(
                                            id: streamStepId ?? UUID(),
                                            stepNumber: thoughtNumber,
                                            type: .thought,
                                            content: thoughtContent,
                                            title: thoughtTitle
                                        )
                                        if streamStepId == nil {
                                            streamStepId = thoughtStep.id
                                        }
                                        await onStep(thoughtStep)
                                    }

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

                        let thoughtContent = self.extractReasoning(from: content) ?? content
                        let thoughtTitle = self.extractTitle(from: content)
                        // Always emit thought step for non-streaming mode
                        let thoughtStep = AgentStep(
                            stepNumber: thoughtNumber,
                            type: .thought,
                            content: thoughtContent,
                            title: thoughtTitle
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

    private func extractReasoning(from text: String) -> String? {
        if let jsonText = extractJSONObject(from: text[text.startIndex...]),
           let data = jsonText.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let reasoning = json["reasoning"] as? String,
           !reasoning.isEmpty {
            return reasoning
        }

        return extractReasoningFromPartialJSON(text)
    }

    private func extractTitle(from text: String) -> String? {
        if let jsonText = extractJSONObject(from: text[text.startIndex...]),
           let data = jsonText.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let decision = json["decision"] as? [String: Any]
            let title = (json["title"] as? String) ?? (decision?["title"] as? String)
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == true ? nil : trimmed
        }

        return extractTitleFromPartialJSON(text)
    }

    private func extractReasoningFromPartialJSON(_ text: String) -> String? {
        extractStringValueFromPartialJSON(text[text.startIndex...], key: "\"reasoning\"")
    }

    private func extractTitleFromPartialJSON(_ text: String) -> String? {
        guard let rawTitle = extractStringValueFromPartialJSON(text[text.startIndex...], key: "\"title\"") else {
            return nil
        }

        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func extractFinalAnswerFromPartialJSON(_ text: String) -> String? {
        guard let decisionRange = text.range(of: "\"decision\"") else {
            return nil
        }

        let decisionText = text[decisionRange.upperBound...]
        guard let typeValue = extractStringValueFromPartialJSON(decisionText, key: "\"type\"") else {
            return nil
        }

        let normalizedType = typeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedType == "final_answer" else {
            return nil
        }

        return extractStringValueFromPartialJSON(decisionText, key: "\"content\"")
    }

    private func extractStringValueFromPartialJSON(_ text: Substring, key: String) -> String? {
        guard let keyRange = text.range(of: key) else {
            return nil
        }

        let afterKey = text[keyRange.upperBound...]
        guard let colonIndex = afterKey.firstIndex(of: ":") else {
            return nil
        }

        var index = afterKey.index(after: colonIndex)
        while index < afterKey.endIndex, afterKey[index].isWhitespace {
            index = afterKey.index(after: index)
        }

        guard index < afterKey.endIndex, afterKey[index] == "\"" else {
            return nil
        }

        index = afterKey.index(after: index)
        var result = ""
        var escaped = false
        var current = index

        while current < afterKey.endIndex {
            let character = afterKey[current]
            if escaped {
                switch character {
                case "n":
                    result.append("\n")
                case "t":
                    result.append("\t")
                case "r":
                    result.append("\r")
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                default:
                    result.append(character)
                }
                escaped = false
            } else {
                if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    return result
                } else {
                    result.append(character)
                }
            }
            current = afterKey.index(after: current)
        }

        return result
    }

    /// Parse thought response to determine next directive
    /// Always tries to parse all possible formats based on actual content
    private func parseThoughtResponse(_ text: String) -> ParsedDecision? {
        // Priority 1: Check for each step type based on actual content
        // Order matters: decision JSON
        if let directive = parseDecisionJSON(from: text) {
            return directive
        }

        // Priority 3: Unknown - no specific action detected
        return nil
    }

    private func parseDecisionJSON(from text: String) -> ParsedDecision? {
        guard let jsonText = extractJSONObject(from: text[text.startIndex...]) else {
            return nil
        }

        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let decision = root["decision"] as? [String: Any],
              let type = decision["type"] as? String else {
            return nil
        }

        let titleValue = (root["title"] as? String) ?? (decision["title"] as? String)
        let title = titleValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = (title?.isEmpty ?? true) ? nil : title

        func makeDecision(_ directive: AgentDirective) -> ParsedDecision {
            ParsedDecision(directive: directive, title: normalizedTitle)
        }

        switch type {
        case "action":
            guard let tool = decision["tool"] as? String else {
                return nil
            }
            let inputValue = decision["input"] ?? [:]
            guard let inputText = encodeJSONValue(inputValue) else {
                return nil
            }
            return makeDecision(.action(ToolCall(tool: tool, input: inputText)))

        case "plan":
            guard let content = decision["content"] as? String else {
                return nil
            }
            return makeDecision(.plan(content))

        case "reflection":
            guard let content = decision["content"] as? String else {
                return nil
            }
            return makeDecision(.reflection(content))

        case "final_answer":
            guard let content = decision["content"] as? String else {
                return nil
            }
            return makeDecision(.finalAnswer(content))

        default:
            return nil
        }
    }

    private func encodeJSONValue(_ value: Any) -> String? {
        if let value = value as? String {
            return value
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func extractJSONObject(from text: Substring) -> String? {
        guard let startIndex = text.firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var endIndex: String.Index? = nil
        var index = startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    endIndex = index
                    break
                }
            }
            index = text.index(after: index)
        }

        guard let endIndex else {
            return nil
        }

        return String(text[startIndex...endIndex])
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
