import Foundation
import Testing
@testable import LLMCore

@Suite("Upstream metadata does not control provider capabilities")
struct LLMChatCompletionsMetadataTests {
    @Test("Presets preserve local tools and arbitrary model IDs without injecting hosted search", arguments: LLMBYOKPreset.allCases)
    func requestsDoNotConfigureSearch(preset: LLMBYOKPreset) throws {
        let configuration = preset.configuration
        let tool = ToolSchema(name: "draw", description: "Local drawing", parameters: .init(["type": "object"]))
        let data = try LLMChatCompletionsCodec.encode(model: "future-model", messages: [.init(role: .user, content: "News")],
            tools: [tool], configuration: configuration, stream: true)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["web_search_options"] == nil && payload["enable_search"] == nil && payload["plugins"] == nil)
        #expect(payload["model"] as? String == "future-model" && payload["stream"] as? Bool == true)
        let tools = try #require(payload["tools"] as? [[String: Any]])
        #expect(tools.count == 1 && tools.first?["type"] as? String == "function")
        #expect((tools.first?["function"] as? [String: Any])?["name"] as? String == "draw")
        let encoded = try JSONEncoder().encode(configuration)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["webSearch"] == nil)
        #expect(try JSONDecoder().decode(LLMBYOKConfiguration.self, from: encoded) == configuration)
    }

    @Test("Provider annotation, citation and search-result shapes normalize to safe persisted links", arguments: [
        #"{"choices":[{"message":{"annotations":[{"type":"url_citation","url_citation":{"url":"https://example.com/news","title":"News"}}]}}]}"#,
        #"{"citations":["https://example.com/news"],"choices":[]}"#,
        #"{"search_info":{"search_results":[{"url":"https://example.com/news","title":"News","index":1}]},"choices":[]}"#,
        #"{"search_results":[{"url":"https://example.com/news","title":"News"}],"choices":[]}"#
    ])
    func citations(payload: String) throws {
        let metadata = try JSONDecoder().decode(LLMChatCompletionsMetadata.self, from: Data(payload.utf8))
        var message = ChatMessageContent(id: "r", role: .assistant, content: "Answer")
        message.mergeCitations(metadata.citations)
        message.mergeCitations(metadata.citations)
        #expect(message.citations?.count == 1)
        #expect(message.citations?.first?.url.absoluteString == "https://example.com/news")
        let restored = try JSONDecoder().decode(ChatMessageContent.self, from: JSONEncoder().encode(message))
        #expect(restored.citations == message.citations)
    }

    @Test("Citation-only terminal deltas are metadata, not a second answer or completion marker")
    func streamingCitations() throws {
        let terminal = #"{"id":"r","choices":[{"index":0,"delta":{"content":"Answer"},"finish_reason":"stop"}]}"#
        let tail = #"{"id":"r","choices":[{"index":0,"delta":{"annotations":[{"type":"url_citation","url_citation":{"url":"https://example.com/news","title":"News"}}]},"finish_reason":null}]}"#
        var accumulator = LLMChatCompletionsAccumulator()
        _ = try accumulator.append(Data(terminal.utf8))
        let message = try #require(try accumulator.append(Data(tail.utf8)))
        #expect(message.content == "Answer")
        #expect(message.citations?.count == 1)
        try accumulator.validateEnd()
        var frames = LLMChatCompletionsFrames()
        for byte in "data: \(terminal)\n\ndata: \(tail)\n\n".utf8 { _ = try frames.append(byte) }
        #expect(throws: LLMChatCompletionsError.self) { try frames.validateEnd() }
        let illegal = tail.replacingOccurrences(of: #""delta":{"annotations""#, with: #""delta":{"content":"extra","annotations""#)
        #expect(throws: LLMChatCompletionsError.self) { _ = try accumulator.append(Data(illegal.utf8)) }
        #expect(accumulator.currentMessage.content == "Answer")
    }

    @Test("Unknown annotations and unsafe URLs cannot bypass post-finish output validation")
    func unsafeMetadata() throws {
        let payload = #"{"choices":[{"message":{"annotations":[{"type":"url_citation","url_citation":{"url":"javascript:alert(1)"}},{"type":"url_citation","url_citation":{"url":"https://secret@example.com/"}}]}}],"citations":["file:///tmp/a"]}"#
        #expect(try JSONDecoder().decode(LLMChatCompletionsMetadata.self, from: Data(payload.utf8)).citations.isEmpty)
        var accumulator = LLMChatCompletionsAccumulator()
        _ = try accumulator.append(Data(#"{"id":"r","choices":[{"index":0,"delta":{"content":"Answer"},"finish_reason":"stop"}]}"#.utf8))
        let tail = #"{"id":"r","choices":[{"index":0,"delta":{"annotations":[{"type":"reasoning","text":"extra"}]},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}"#
        #expect(throws: LLMChatCompletionsError.self) { _ = try accumulator.append(Data(tail.utf8)) }
    }

    @Test("Hosted tool counters are distinct from tokens and deduplicated by actual request")
    func hostedUsage() throws {
        let data = Data(#"{"id":"r","choices":[{"index":0,"message":{"role":"assistant","content":"Answer"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3,"server_tool_use_details":{"web_search_requests":2,"tool_calls_executed":2}}}"#.utf8)
        let response = try LLMChatCompletionsCodec.decode(data)
        let record = try #require(response.data?.inferenceUsage?.first)
        let summary = LLMUsageSummary([record, record])
        #expect(summary.tokens?.totalTokens == 3)
        #expect(summary.providerToolUsage?["web_search_requests"] == 2)
        #expect(summary.requestCount == 1)
        let restored = try JSONDecoder().decode(LLMInferenceUsage.self, from: JSONEncoder().encode(record))
        #expect(restored.providerToolUsage == record.providerToolUsage)
    }
}
