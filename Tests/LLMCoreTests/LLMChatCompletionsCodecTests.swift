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

    @Test("OpenRouter usage tails repeat the finish reason without emitting another message", arguments: ["stop", "tool_calls"])
    func openRouterUsageTail(reason: String) throws {
        let delta: [String: Any] = reason == "stop"
            ? ["content": "Hi"]
            : ["tool_calls": [["index": 0, "id": "a", "type": "function", "function": ["name": "draw", "arguments": "{}"]]]]
        let terminal = try JSONSerialization.data(withJSONObject: [
            "id": "r", "choices": [["index": 0, "delta": delta, "finish_reason": reason]]
        ])
        for emptyDelta in [
            #"{}"#,
            #"{"role":"assistant","content":""}"#,
            #"{"role":null,"content":null}"#,
            #"{"content":"","refusal":null,"tool_calls":[],"reasoning":null,"reasoning_details":[]}"#
        ] {
            let tail = #"{"id":"r","choices":[{"index":0,"delta":\#(emptyDelta),"finish_reason":"\#(reason)","native_finish_reason":"\#(reason)"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#
            let wire = "data: \(String(decoding: terminal, as: UTF8.self))\n\ndata: \(tail)\n\ndata: [DONE]\n\n"
            var frames = LLMChatCompletionsFrames()
            var accumulator = LLMChatCompletionsAccumulator()
            var messages: [ChatMessageContent] = []
            for byte in wire.utf8 {
                if case .data(let data) = try frames.append(byte), let message = try accumulator.append(data) {
                    messages.append(message)
                }
            }
            try frames.validateEnd()
            try accumulator.validateEnd()
            #expect(messages.count == 1)
            #expect(messages.first?.content == (reason == "stop" ? "Hi" : nil))
            #expect(messages.first?.toolCalls?.first?.arguments == (reason == "tool_calls" ? "{}" : nil))
            #expect(accumulator.usage?.promptTokens == 1)
            #expect(accumulator.usage?.completionTokens == 2)
            #expect(accumulator.usage?.totalTokens == 3)
        }
    }

    @Test("After finishing, only content-free accounting for the same response is accepted", arguments: [
        #"{"id":"other","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":1,"delta":{},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{},"finish_reason":null}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{"role":"user"},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{"content":"extra"},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{"refusal":"extra"},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"}"}}]},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{"images":[{}]},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{"audio":{}},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{"reasoning":"extra"},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{},"message":{"content":"extra"},"finish_reason":"stop"}]}"#,
        #"{"id":"r","choices":[{"index":0,"delta":{},"finish_reason":"stop"},{"index":1,"delta":{},"finish_reason":"stop"}]}"#
    ])
    func invalidUsageTail(payload: String) throws {
        var accumulator = LLMChatCompletionsAccumulator()
        _ = try accumulator.append(Data(#"{"id":"r","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#.utf8))
        var tail = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        // Check both a duplicate terminal event without usage and a malformed accounting tail.
        #expect(throws: (any Error).self) { _ = try accumulator.append(Data(payload.utf8)) }
        tail["usage"] = ["prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30]
        let data = try JSONSerialization.data(withJSONObject: tail)
        #expect(throws: (any Error).self) { _ = try accumulator.append(data) }
        #expect(accumulator.usage?.totalTokens == 3)
        try accumulator.validateEnd()
    }

    @Test("A usage tail does not replace DONE, a finish reason, or complete tool arguments")
    func usageTailPreservesCompletionChecks() throws {
        let tail = #"{"id":"r","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#
        let wire = "data: {\"id\":\"r\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":\"stop\"}]}\n\ndata: \(tail)\n\n"
        var frames = LLMChatCompletionsFrames()
        var accumulator = LLMChatCompletionsAccumulator()
        for byte in wire.utf8 {
            if case .data(let data) = try frames.append(byte) { _ = try accumulator.append(data) }
        }
        try accumulator.validateEnd()
        #expect(throws: (any Error).self) { try frames.validateEnd() }
        #expect(throws: (any Error).self) {
            _ = try accumulator.append(Data(#"{"id":"r","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#.utf8))
        }

        var unfinished = LLMChatCompletionsAccumulator()
        _ = try unfinished.append(Data(#"{"id":"r","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}"#.utf8))
        _ = try unfinished.append(Data(#"{"id":"r","choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#.utf8))
        #expect(throws: (any Error).self) { try unfinished.validateEnd() }

        var truncated = LLMChatCompletionsAccumulator()
        _ = try truncated.append(Data(#"{"id":"r","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"a","type":"function","function":{"name":"draw","arguments":"{\"ops\":"}}]},"finish_reason":"tool_calls"}]}"#.utf8))
        let toolTail = tail.replacingOccurrences(of: #""finish_reason":"stop""#, with: #""finish_reason":"tool_calls""#)
        #expect(try truncated.append(Data(toolTail.utf8)) == nil)
        #expect(throws: (any Error).self) { try truncated.validateEnd() }
        let repair = #"{"id":"r","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"[]}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#
        #expect(throws: (any Error).self) { _ = try truncated.append(Data(repair.utf8)) }
        #expect(throws: (any Error).self) { try truncated.validateEnd() }
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
