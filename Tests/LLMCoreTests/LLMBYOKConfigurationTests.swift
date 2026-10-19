import Foundation
import Testing
@testable import LLMCore

@Suite("Configuration-driven BYOK")
struct LLMBYOKConfigurationTests {
    @Test("Presets are ordinary, key-free configurations", arguments: LLMBYOKPreset.allCases)
    func presetRoundTrip(preset: LLMBYOKPreset) throws {
        let configuration = preset.configuration
        try configuration.validate()
        let data = try JSONEncoder().encode(configuration)
        let restored = try JSONDecoder().decode(LLMBYOKConfiguration.self, from: data)
        #expect(restored == configuration)
        #expect(restored.preset == preset)
        #expect(restored.chatCompletionsURL.path.hasSuffix("/chat/completions"))
        #expect(!String(decoding: data, as: UTF8.self).contains("apiKey"))
    }

    @Test("Custom models don't need a vendor enum")
    func customModelMapping() throws {
        let configuration = LLMBYOKConfiguration(
            baseURL: URL(string: "https://Gateway.Example.com/custom-api/v1")!,
            defaultModel: "logical-model",
            modelMapping: .init(aliases: ["logical-model": "team/model:v2"])
        )
        try configuration.validate()
        #expect(configuration.preset == nil)
        #expect(try configuration.modelMapping.resolve("logical-model") == "team/model:v2")
        #expect(configuration.chatCompletionsURL.host == "gateway.example.com")
        #expect(configuration.chatCompletionsURL.path == "/custom-api/v1/chat/completions")
    }

    @Test("Unsafe URL syntax is rejected before attaching a key", arguments: [
        "http://gateway.example.com/v1", "https://user:secret@gateway.example.com/v1",
        "https://gateway.example.com/v1?api_key=secret", "https://gateway.example.com/v1#secret",
        "https://gateway.example.com/v1/%2e%2e/private", "https://gateway.example.com/v1/../private"
    ])
    func rejectEndpointSyntax(value: String) throws {
        let url = try #require(URL(string: value))
        let configuration = LLMBYOKConfiguration(baseURL: url)
        #expect(throws: LLMBYOKConfigurationValidationError.self) { try configuration.validate() }
    }

    @Test("Unknown versions and oversized configurations fail closed")
    func invalidConfiguration() throws {
        var configuration = LLMBYOKConfiguration.openAI
        configuration.version = 2
        #expect(throws: LLMBYOKConfigurationValidationError.self) { try configuration.validate() }
        configuration = .init(baseURL: URL(string: "https://gateway.example.com/v1")!, modelMapping: .init(aliases: ["m": String(repeating: "a", count: 5000)]))
        #expect(throws: LLMBYOKConfigurationValidationError.self) { try configuration.validate() }
    }

    @Test("A minimal configuration uses protocol defaults")
    func minimalConfiguration() throws {
        let data = Data(#"{"baseURL":"https://gateway.example.com/v1/"}"#.utf8)
        let configuration = try JSONDecoder().decode(LLMBYOKConfiguration.self, from: data)
        try configuration.validate()
        #expect(configuration.apiFormat == .chatCompletions)
        #expect(configuration.options.requiresDoneMarker)
        #expect(configuration.modelMapping.aliases.isEmpty)
    }

    @Test("Partial nested settings inherit protocol defaults")
    func partialOptions() throws {
        let data = Data(#"{"baseURL":"https://gateway.example.com/v1/","modelMapping":{"aliases":{"logical":"actual"}},"options":{"includeUsage":false}}"#.utf8)
        let configuration = try JSONDecoder().decode(LLMBYOKConfiguration.self, from: data)
        try configuration.validate()
        #expect(try configuration.modelMapping.resolve("logical") == "actual")
        #expect(!configuration.options.includeUsage)
        #expect(configuration.options.requiresDoneMarker)
        #expect(configuration.options.tokenLimitParameter == .maxTokens)
    }
}
