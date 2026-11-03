import Foundation
import Testing
@testable import LLMCore

@Suite("Optional access capability contracts")
struct LLMAccessCapabilityTests {
    @Test("Capabilities round-trip without App-specific tier concepts")
    func roundTrip() throws {
        let model = LLMAccessCapability.modelAccess(agentID: "other-agent", profileID: "quality", modelID: "vendor/model", requiredAccessIDs: ["app-entitlement"])
        for capability in [LLMAccessCapability.backendBYOK, model] {
            try capability.validate()
            #expect(try JSONDecoder().decode(LLMAccessCapability.self, from: JSONEncoder().encode(capability)) == capability)
        }
        #expect(model.resource.id == "other-agent")
        #expect(model.requiredAccessIDs == ["app-entitlement"])
        let first = LLMAccessCapability.modelAccess(agentID: "a:b", profileID: "c", modelID: "m", requiredAccessIDs: ["r"])
        let second = LLMAccessCapability.modelAccess(agentID: "a", profileID: "b:c", modelID: "m", requiredAccessIDs: ["r"])
        #expect(first.id != second.id)
    }

    @Test("A wildcard Chat Allow never opts an App into BYOK")
    func explicitAdmission() {
        let resource = LLMAccessCapability.backendBYOK.resource
        var policy = LLMAccessPolicy(rules: [.init(resource: .init(kind: "inference", id: "chat"), effect: .allow)])
        #expect(!policy.hasExplicitAdmission(for: resource))
        policy.rules.append(.init(resource: .init(kind: "inference", id: "chat", billingSource: .platform), effect: .allow))
        #expect(!policy.hasExplicitAdmission(for: resource))
        policy.rules.append(.init(resource: resource, effect: .deny))
        #expect(!policy.hasExplicitAdmission(for: resource))
        policy.rules.append(.init(resource: resource, effect: .allow))
        #expect(policy.hasExplicitAdmission(for: resource))
        #expect(policy.evaluate(resource: resource, effectiveProductIDs: [], registeredProductIDs: []).denial == .explicitDeny)
    }

    @Test("Model descriptors must identify a protected platform profile")
    func invalidDescriptors() {
        let invalid: [LLMAccessCapability] = [
            .init(id: "backend-byok", kind: .backendBYOK, resource: .init(kind: "inference", id: "chat")),
            .modelAccess(agentID: "agent", profileID: "basic", modelID: "vendor/model", requiredAccessIDs: []),
            .modelAccess(agentID: "agent", profileID: "quality", modelID: "vendor/model", requiredAccessIDs: ["invalid requirement"])
        ]
        for capability in invalid {
            #expect(throws: LLMAccessPolicyError.self) { try capability.validate() }
        }
    }
}
