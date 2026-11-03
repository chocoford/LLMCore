import Foundation

/// An operator-managed connection between one App and a trusted server resource.
/// Names are App presentation data, never authorization claims supplied by App users.
public struct LLMAppResourceBinding: Codable, Equatable, Sendable, Identifiable {
    public var resourceID: String
    public var name: String
    public var summary: String?
    public var id: String { resourceID }

    public init(resourceID: String, name: String, summary: String? = nil) {
        self.resourceID = resourceID; self.name = name; self.summary = summary
    }

    public func validate() throws {
        guard !resourceID.isEmpty, resourceID.utf8.count <= 512,
              resourceID.utf8.allSatisfy({ (33...126).contains($0) }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 256, (summary?.utf8.count ?? 0) <= 2048 else {
            throw LLMAccessPolicyError.invalidConfiguration
        }
    }
}

/// Public resource metadata. It contains no prompts, provider credentials or billing grants.
public struct LLMAccessResourceDescriptor: Codable, Equatable, Sendable, Identifiable {
    public enum Category: String, Codable, Sendable { case assistant, modelProfile, tool, imageGeneration, imageScene }
    public let id: String
    public let category: Category
    public let name: String
    public let summary: String
    public let resource: LLMAccessResource
    public let requiredAccessIDs: [String]
    public let modelID: String?
    public let parentID: String?

    public init(id: String, category: Category, name: String, summary: String, resource: LLMAccessResource,
                requiredAccessIDs: [String] = [], modelID: String? = nil, parentID: String? = nil) {
        self.id = id; self.category = category; self.name = name; self.summary = summary
        self.resource = resource; self.requiredAccessIDs = Array(Set(requiredAccessIDs)).sorted()
        self.modelID = modelID; self.parentID = parentID
    }

    public func validate() throws {
        try LLMAppResourceBinding(resourceID: id, name: name, summary: summary).validate()
        try resource.validate()
        guard requiredAccessIDs.count <= 64, requiredAccessIDs.allSatisfy(LLMAccessPolicy.validIdentifier) else {
            throw LLMAccessPolicyError.invalidConfiguration
        }
    }

    public func capability(binding: LLMAppResourceBinding, legacy: Bool = false) -> LLMAccessCapability {
        let isLegacyProfile = legacy && category == .modelProfile && !requiredAccessIDs.isEmpty
        return .init(id: isLegacyProfile ? "model/\(resource.id)/\(resource.modelProfileID ?? "")" : "resource/\(id)",
                     kind: isLegacyProfile ? .modelAccess : .resourceAccess, resource: resource,
                     requiredAccessIDs: requiredAccessIDs, modelID: modelID, binding: binding, descriptor: self)
    }
}

public enum LLMAppResourcePolicy {
    public static func isManagedResource(_ resource: LLMAccessResource) -> Bool {
        ["agent", "tool", "image", "image-scene"].contains(resource.kind)
    }

    /// A narrow compatibility suggestion based on real configured gates, not all globally
    /// registered agents or product-name guesses. Empty migration placeholders do not count.
    public static func legacyBindings(in policy: LLMAccessPolicy, catalog: [LLMAccessResourceDescriptor]) -> [LLMAppResourceBinding] {
        var selected: Set<String> = []
        for descriptor in catalog where descriptor.category == .modelProfile && !descriptor.requiredAccessIDs.isEmpty {
            let explicitlyConfigured = policy.rules.contains { $0.resource == descriptor.resource && $0.effect != .deny }
            let mapped = descriptor.requiredAccessIDs.allSatisfy { id in
                policy.requirements.contains { $0.id == id && !$0.acceptedProductIDs.isEmpty }
            }
            guard explicitlyConfigured || mapped else { continue }
            selected.insert(descriptor.id)
            if let parentID = descriptor.parentID,
               let parent = catalog.first(where: { $0.id == parentID }),
               policy.rules.contains(where: { $0.resource == parent.resource && $0.effect != .deny }) {
                selected.insert(parentID)
            }
        }
        return catalog.filter { selected.contains($0.id) }.map { .init(resourceID: $0.id, name: $0.name) }
    }

    public static func capabilities(in policy: LLMAccessPolicy, catalog: [LLMAccessResourceDescriptor]) -> [LLMAccessCapability] {
        let bindings = policy.resourceBindings ?? legacyBindings(in: policy, catalog: catalog)
        return [.backendBYOK] + bindings.compactMap { binding in
            catalog.first { $0.id == binding.resourceID }?.capability(binding: binding, legacy: policy.resourceBindings == nil)
        }
    }

    /// nil is the old compatibility mode; an explicit empty list connects no resources.
    public static func permits(_ actual: LLMAccessResource, policy: LLMAccessPolicy,
                               catalog: [LLMAccessResourceDescriptor]) -> Bool {
        guard policy.modelAccessEnabled != false else { return false }
        guard let bindings = policy.resourceBindings else { return true }
        return bindings.contains { binding in
            catalog.first { $0.id == binding.resourceID }?.resource.matches(actual) == true
        }
    }

    /// Registering a resource does not silently grant it. Previously connected rules survive;
    /// configured legacy profile gates are imported without changing their product mapping.
    public static func applying(_ bindings: [LLMAppResourceBinding], to policy: LLMAccessPolicy,
                                catalog: [LLMAccessResourceDescriptor]) throws -> LLMAccessPolicy {
        guard Set(bindings.map(\.id)).count == bindings.count,
              bindings.allSatisfy({ binding in catalog.contains { $0.id == binding.resourceID } }) else {
            throw LLMAccessPolicyError.invalidConfiguration
        }
        try bindings.forEach { try $0.validate() }
        var result = policy
        let oldBindings = policy.resourceBindings ?? legacyBindings(in: policy, catalog: catalog)
        let selected = catalog.filter { descriptor in bindings.contains { $0.resourceID == descriptor.id } }
        var retiredConditionIDs: [String] = []
        for old in oldBindings where !bindings.contains(where: { $0.id == old.id }) {
            guard let descriptor = catalog.first(where: { $0.id == old.resourceID }) else { continue }
            retiredConditionIDs += result.rules.filter { $0.resource == descriptor.resource }.flatMap(\.requirementIDs)
            result.rules.removeAll { $0.resource == descriptor.resource }
            // A retained broader connection must not restore a removed child gate.
            if selected.contains(where: { $0.resource.matches(descriptor.resource) }) {
                result.rules.append(.init(resource: descriptor.resource, effect: .deny))
            }
        }
        for descriptor in selected {
            if !oldBindings.contains(where: { $0.resourceID == descriptor.id }) {
                // Old rollout defaults contained global agent/tool Allows. They must
                // not turn a newly connected resource on without an explicit Enable.
                retiredConditionIDs += result.rules.filter { $0.resource == descriptor.resource }.flatMap(\.requirementIDs)
                result.rules.removeAll { $0.resource == descriptor.resource }
                result.rules.append(.init(resource: descriptor.resource, effect: .deny))
                continue
            }
            guard !result.rules.contains(where: { $0.resource == descriptor.resource }) else { continue }
            let matching = policy.rules.filter { $0.matches(descriptor.resource) }
            let legacyProfile = policy.resourceBindings == nil && descriptor.category == .modelProfile
                && !descriptor.requiredAccessIDs.isEmpty && !matching.isEmpty
                && !matching.contains(where: { $0.effect == .deny })
                && descriptor.requiredAccessIDs.allSatisfy { id in
                    policy.requirements.contains { $0.id == id && !$0.acceptedProductIDs.isEmpty }
                }
            result.rules.append(.init(resource: descriptor.resource, effect: legacyProfile ? .require : .deny,
                                      requirementIDs: legacyProfile ? descriptor.requiredAccessIDs : []))
        }
        result.resourceBindings = bindings
        let referenced = Set(result.rules.flatMap(\.requirementIDs) + catalog.flatMap(\.requiredAccessIDs))
        result.requirements.removeAll { requirement in
            retiredConditionIDs.contains(requirement.id) && !referenced.contains(requirement.id)
                && requirement.id.hasPrefix("capability.")
                && UUID(uuidString: String(requirement.id.dropFirst("capability.".count))) != nil
        }
        try result.validate()
        return result
    }
}
