import Foundation
import Testing
@testable import LLMCore

@Suite("App-scoped access policy")
struct LLMAccessPolicyTests {
    private let resource = LLMAccessResource(kind: "agent", id: "canvas", billingSource: .platform, modelProfileID: "extra-high")
    private let products: Set<String> = ["app.pro", "app.max", "app.addon"]

    private func policy() -> LLMAccessPolicy {
        .init(requirements: [
            .init(id: "premium", acceptedProductIDs: ["app.pro", "app.max"]),
            .init(id: "drawing-addon", acceptedProductIDs: ["app.addon"])
        ], rules: [
            .init(resource: .init(kind: "agent", id: "canvas"), effect: .allow),
            .init(resource: .init(kind: "agent", id: "canvas", billingSource: .platform), effect: .require, requirementIDs: ["premium"])
        ])
    }

    @Test("Products within a requirement are OR; matching requirements are AND", arguments: ["app.pro", "app.max"])
    func conjunction(product: String) {
        var policy = policy()
        policy.rules.append(.init(resource: resource, effect: .require, requirementIDs: ["drawing-addon"]))
        let denied = policy.evaluate(resource: resource, effectiveProductIDs: [product], registeredProductIDs: products)
        #expect(!denied.allowed)
        #expect(denied.missingRequirementIDs == ["drawing-addon"])
        #expect(policy.evaluate(resource: resource, effectiveProductIDs: [product, "app.addon"], registeredProductIDs: products).allowed)
    }

    @Test("Deny wins regardless of rule order and Allow does not waive requirements", arguments: [false, true])
    func denyPrecedence(reverse: Bool) {
        var policy = policy()
        #expect(!policy.evaluate(resource: resource, effectiveProductIDs: [], registeredProductIDs: products).allowed)
        policy.rules.append(.init(resource: resource, effect: .deny))
        if reverse { policy.rules.reverse() }
        #expect(policy.evaluate(resource: resource, effectiveProductIDs: products, registeredProductIDs: products).denial == .explicitDeny)
    }

    @Test("Missing rules, definitions and stale product registrations fail closed")
    func missingConfiguration() {
        #expect(LLMAccessPolicy().evaluate(resource: resource, effectiveProductIDs: products, registeredProductIDs: products).denial == .ruleMissing)
        let policy = policy()
        #expect(policy.evaluate(resource: resource, effectiveProductIDs: products, registeredProductIDs: products, additionalRequirementIDs: ["unknown"]).denial == .configurationMissing)
        #expect(policy.evaluate(resource: resource, effectiveProductIDs: products, registeredProductIDs: ["other-app.pro"]).denial == .configurationMissing)
    }

    @Test("Empty product sets deliberately deny everyone; product names have no implied hierarchy")
    func noPlanGuessing() {
        var policy = policy()
        #expect(!policy.evaluate(resource: resource, effectiveProductIDs: ["plan.premium", "premium", "app.max10x"], registeredProductIDs: products).allowed)
        policy.requirements[0].acceptedProductIDs = []
        #expect(policy.evaluate(resource: resource, effectiveProductIDs: products, registeredProductIDs: products).denial == .subscriptionRequired)
    }

    @Test("Model profile requirements cannot be bypassed with an Allow rule")
    func serverRequirements() {
        let policy = policy()
        let decision = policy.evaluate(resource: resource, effectiveProductIDs: ["app.pro"], registeredProductIDs: products, additionalRequirementIDs: ["drawing-addon"])
        #expect(decision.missingRequirementIDs == ["drawing-addon"])
    }

    @Test("Billing, profile, action and resource selectors are exact")
    func selectors() {
        let rule = LLMAccessRule(resource: resource, effect: .deny)
        #expect(rule.matches(resource))
        for changed in [
            LLMAccessResource(kind: "agent", id: "other", billingSource: .platform, modelProfileID: "extra-high"),
            .init(kind: "agent", id: "canvas", action: "read", billingSource: .platform, modelProfileID: "extra-high"),
            .init(kind: "agent", id: "canvas", billingSource: .byok, modelProfileID: "extra-high"),
            .init(kind: "agent", id: "canvas", billingSource: .platform, modelProfileID: "standard")
        ] { #expect(!rule.matches(changed)) }
        let byok = LLMAccessResource(kind: "agent", id: "canvas", billingSource: .byok)
        #expect(policy().evaluate(resource: byok, effectiveProductIDs: [], registeredProductIDs: products).allowed)
    }

    @Test("Malformed, duplicate or dangling rules are rejected")
    func validation() {
        var policy = policy()
        policy.requirements.append(policy.requirements[0])
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
        policy = self.policy()
        policy.rules.append(.init(resource: resource, effect: .require))
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
        policy = self.policy()
        policy.rules[0].requirementIDs = ["unknown"]
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
        policy = self.policy()
        policy.rules.append(policy.rules[0])
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
        #expect(policy.evaluate(resource: resource, effectiveProductIDs: products, registeredProductIDs: products).denial == .configurationMissing)
    }

    @Test("Unsafe and oversized IDs cannot become executable policy expressions", arguments: ["", "*", "../max", "paid || true", "套餐", String(repeating: "x", count: 129)])
    func identifiers(value: String) {
        #expect(!LLMAccessPolicy.validIdentifier(value))
        #expect(policy().evaluate(resource: resource, effectiveProductIDs: products, registeredProductIDs: products, additionalRequirementIDs: [value]).denial == .configurationMissing)
    }

    @Test("Policy documents round-trip atomically with their revision")
    func coding() throws {
        let response = LLMAppAccessPolicyResponse(appConfigID: UUID(), revision: UUID(), policy: policy())
        #expect(try JSONDecoder().decode(LLMAppAccessPolicyResponse.self, from: JSONEncoder().encode(response)) == response)
        let legacy = try JSONDecoder().decode(ModelProfileRequirements.self, from: Data(#"{"plan":"max"}"#.utf8))
        #expect(legacy.requiredAccessIDs == ["max"])
        #expect(ModelProfileRequirements(plan: "max", accessRequirementIDs: ["drawing", "max"]).requiredAccessIDs == ["drawing", "max"])
    }

    @Test("Legacy errors remain decodable and old readers ignore structured access")
    func errorCompatibility() throws {
        struct LegacyError: Codable, Equatable {
            let code: Int
            let message: String
        }
        let legacy = try JSONDecoder().decode(APIError.self, from: Data(#"{"code":403,"message":"Forbidden"}"#.utf8))
        #expect(legacy == APIError(code: 403, message: "Forbidden"))
        #expect(legacy.access == nil)

        let error = APIError(code: 403, message: "Access denied", access: .denied(.subscriptionRequired, requirementIDs: ["max"]))
        let encoded = try JSONEncoder().encode(error)
        #expect(try JSONDecoder().decode(APIError.self, from: encoded) == error)
        #expect(try JSONDecoder().decode(LegacyError.self, from: encoded) == LegacyError(code: 403, message: "Access denied"))
        let legacyEncoding = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
        #expect(legacyEncoding?["access"] == nil)
    }

    @Test("Invalid product IDs cannot be registered", arguments: ["", " ", "app.pro\n", "套餐", String(repeating: "x", count: 256)])
    func invalidProducts(value: String) {
        var policy = policy()
        policy.requirements[0].acceptedProductIDs = [value]
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
    }

    @Test("Version, count and duplicate bounds fail closed")
    func policyBounds() {
        var policy = policy()
        policy.version = 2
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
        policy = self.policy()
        policy.requirements[0].acceptedProductIDs = ["app.pro", "app.pro"]
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
        policy = self.policy()
        policy.rules[1].requirementIDs = ["premium", "premium"]
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
        policy = .init(requirements: (0..<257).map { .init(id: "requirement-\($0)", acceptedProductIDs: []) })
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
        policy = .init(rules: (0..<1025).map { _ in .init(resource: resource, effect: .allow) })
        #expect(throws: LLMAccessPolicyError.self) { try policy.validate() }
        #expect(self.policy().evaluate(resource: resource, effectiveProductIDs: products, registeredProductIDs: products, additionalRequirementIDs: Array(repeating: "premium", count: 65)).denial == .configurationMissing)
    }
}
