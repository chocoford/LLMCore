import Foundation
import Testing
@testable import LLMCore

@Suite("App-scoped server resource connections")
struct LLMAppResourcePolicyTests {
    private let assistant = LLMAccessResourceDescriptor(id: "agent/canvas", category: .assistant,
        name: "Canvas", summary: "Assistant", resource: .init(kind: "agent", id: "canvas"))
    private let model = LLMAccessResourceDescriptor(id: "agent/canvas/profile/quality", category: .modelProfile,
        name: "Quality model", summary: "Protected profile",
        resource: .init(kind: "agent", id: "canvas", billingSource: .platform, modelProfileID: "quality"),
        requiredAccessIDs: ["max"], modelID: "vendor/model", parentID: "agent/canvas")
    private let scene = LLMAccessResourceDescriptor(id: "image-scene/greeting", category: .imageScene,
        name: "Greeting", summary: "Image scene", resource: .init(kind: "image-scene", id: "greeting", billingSource: .platform))
    private var catalog: [LLMAccessResourceDescriptor] { [assistant, model, scene] }

    @Test("Old JSON stays in compatibility mode; an explicit empty list is restrictive")
    func backwardsCompatibleCoding() throws {
        let old = Data(#"{"version":1,"requirements":[],"rules":[]}"#.utf8)
        let legacy = try JSONDecoder().decode(LLMAccessPolicy.self, from: old)
        #expect(legacy.resourceBindings == nil)
        #expect(LLMAppResourcePolicy.permits(scene.resource, policy: legacy, catalog: catalog))
        let managed = LLMAccessPolicy(resourceBindings: [])
        let decoded = try JSONDecoder().decode(LLMAccessPolicy.self, from: JSONEncoder().encode(managed))
        #expect(decoded.resourceBindings == [])
        #expect(!LLMAppResourcePolicy.permits(scene.resource, policy: decoded, catalog: catalog))
    }

    @Test("Empty legacy placeholders never advertise another App’s models")
    func legacySuggestions() {
        var policy = LLMAccessPolicy(requirements: [.init(id: "max", acceptedProductIDs: [])],
            rules: [.init(resource: assistant.resource, effect: .allow)])
        #expect(LLMAppResourcePolicy.legacyBindings(in: policy, catalog: catalog).isEmpty)
        #expect(LLMAppResourcePolicy.capabilities(in: policy, catalog: catalog) == [.backendBYOK])
        policy.requirements[0].acceptedProductIDs = ["app.own-product"]
        #expect(LLMAppResourcePolicy.legacyBindings(in: policy, catalog: catalog).map(\.id) == [assistant.id, model.id])
        let migrated = try? LLMAppResourcePolicy.applying([
            .init(resourceID: assistant.id, name: "Drawing assistant"),
            .init(resourceID: model.id, name: "Detailed drawing")
        ], to: policy, catalog: catalog)
        #expect(migrated?.requirements == policy.requirements)
        #expect(migrated?.rules.contains { $0.resource == model.resource && $0.effect == .require && $0.requirementIDs == ["max"] } == true)
    }

    @Test("An App selects its own resources and labels without cross-App agent access")
    func appSpecificResources() throws {
        let original = LLMAccessPolicy(rules: [.init(resource: assistant.resource, effect: .allow)])
        let binding = LLMAppResourceBinding(resourceID: scene.id, name: "生日贺卡生成", summary: "为照片生成生日涂鸦")
        let policy = try LLMAppResourcePolicy.applying([binding], to: original, catalog: catalog)
        #expect(LLMAppResourcePolicy.permits(scene.resource, policy: policy, catalog: catalog))
        #expect(!LLMAppResourcePolicy.permits(model.resource, policy: policy, catalog: catalog))
        #expect(policy.rules.contains { $0.resource == scene.resource && $0.effect == .deny })
        let capabilities = LLMAppResourcePolicy.capabilities(in: policy, catalog: catalog)
        #expect(capabilities.count == 2 && capabilities[1].kind == .resourceAccess)
        #expect(capabilities[1].binding?.name == "生日贺卡生成")
        #expect(capabilities[1].resource == scene.resource && capabilities[1].modelID == nil)
        try capabilities.forEach { try $0.validate() }
        #expect(try JSONDecoder().decode(LLMAccessCapability.self, from: JSONEncoder().encode(capabilities[1])) == capabilities[1])
    }

    @Test("Disconnecting a child cannot restore it through a broader assistant connection")
    func disconnectProtectedChild() throws {
        let bindings = [LLMAppResourceBinding(resourceID: assistant.id, name: "Assistant"),
                        LLMAppResourceBinding(resourceID: model.id, name: "Detailed drawing")]
        let policy = LLMAccessPolicy(requirements: [.init(id: "max", acceptedProductIDs: ["app.product"])], rules: [
            .init(resource: assistant.resource, effect: .allow),
            .init(resource: model.resource, effect: .require, requirementIDs: ["max"])
        ], resourceBindings: bindings)
        let updated = try LLMAppResourcePolicy.applying([bindings[0]], to: policy, catalog: catalog)
        #expect(LLMAppResourcePolicy.permits(model.resource, policy: updated, catalog: catalog))
        #expect(updated.evaluate(resource: model.resource, effectiveProductIDs: ["app.product"], registeredProductIDs: ["app.product"], additionalRequirementIDs: ["max"]).denial == .explicitDeny)
        #expect(updated.requirements == policy.requirements)
    }

    @Test("Global rollout Allows do not activate newly connected resources")
    func connectDoesNotGrant() throws {
        let policy = LLMAccessPolicy(rules: [.init(resource: assistant.resource, effect: .allow)], resourceBindings: [])
        let updated = try LLMAppResourcePolicy.applying([.init(resourceID: assistant.id, name: "My Assistant")], to: policy, catalog: catalog)
        #expect(updated.rules.filter { $0.resource == assistant.resource }.map(\.effect) == [.deny])
        #expect(updated.evaluate(resource: model.resource, effectiveProductIDs: [], registeredProductIDs: []).denial == .explicitDeny)
    }

    @Test("Unknown resources and duplicate registrations are rejected")
    func invalidBindings() {
        #expect(throws: LLMAccessPolicyError.self) {
            try LLMAppResourcePolicy.applying([.init(resourceID: "made-up/resource", name: "Unknown")], to: .init(), catalog: catalog)
        }
        let binding = LLMAppResourceBinding(resourceID: scene.id, name: "Greeting")
        #expect(throws: LLMAccessPolicyError.self) {
            try LLMAppResourcePolicy.applying([binding, binding], to: .init(), catalog: catalog)
        }
    }
}
