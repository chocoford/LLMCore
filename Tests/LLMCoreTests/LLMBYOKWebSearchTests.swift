import Foundation
import Testing
@testable import LLMCore

@Suite("Explicit upstream search options")
struct LLMBYOKWebSearchTests {
    @Test("Supported presets opt in without changing model IDs or local tools", arguments: [
        LLMBYOKPreset.openRouter, .openAI, .dashScope, .dashScopeInternational, .groq
    ])
    func requestAdapters(preset: LLMBYOKPreset) throws {
        let original = preset.configuration
        let enabled = try original.withWebSearch()
        #expect(original.webSearch == nil)
        #expect(enabled.webSearch?.isEnabled == true)
        #expect(enabled.preset == preset && enabled.hasSameConnection(as: original))
        let tool = ToolSchema(name: "draw", description: "Local", parameters: .init(["type": "object"]))
        let data = try LLMChatCompletionsCodec.encode(model: "future-model", messages: [.init(role: .user, content: "News")],
            tools: [tool], configuration: enabled, stream: true)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["model"] as? String == "future-model" && payload["stream"] as? Bool == true)
        #expect(payload["tool_choice"] == nil && payload["plugins"] == nil)
        let tools = try #require(payload["tools"] as? [[String: Any]])
        #expect((tools.first?["function"] as? [String: Any])?["name"] as? String == "draw")
        switch try #require(enabled.webSearch?.adapter) {
        case .openRouter: #expect(tools.count == 2 && tools.last?["type"] as? String == "openrouter:web_search")
        case .openAI: #expect(tools.count == 1 && payload["web_search_options"] as? [String: Any] != nil)
        case .dashScope: #expect(tools.count == 1 && payload["enable_search"] as? Bool == true)
        case .groq: #expect(tools.count == 2 && tools.last?["type"] as? String == "browser_search")
        }
        let disabled = try enabled.withWebSearch(enabled: false)
        let plain = try LLMChatCompletionsCodec.encode(model: "future-model", messages: [], tools: nil,
            configuration: disabled, stream: false)
        let plainPayload = try #require(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        #expect(plainPayload["tools"] == nil && plainPayload["web_search_options"] == nil && plainPayload["enable_search"] == nil)
        let restored = try JSONDecoder().decode(LLMBYOKConfiguration.self, from: JSONEncoder().encode(enabled))
        #expect(restored == enabled)
    }

    @Test("Connection identity ignores only the invocation search option")
    func connectionIdentity() throws {
        let original = LLMBYOKConfiguration.openRouter
        let enabled = try original.withWebSearch()
        var changed = enabled
        changed.baseURL = URL(string: "https://untrusted.example/v1/")!
        #expect(!changed.hasSameConnection(as: original))
        #expect(changed.preset == nil)
        let encoded = try JSONEncoder().encode(original)
        let old = try JSONDecoder().decode(LLMBYOKConfiguration.self, from: encoded)
        #expect(old.webSearch == nil && old.webSearchAdapter == .openRouter)
        #expect(try old.withWebSearch() == enabled)
    }

    @Test("Unsupported presets fail explicitly while custom gateways choose a wire adapter")
    func unsupportedAndCustom() throws {
        for preset in LLMBYOKPreset.allCases where preset.webSearchAdapter == nil {
            #expect(throws: LLMBYOKWebSearchError.self) { _ = try preset.configuration.withWebSearch() }
            #expect(try preset.configuration.withWebSearch(enabled: false) == preset.configuration)
        }
        let custom = LLMBYOKConfiguration(baseURL: URL(string: "https://gateway.example/v1/")!,
            webSearch: .init(adapter: .dashScope))
        let enabled = try custom.withWebSearch()
        try enabled.validate()
        #expect(enabled.webSearch?.isEnabled == true && enabled.preset == nil)
    }

    @Test("App-visible execution behavior does not promise optional search on specialized OpenAI models")
    func executionBehavior() {
        #expect(LLMBYOKWebSearch.Adapter.openRouter.executionBehavior == .modelDecides)
        #expect(LLMBYOKWebSearch.Adapter.openAI.executionBehavior == .alwaysSearch)
        #expect(LLMBYOKWebSearch.Adapter.dashScope.executionBehavior == .providerDefined)
        #expect(LLMBYOKWebSearch.Adapter.groq.executionBehavior == .providerDefined)
    }
}
