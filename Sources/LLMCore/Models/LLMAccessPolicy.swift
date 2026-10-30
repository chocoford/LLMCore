import Foundation

/// App-scoped identifiers, not universal subscription names or levels.
public struct LLMAccessRequirement: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var acceptedProductIDs: [String]
    public init(id: String, acceptedProductIDs: [String]) {
        self.id = id
        self.acceptedProductIDs = acceptedProductIDs
    }
}

public enum LLMAccessBillingSource: String, Codable, CaseIterable, Sendable {
    case platform, byok
}

/// The server constructs this from the actual operation. Client evaluations are advisory only.
public struct LLMAccessResource: Codable, Equatable, Sendable {
    public var kind: String
    public var id: String
    public var action: String
    public var billingSource: LLMAccessBillingSource?
    public var modelProfileID: String?
    public init(kind: String, id: String, action: String = "invoke", billingSource: LLMAccessBillingSource? = nil, modelProfileID: String? = nil) {
        self.kind = kind; self.id = id; self.action = action
        self.billingSource = billingSource; self.modelProfileID = modelProfileID
    }

    public func validate() throws {
        guard [kind, id, action].allSatisfy(LLMAccessPolicy.validIdentifier),
              modelProfileID.map(LLMAccessPolicy.validIdentifier) ?? true else { throw LLMAccessPolicyError.invalidConfiguration }
    }
}

public struct LLMAccessRule: Codable, Equatable, Sendable, Identifiable {
    public enum Effect: String, Codable, CaseIterable, Sendable { case allow, require, deny }
    public var id: UUID
    public var resource: LLMAccessResource
    public var effect: Effect
    public var requirementIDs: [String]
    public init(id: UUID = UUID(), resource: LLMAccessResource, effect: Effect, requirementIDs: [String] = []) {
        self.id = id; self.resource = resource; self.effect = effect; self.requirementIDs = requirementIDs
    }
    public func matches(_ actual: LLMAccessResource) -> Bool {
        resource.kind == actual.kind && resource.id == actual.id && resource.action == actual.action
            && (resource.billingSource == nil || resource.billingSource == actual.billingSource)
            && (resource.modelProfileID == nil || resource.modelProfileID == actual.modelProfileID)
    }
}

/// An atomic document, administered through a trusted management API, never client registration.
public struct LLMAccessPolicy: Codable, Equatable, Sendable {
    public var version: Int
    public var requirements: [LLMAccessRequirement]
    public var rules: [LLMAccessRule]
    public init(requirements: [LLMAccessRequirement] = [], rules: [LLMAccessRule] = []) {
        version = 1; self.requirements = requirements; self.rules = rules
    }
    public func validate() throws {
        guard version == 1, requirements.count <= 256, rules.count <= 1024,
              Set(requirements.map(\.id)).count == requirements.count,
              Set(rules.map(\.id)).count == rules.count,
              try JSONEncoder().encode(self).count <= 512 * 1024 else { throw LLMAccessPolicyError.invalidConfiguration }
        let requirementIDs = Set(requirements.map(\.id))
        for requirement in requirements {
            // An empty product set is deliberately deny-all (useful during safe migration).
            guard Self.validIdentifier(requirement.id), requirement.acceptedProductIDs.count <= 256,
                  Set(requirement.acceptedProductIDs).count == requirement.acceptedProductIDs.count,
                  requirement.acceptedProductIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 && $0.utf8.allSatisfy { (33...126).contains($0) } }) else { throw LLMAccessPolicyError.invalidConfiguration }
        }
        for rule in rules {
            try rule.resource.validate()
            guard rule.requirementIDs.count <= 64,
                  Set(rule.requirementIDs).count == rule.requirementIDs.count,
                  rule.requirementIDs.allSatisfy({ requirementIDs.contains($0) }),
                  (rule.effect == .require) == !rule.requirementIDs.isEmpty else { throw LLMAccessPolicyError.invalidConfiguration }
        }
    }

    public static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 58, 95].contains($0)
        }
    }

    public func evaluate(
        resource: LLMAccessResource,
        effectiveProductIDs: Set<String>,
        registeredProductIDs: Set<String>,
        additionalRequirementIDs: [String] = []
    ) -> LLMAccessDecision {
        guard (try? validate()) != nil, (try? resource.validate()) != nil,
              additionalRequirementIDs.count <= 64,
              additionalRequirementIDs.allSatisfy(Self.validIdentifier) else { return .denied(.configurationMissing) }
        let matching = rules.filter { $0.matches(resource) }
        guard !matching.isEmpty else { return .denied(.ruleMissing) }
        if matching.contains(where: { $0.effect == .deny }) { return .denied(.explicitDeny) }
        let required = Set(matching.flatMap(\.requirementIDs) + additionalRequirementIDs).sorted()
        let definitions = Dictionary(uniqueKeysWithValues: requirements.map { ($0.id, $0) })
        var missing: [String] = []
        for id in required {
            guard let definition = definitions[id] else { return .denied(.configurationMissing, requirementIDs: required) }
            // Removing a registered product must not leave a stale authorization grant.
            guard Set(definition.acceptedProductIDs).isSubset(of: registeredProductIDs) else { return .denied(.configurationMissing, requirementIDs: required) }
            if Set(definition.acceptedProductIDs).isDisjoint(with: effectiveProductIDs) { missing.append(id) }
        }
        return .init(allowed: missing.isEmpty, requirementIDs: required, missingRequirementIDs: missing, denial: missing.isEmpty ? nil : .subscriptionRequired)
    }
}

public enum LLMAccessPolicyError: Error, Sendable { case invalidConfiguration }

/// Local preflight context only. Neither this value nor an App's decision grants server access.
public struct LLMAccessRequest: Sendable {
    public var resource: LLMAccessResource
    public var model: SupportedModel?
    public var requirementIDs: [String]
    public init(resource: LLMAccessResource, model: SupportedModel? = nil, requirementIDs: [String] = []) {
        self.resource = resource; self.model = model; self.requirementIDs = requirementIDs
    }
}

public struct LLMAccessDecision: Codable, Equatable, Sendable {
    public enum Denial: String, Codable, Sendable { case configurationMissing, ruleMissing, explicitDeny, subscriptionRequired }
    public var allowed: Bool
    public var requirementIDs: [String]
    public var missingRequirementIDs: [String]
    public var denial: Denial?
    public init(allowed: Bool, requirementIDs: [String] = [], missingRequirementIDs: [String] = [], denial: Denial? = nil) {
        self.allowed = allowed; self.requirementIDs = requirementIDs
        self.missingRequirementIDs = missingRequirementIDs; self.denial = denial
    }
    public static func denied(_ denial: Denial, requirementIDs: [String] = []) -> Self {
        .init(allowed: false, requirementIDs: requirementIDs, denial: denial)
    }
}

public struct LLMAppAccessPolicyResponse: Codable, Equatable, Sendable {
    public var appConfigID: UUID
    public var revision: UUID
    public var policy: LLMAccessPolicy
    public var updatedAt: Date?
    public init(appConfigID: UUID, revision: UUID, policy: LLMAccessPolicy, updatedAt: Date? = nil) {
        self.appConfigID = appConfigID; self.revision = revision; self.policy = policy; self.updatedAt = updatedAt
    }
}

public struct LLMAccessPolicyUpdateRequest: Codable, Equatable, Sendable {
    public var policy: LLMAccessPolicy
    public var expectedRevision: UUID?
    public init(policy: LLMAccessPolicy, expectedRevision: UUID?) {
        self.policy = policy; self.expectedRevision = expectedRevision
    }
}
