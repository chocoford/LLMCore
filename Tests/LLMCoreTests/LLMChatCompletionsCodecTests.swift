import Foundation
import Testing
@testable import LLMCore

@Suite("Direct-compatible Chat Completions wire contract")
struct LLMChatCompletionsCodecTests {
    @Test("Presets and unknown model IDs reuse the same credential-free encoder", arguments: LLMBYOKPreset.allCases)
    func presets(preset: LLMBYOKPreset) throws {
        let data = try LLMChatCompletionsCodec.encode(model: "future/model:v9", messages: [.init(role: .system, content: "local prompt"), .init(role: .user, content: "hello")], tools: nil, configuration: preset.configuration, stream: true)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["model"] as? String == "future/model:v9")
        #expect(object["stream"] as? Bool == true)
        #expect(object["metadata"] == nil)
        #expect(object["agentID"] == nil)
        #expect(object["apiKey"] == nil)
        #expect(object["usage"] != nil == preset.configuration.options.openRouterExtensions)
    }

    @Test("Tool results stay paired before multimodal observations")
    func toolHistory() throws {
        let calls = [ToolCall(id: "a", name: "draw", arguments: "{}"), .init(id: "b", name: "checkpoint", arguments: "{}")]
        let data = try LLMChatCompletionsCodec.encode(model: "model", messages: [
            .init(role: .assistant, toolCalls: calls),
            .init(role: .tool, content: "drawn", files: [.base64EncodedImage("data:image/png;base64,YQ==")], toolCallId: "a"),
            .init(role: .tool, content: "saved", toolCallId: "b")
        ], tools: nil, configuration: .openAI, stream: false)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: Any]])
        #expect(messages.compactMap { $0["role"] as? String } == ["assistant", "tool", "tool", "user"])
        #expect(messages[1]["tool_call_id"] as? String == "a")
        #expect(messages[2]["tool_call_id"] as? String == "b")
    }

    @Test("Fragmented native calls are cumulative and retain Gemini continuation data")
    func fragmentedCalls() throws {
        var accumulator = LLMChatCompletionsAccumulator()
        _ = try accumulator.append(Data(#"{"id":"r","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"a","type":"function","function":{"name":"draw","arguments":"{\"ops\":"}}]},"finish_reason":null}]}"#.utf8))
        let message = try #require(try accumulator.append(Data(#"{"id":"r","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"[]}"},"extra_content":{"google":{"thought_signature":"opaque"}}}]},"finish_reason":"tool_calls"}]}"#.utf8)))
        try accumulator.validateEnd()
        #expect(message.toolCalls?.first?.arguments == #"{"ops":[]}"#)
        #expect(message.toolCalls?.first?.providerMetadata?["google.thought_signature"] == "opaque")
        let data = try LLMChatCompletionsCodec.encode(model: "gemini-model", messages: [message, .init(role: .tool, content: "ok", toolCallId: "a")], tools: nil, configuration: .gemini, stream: false)
        #expect(String(decoding: data, as: UTF8.self).contains("thought_signature"))
    }

    @Test("EOF and malformed frames never succeed", arguments: [
        "data: {broken}\n\n", "data: {}", "data: [DONE]", "data: \u{fffd}\n\n"
    ])
    func incompleteFrames(wire: String) {
        #expect(throws: (any Error).self) {
            var frames = LLMChatCompletionsFrames()
            var accumulator = LLMChatCompletionsAccumulator()
            for byte in wire.utf8 {
                if case .data(let data) = try frames.append(byte) { _ = try accumulator.append(data) }
            }
            try frames.validateEnd()
            try accumulator.validateEnd()
        }
    }

    @Test("UTF-8, CRLF, usage-only chunks and completion markers are handled strictly")
    func completeStream() throws {
        let wire = "data: {\"id\":\"r\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"你好\"},\"finish_reason\":\"stop\"}]}\r\n\r\ndata: {\"id\":\"r\",\"choices\":[],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}\n\ndata: [DONE]\n\n"
        var frames = LLMChatCompletionsFrames()
        var accumulator = LLMChatCompletionsAccumulator()
        var message: ChatMessageContent?
        for byte in wire.utf8 {
            if case .data(let data) = try frames.append(byte), let next = try accumulator.append(data) { message = next }
        }
        try frames.validateEnd()
        try accumulator.validateEnd()
        #expect(message?.content == "你好")
        #expect(accumulator.usage?.totalTokens == 3)
        #expect(message?.usage == nil)
    }

    @Test("Truncated or invalid tool calls cannot reach execution", arguments: ["length", "content_filter", "stop", "tool_calls"])
    func badToolCalls(reason: String) {
        #expect(throws: (any Error).self) {
            var accumulator = LLMChatCompletionsAccumulator()
            let data = try JSONSerialization.data(withJSONObject: ["id": "r", "choices": [["index": 0, "delta": ["tool_calls": [["index": 0, "id": "a", "function": ["name": "draw", "arguments": "{\"ops\":"]]]], "finish_reason": reason]]])
            _ = try accumulator.append(data)
            try accumulator.validateEnd()
        }
    }

    @Test("Unsupported output and provider errors are explicit and never echo response bodies")
    func unsupportedAndError() {
        for data in [
            Data(#"{"error":{"message":"secret-key"}}"#.utf8),
            Data(#"{"id":"r","choices":[{"index":0,"message":{"content":"","images":[{}]},"finish_reason":"stop"}]}"#.utf8)
        ] {
            do { _ = try LLMChatCompletionsCodec.decode(data); Issue.record("Must fail") }
            catch { #expect(!error.localizedDescription.contains("secret-key")) }
        }
    }
}
