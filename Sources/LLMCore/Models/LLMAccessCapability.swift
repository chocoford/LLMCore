import Foundation

/// A trusted, optional server capability. App-specific agent/profile IDs are data,
/// never built-in product names, model tiers or subscription levels.
public struct LLMAccessCapability: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case backendBYOK, modelAccess, resourceAccess }

    public let id: String
    public let kind: Kind
    public let resource: LLMAccessResource
    public let requiredAccessIDs: [String]
    public let modelID: String?
    public let binding: LLMAppResourceBinding?
    public let descriptor: LLMAccessResourceDescriptor?

    public init(id: String, kind: Kind, resource: LLMAccessResource, requiredAccessIDs: [String] = [], modelID: String? = nil,
                binding: LLMAppResourceBinding? = nil, descriptor: LLMAccessResourceDescriptor? = nil) {
        self.id = id
        self.kind = kind
        self.resource = resource
        self.requiredAccessIDs = Array(Set(requiredAccessIDs)).sorted()
        self.modelID = modelID
        self.binding = binding; self.descriptor = descriptor
    }

    public static var backendBYOK: Self {
        .init(id: "backend-byok", kind: .backendBYOK,
              resource: .init(kind: "inference", id: "chat", billingSource: .byok))
    }

    public static func modelAccess(agentID: String, profileID: String, modelID: String, requiredAccessIDs: [String]) -> Self {
        .init(id: "model/\(agentID)/\(profileID)", kind: .modelAccess,
              resource: .init(kind: "agent", id: agentID, billingSource: .platform, modelProfileID: profileID),
              requiredAccessIDs: requiredAccessIDs, modelID: modelID)
    }

    public func validate() throws {
        try resource.validate()
        guard requiredAccessIDs.count <= 64, Set(requiredAccessIDs).count == requiredAccessIDs.count,
              requiredAccessIDs.allSatisfy(LLMAccessPolicy.validIdentifier) else {
            throw LLMAccessPolicyError.invalidConfiguration
        }
        switch kind {
        case .backendBYOK:
            guard id == Self.backendBYOK.id, resource == Self.backendBYOK.resource, requiredAccessIDs.isEmpty else {
                throw LLMAccessPolicyError.invalidConfiguration
            }
        case .modelAccess:
            guard resource.kind == "agent", resource.action == "invoke", resource.billingSource == .platform,
                  let profileID = resource.modelProfileID, !requiredAccessIDs.isEmpty,
                  id == "model/\(resource.id)/\(profileID)" else { throw LLMAccessPolicyError.invalidConfiguration }
        case .resourceAccess:
            guard let binding, let descriptor, id == "resource/\(descriptor.id)",
                  binding.resourceID == descriptor.id, resource == descriptor.resource,
                  requiredAccessIDs == descriptor.requiredAccessIDs, modelID == descriptor.modelID else {
                throw LLMAccessPolicyError.invalidConfiguration
            }
        }
        if let binding, let descriptor {
            try binding.validate(); try descriptor.validate()
            guard binding.resourceID == descriptor.id, resource == descriptor.resource else {
                throw LLMAccessPolicyError.invalidConfiguration
            }
        }
    }
}

extension LLMAccessPolicy {
    /// Optional capabilities need a positive rule for their exact resource. This is
    /// only admission: normal evaluation must still enforce all matching rules.
    public func hasExplicitAdmission(for resource: LLMAccessResource) -> Bool {
        rules.contains { $0.resource == resource && $0.effect != .deny }
    }
}
