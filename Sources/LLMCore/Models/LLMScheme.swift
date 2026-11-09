import Foundation

/// Stable data identities, not App feature names or a universal tier hierarchy.
public struct LLMSchemeSelection: ContentModel {
    public var schemeID: String
    public var profileID: String?
    public init(schemeID: String, profileID: String? = nil) {
        self.schemeID = schemeID
        self.profileID = profileID
    }
    public func validate() throws {
        guard LLMAccessPolicy.validIdentifier(schemeID), ![".", ".."].contains(schemeID),
              profileID.map({ LLMAccessPolicy.validIdentifier($0) && ![".", ".."].contains($0) }) ?? true else {
            throw LLMSchemeValidationError.invalidSelection
        }
    }
}

public enum LLMSchemeKind: String, Codable, CaseIterable, Sendable {
    case conversation, image
}

public struct LLMSchemeInput: ContentModel, Identifiable {
    public enum Kind: String, Codable, Sendable { case text, imageURL }
    public var id: String
    public var kind: Kind
    public var required: Bool
    public init(id: String, kind: Kind, required: Bool) {
        self.id = id; self.kind = kind; self.required = required
    }
}

public struct LLMSchemeProfile: ContentModel, Identifiable {
    public var id: String
    public var name: String
    public var rank: Int
    public var isVisible: Bool
    public var capabilities: ModelProfileCapabilities
    /// Informational only. Invocation selects id; the server resolves the actual model.
    public var modelID: String?
    /// Advisory snapshot, never a permission token. Real execution rechecks access.
    public var access: LLMAccessDecision?
    public init(id: String, name: String, rank: Int, isVisible: Bool = true,
                capabilities: ModelProfileCapabilities = .init(), modelID: String? = nil,
                access: LLMAccessDecision? = nil) {
        self.id = id; self.name = name; self.rank = rank; self.isVisible = isVisible
        self.capabilities = capabilities; self.modelID = modelID; self.access = access
    }
}

/// Tenant-scoped public metadata. Contains no templates, private prompts or credentials.
public struct LLMSchemeDescriptor: ContentModel, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var kind: LLMSchemeKind
    public var defaultProfileID: String
    public var profiles: [LLMSchemeProfile]
    /// Public input names/types only; never includes the private prompt template.
    public var inputs: [LLMSchemeInput]?
    public init(id: String, name: String, summary: String, kind: LLMSchemeKind,
                defaultProfileID: String, profiles: [LLMSchemeProfile], inputs: [LLMSchemeInput]? = nil) {
        self.id = id; self.name = name; self.summary = summary; self.kind = kind
        self.defaultProfileID = defaultProfileID; self.profiles = profiles
        self.inputs = inputs
    }
}

/// One invocation contract for conversation and parameterized image schemes.
/// Platform requests cannot override the configured model. BYOK explicitly supplies its own
/// model ID and does not select a platform profile; provider/key remain request-only headers.
public struct LLMSchemeRequest<Metadata: ContentModel>: ContentModel {
    public var scheme: LLMSchemeSelection
    public var messages: [ChatMessageContent]
    public var parameters: [String: String]
    public var metadata: Metadata?
    public var tools: [ToolSchema]?
    public var byokModelID: String?
    private enum CodingKeys: String, CodingKey { case scheme, messages, parameters, metadata, tools, byokModelID }
    public init(scheme: LLMSchemeSelection, messages: [ChatMessageContent] = [],
                parameters: [String: String] = [:], metadata: Metadata? = nil,
                tools: [ToolSchema]? = nil, byokModelID: String? = nil) {
        self.scheme = scheme; self.messages = messages; self.parameters = parameters
        self.metadata = metadata; self.tools = tools; self.byokModelID = byokModelID
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scheme = try values.decode(LLMSchemeSelection.self, forKey: .scheme)
        messages = try values.decodeIfPresent([ChatMessageContent].self, forKey: .messages) ?? []
        parameters = try values.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:]
        metadata = try values.decodeIfPresent(Metadata.self, forKey: .metadata)
        tools = try values.decodeIfPresent([ToolSchema].self, forKey: .tools)
        byokModelID = try values.decodeIfPresent(String.self, forKey: .byokModelID)
    }
}

public enum LLMSchemeValidationError: Error, Sendable { case invalidSelection }
