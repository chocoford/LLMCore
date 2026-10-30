import Foundation

/// Credential-free wire conversion for OpenAI-compatible Chat Completions.
/// Product access, transport, key storage and platform accounting do not belong here.
public enum LLMChatCompletionsError: Error, LocalizedError, Sendable, Equatable {
    case invalidResponse
    case incompleteStream
    case unsupportedCapability(String)
    case upstream(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The model service returned an invalid response."
        case .incompleteStream: return "The model response ended before successful completion."
        case .unsupportedCapability(let capability): return "Direct BYOK does not support \(capability)."
        case .upstream(let code): return "The model service rejected the request (HTTP \(code))."
        }
    }
}

public enum LLMChatCompletionsCodec {
    public static func encode(
        model: String, messages: [ChatMessageContent], tools: [ToolSchema]?,
        configuration: LLMBYOKConfiguration, stream: Bool
    ) throws -> Data {
        try configuration.validate()
        var wire: [[String: Any]] = []
        var toolNames: [String: String] = [:]
        // Images returned by tools must follow ALL tool results, not interrupt their pairing.
        var pendingImages: [[String: Any]] = []
        func flushImages() {
            if !pendingImages.isEmpty {
                wire.append(["role": "user", "content": [["type": "text", "text": "Images returned by the preceding tool calls:"]] + pendingImages])
                pendingImages = []
            }
        }
        for message in messages where !message.isCompactedOut {
            if message.role != .tool { flushImages() }
            var item: [String: Any] = ["role": message.role.rawValue]
            let images = try imageParts(message.files ?? [])
            switch message.role {
            case .assistant:
                item["content"] = message.content.map { $0 as Any } ?? NSNull()
                if let calls = message.toolCalls, !calls.isEmpty {
                    item["tool_calls"] = try calls.map { call -> [String: Any] in
                        guard !call.id.isEmpty, !call.name.isEmpty, call.hasProviderSafeArguments else {
                            throw LLMChatCompletionsError.invalidResponse
                        }
                        toolNames[call.id] = call.name
                        var value: [String: Any] = ["id": call.id, "type": "function", "function": ["name": call.name, "arguments": call.arguments]]
                        if configuration.options.preserveGoogleThoughtSignatures,
                           let signature = call.providerMetadata?["google.thought_signature"] {
                            value["extra_content"] = ["google": ["thought_signature": signature]]
                        }
                        return value
                    }
                }
                guard images.isEmpty else { throw LLMChatCompletionsError.unsupportedCapability("image generation history") }
            case .tool:
                guard let id = message.toolCallId, !id.isEmpty else { throw LLMChatCompletionsError.invalidResponse }
                item["tool_call_id"] = id
                item["content"] = message.content ?? ""
                if configuration.options.preserveGoogleThoughtSignatures, let name = toolNames[id] { item["name"] = name }
                pendingImages += images
            case .user:
                item["content"] = images.isEmpty ? (message.content ?? "") as Any
                    : [["type": "text", "text": message.content ?? ""]] + images
            case .system, .developer:
                guard images.isEmpty else { throw LLMChatCompletionsError.unsupportedCapability("images in system messages") }
                item["content"] = message.content ?? ""
            }
            wire.append(item)
        }
        flushImages()
        var payload: [String: Any] = ["model": try configuration.modelMapping.resolve(model), "messages": wire, "stream": stream]
        if let tools, !tools.isEmpty {
            payload["tools"] = try tools.map { tool -> [String: Any] in
                let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tool.parameters))
                guard let schema = object as? [String: Any] else { throw LLMChatCompletionsError.invalidResponse }
                return ["type": "function", "function": ["name": tool.name, "description": tool.description, "parameters": normalizeSchema(schema)]]
            }
        }
        let options = configuration.options
        if stream && options.includeUsage { payload["stream_options"] = ["include_usage": true] }
        if options.sendStoreFalse { payload["store"] = false }
        if let limit = options.outputTokenLimit { payload[options.tokenLimitParameter.rawValue] = limit }
        if options.openRouterExtensions { payload["usage"] = ["include": true] }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    public static func decode(_ data: Data) throws -> APIResponse<ChatMessageContent> {
        let envelope = try decodeEnvelope(data)
        guard envelope.choices.count == 1, let choice = envelope.choices.first, choice.index == 0,
              let message = choice.message, message.role == nil || message.role == "assistant" else {
            throw LLMChatCompletionsError.invalidResponse
        }
        try validateFinish(choice.finish_reason)
        try message.validateCapabilities()
        let calls = try message.tool_calls?.map { try $0.completeCall() }
        try validateCalls(calls, finish: choice.finish_reason)
        guard message.content != nil || message.refusal != nil || calls?.isEmpty == false else {
            throw LLMChatCompletionsError.invalidResponse
        }
        return .init(data: .init(id: envelope.id, role: .assistant, content: message.content ?? message.refusal, toolCalls: calls), usage: envelope.usage?.value, credits: nil)
    }

    static func imageParts(_ files: [ChatMessageContent.File]) throws -> [[String: Any]] {
        try files.map { file in
            let value: String
            switch file {
            case .base64EncodedImage(let data):
                guard data.hasPrefix("data:image/"), data.contains(";base64,"), data.utf8.count <= 32 * 1024 * 1024 else {
                    throw LLMChatCompletionsError.unsupportedCapability("invalid or oversized inline image")
                }
                value = data
            case .image(let url):
                guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else {
                    throw LLMChatCompletionsError.unsupportedCapability("non-HTTPS or unprepared local image")
                }
                value = url.absoluteString
            }
            return ["type": "image_url", "image_url": ["url": value]]
        }
    }

    private static func normalizeSchema(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
            object = object.mapValues(normalizeSchema)
            if object["type"] as? String == "array", object["items"] == nil || object["items"] is NSNull { object["items"] = ["type": "string"] }
            return object
        }
        if let array = value as? [Any] { return array.map(normalizeSchema) }
        return value
    }

    static func validateFinish(_ reason: String?) throws {
        // Never execute apparently valid but token-truncated tool calls.
        guard reason == "stop" || reason == "tool_calls" else { throw LLMChatCompletionsError.incompleteStream }
    }

    static func validateCalls(_ calls: [ToolCall]?, finish: String?) throws {
        let values = calls ?? []
        guard Set(values.map(\.id)).count == values.count,
              (finish == "tool_calls") == !values.isEmpty else { throw LLMChatCompletionsError.invalidResponse }
        for call in values {
            guard !call.id.isEmpty, !call.name.isEmpty, call.hasProviderSafeArguments else { throw LLMChatCompletionsError.invalidResponse }
        }
    }

    static func decodeEnvelope(_ data: Data) throws -> Envelope {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] != nil {
            throw LLMChatCompletionsError.upstream(502)
        }
        guard let value = try? JSONDecoder().decode(Envelope.self, from: data), !value.id.isEmpty else { throw LLMChatCompletionsError.invalidResponse }
        return value
    }

    struct Envelope: Decodable {
        let id: String
        let choices: [Choice]
        let usage: TokenUsage?
    }
    struct Choice: Decodable {
        let index: Int
        let message: Message?
        let delta: Message?
        let finish_reason: String?
    }
    struct TokenUsage: Decodable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
        var value: Usage { .init(promptTokens: prompt_tokens, completionTokens: completion_tokens, totalTokens: total_tokens) }
    }
    struct Message: Decodable {
        let role: String?
        let content: String?
        let refusal: String?
        let tool_calls: [Call]?
        let images: [Image]?
        let audio: Image?
        // Presence matters; do not silently drop a provider-specific output modality.
        struct Image: Decodable {}
        func validateCapabilities() throws {
            if images?.isEmpty == false || audio != nil { throw LLMChatCompletionsError.unsupportedCapability("generated image/audio output") }
        }
    }
    struct Call: Decodable {
        let index: Int?
        let id: String?
        let type: String?
        let function: Function?
        let extra_content: Extra?
        struct Function: Decodable { let name: String?; let arguments: String? }
        struct Extra: Decodable { let google: Google?; struct Google: Decodable { let thought_signature: String? } }
        func completeCall() throws -> ToolCall {
            guard type == nil || type == "function", let id, let name = function?.name, let arguments = function?.arguments else { throw LLMChatCompletionsError.invalidResponse }
            return .init(id: id, name: name, arguments: arguments, providerMetadata: extra_content?.google?.thought_signature.map { ["google.thought_signature": $0] })
        }
    }
}

/// Produces cumulative snapshots, matching LLMProvider's Agent tool-call contract.
public struct LLMChatCompletionsAccumulator {
    private var message = ChatMessageContent(role: .assistant)
    private var calls: [Int: ToolCall] = [:]
    private var finishReason: String?
    private var responseID: String?
    private var receivedBytes = 0
    public private(set) var usage: Usage?

    public init() {}

    public mutating func append(_ data: Data) throws -> ChatMessageContent? {
        receivedBytes += data.count
        guard receivedBytes <= 16 * 1024 * 1024 else { throw LLMChatCompletionsError.invalidResponse }
        let envelope = try LLMChatCompletionsCodec.decodeEnvelope(data)
        if let responseID, responseID != envelope.id { throw LLMChatCompletionsError.invalidResponse }
        responseID = envelope.id
        message.id = envelope.id
        if let value = envelope.usage { usage = value.value }
        guard !envelope.choices.isEmpty else {
            guard envelope.usage != nil else { throw LLMChatCompletionsError.invalidResponse }
            return nil
        }
        guard envelope.choices.count == 1, let choice = envelope.choices.first, choice.index == 0,
              let delta = choice.delta, finishReason == nil else { throw LLMChatCompletionsError.invalidResponse }
        try delta.validateCapabilities()
        guard delta.role == nil || delta.role == "assistant" else { throw LLMChatCompletionsError.invalidResponse }
        if let text = delta.content ?? delta.refusal { message.content = (message.content ?? "") + text }
        for part in delta.tool_calls ?? [] {
            guard let index = part.index, (0..<128).contains(index), part.type == nil || part.type == "function" else { throw LLMChatCompletionsError.invalidResponse }
            var call = calls[index] ?? .init(id: "", name: "", arguments: "")
            if let id = part.id {
                guard call.id.isEmpty || call.id == id else { throw LLMChatCompletionsError.invalidResponse }
                call.id = id
            }
            if let name = part.function?.name { call.name += name }
            if let arguments = part.function?.arguments { call.arguments += arguments }
            guard call.arguments.utf8.count <= 4 * 1024 * 1024 else { throw LLMChatCompletionsError.invalidResponse }
            if let signature = part.extra_content?.google?.thought_signature { call.providerMetadata = ["google.thought_signature": signature] }
            calls[index] = call
        }
        if !calls.isEmpty { message.toolCalls = calls.keys.sorted().compactMap { calls[$0] } }
        if let reason = choice.finish_reason { try LLMChatCompletionsCodec.validateFinish(reason); finishReason = reason }
        return message
    }

    public func validateEnd() throws {
        try LLMChatCompletionsCodec.validateFinish(finishReason)
        try LLMChatCompletionsCodec.validateCalls(message.toolCalls, finish: finishReason)
        guard message.content != nil || !calls.isEmpty else { throw LLMChatCompletionsError.invalidResponse }
    }
}

/// Strict byte framing for upstream SSE; EOF is never implicit success by default.
public struct LLMChatCompletionsFrames {
    public enum Frame { case data(Data), done }
    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var event: String?
    private var previousCR = false
    public private(set) var isComplete = false
    public init() {}

    public mutating func append(_ byte: UInt8) throws -> Frame? {
        guard !isComplete else {
            guard [9, 10, 13, 32].contains(byte) else { throw LLMChatCompletionsError.invalidResponse }
            return nil
        }
        if previousCR { previousCR = false; if byte == 10 { return nil } }
        if byte != 10 && byte != 13 {
            guard line.count < 8 * 1024 * 1024 else { throw LLMChatCompletionsError.invalidResponse }
            line.append(byte); return nil
        }
        previousCR = byte == 13
        guard let text = String(bytes: line, encoding: .utf8) else { throw LLMChatCompletionsError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            guard !dataLines.isEmpty else {
                guard event == nil else { throw LLMChatCompletionsError.invalidResponse }
                return nil
            }
            let payload = dataLines.joined(separator: "\n")
            let event = event
            dataLines = []; self.event = nil
            guard event == nil || event == "message" else { throw LLMChatCompletionsError.invalidResponse }
            if payload == "[DONE]" { isComplete = true; return .done }
            return .data(Data(payload.utf8))
        }
        if text.hasPrefix(":") { return nil }
        let fields = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var value = fields.count == 2 ? String(fields[1]) : ""
        if value.first == " " { value.removeFirst() }
        switch fields[0] {
        case "data":
            guard dataLines.count < 1024, dataLines.reduce(0, { $0 + $1.utf8.count }) + value.utf8.count <= 8 * 1024 * 1024 else { throw LLMChatCompletionsError.invalidResponse }
            dataLines.append(value)
        case "event": event = value
        case "id", "retry": break
        default: throw LLMChatCompletionsError.invalidResponse
        }
        return nil
    }

    public func validateEnd(requiresDoneMarker: Bool = true) throws {
        guard isComplete || !requiresDoneMarker, line.isEmpty, dataLines.isEmpty, event == nil else { throw LLMChatCompletionsError.incompleteStream }
    }
}
