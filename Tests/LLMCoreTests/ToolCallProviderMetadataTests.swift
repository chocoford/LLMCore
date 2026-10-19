import Foundation
import Testing
@testable import LLMCore

@Suite("Tool continuation metadata compatibility")
struct ToolCallProviderMetadataTests {
    @Test("Existing tool-call JSON remains compatible")
    func legacyToolCall() throws {
        let data = Data(#"{"id":"call_1","name":"tool","arguments":"{}"}"#.utf8)
        let call = try JSONDecoder().decode(ToolCall.self, from: data)
        #expect(call.providerMetadata == nil)
    }

    @Test("Opaque provider state survives serialization and argument sanitization")
    func metadataRoundTrip() throws {
        let call = ToolCall(id: "call_1", name: "tool", arguments: "{invalid", providerMetadata: ["google.thought_signature": "opaque-signature"])
        var safe = call
        safe.arguments = safe.providerSafeArguments
        let restored = try JSONDecoder().decode(ToolCall.self, from: JSONEncoder().encode(safe))
        #expect(restored.arguments == "{}")
        #expect(restored.providerMetadata == call.providerMetadata)
    }
}
