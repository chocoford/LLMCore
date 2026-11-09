import Foundation
import Testing
@testable import LLMCore

@Suite("Generic scheme contract")
struct LLMSchemeTests {
    @Test("A platform request selects identities, never a model or business enum")
    func platformSelection() throws {
        let value = LLMSchemeRequest<EmptyMetadata>(scheme: .init(schemeID: "app-feature-v2", profileID: "quality"),
            messages: [.init(role: .user, content: "Hello")])
        let data = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["model"] == nil && object["byokModelID"] == nil)
        #expect(try JSONDecoder().decode(LLMSchemeRequest<EmptyMetadata>.self, from: data) == value)
    }

    @Test("Omitted conversation/image fields decode to empty collections")
    func minimalRequest() throws {
        let request = try JSONDecoder().decode(LLMSchemeRequest<EmptyMetadata>.self,
            from: Data(#"{"scheme":{"schemeID":"new-feature"}}"#.utf8))
        #expect(request.messages.isEmpty && request.parameters.isEmpty)
        try request.scheme.validate()
    }

    @Test("Identifiers cannot escape the scheme route", arguments: ["", ".", "..", "../secret", "a/b", "a?x=y", "a%2fb"])
    func invalidIdentity(id: String) {
        #expect(throws: LLMSchemeValidationError.self) { try LLMSchemeSelection(schemeID: id).validate() }
    }

    @Test("Two model options can share a model without sharing identity or access")
    func independentOptions() throws {
        let value = LLMSchemeDescriptor(id: "feature", name: "App feature", summary: "", kind: .conversation,
            defaultProfileID: "standard", profiles: [
                .init(id: "standard", name: "Standard", rank: 0, modelID: "vendor/shared"),
                .init(id: "extended", name: "Extended", rank: 10, modelID: "vendor/shared")
            ])
        let copy = try JSONDecoder().decode(LLMSchemeDescriptor.self, from: JSONEncoder().encode(value))
        #expect(copy == value)
        #expect(Set(copy.profiles.map(\.id)).count == 2)
    }
}
