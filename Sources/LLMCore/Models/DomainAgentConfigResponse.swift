//
//  DomainAgentConfigResponse.swift
//  LLMCore
//
//  服务端把一个"领域 Agent"对外可见的运行时配置下发给客户端。
//
//  适用场景: agent 的工具必须客户端执行(例如 Excalidraw canvas 编辑),
//  服务端没法跑完整 ReAct loop, 客户端用 LLMKit 自己跑。
//
//  注意 systemPrompt **不在响应里**: 它是核心 IP, 服务端持有,
//  在客户端调 `/chat` 时通过 agentID 偷偷注入到 messages 头部。
//  这里只下发"客户端真的不知道、必须问服务端"的字段。
//

import Foundation

public struct DomainAgentConfigResponse: ContentModel {
    /// Legacy fallback for old clients. New clients should prefer `modelProfiles`.
    public var defaultModel: SupportedModel
    /// Legacy fallback for old clients. New clients should prefer `modelProfiles`.
    /// The server remains authoritative and validates the selected model on `/chat`.
    public var allowedModels: [SupportedModel]

    /// Server-defined model menu for this domain agent.
    /// Client presentation should be keyed by `(agentID, profile.id)` for localization.
    public var modelProfiles: [DomainModelProfile]?
    /// Preferred profile id. If absent or unknown, clients should fall back to the lowest-rank
    /// visible profile, then to `defaultModel`.
    public var defaultModelProfileID: String?

    public init(
        defaultModel: SupportedModel,
        allowedModels: [SupportedModel],
        modelProfiles: [DomainModelProfile]? = nil,
        defaultModelProfileID: String? = nil
    ) {
        self.defaultModel = defaultModel
        self.allowedModels = allowedModels
        self.modelProfiles = modelProfiles
        self.defaultModelProfileID = defaultModelProfileID
    }
}

public struct DomainModelProfile: ContentModel, Identifiable {
    /// Stable within one domain agent, e.g. "fast", "standard", "max".
    public var id: String
    public var model: SupportedModel
    /// Lower ranks are preferred for fallback / display ordering.
    public var rank: Int
    /// UI hint only. The server still validates requirements on `/chat`.
    public var isVisible: Bool
    public var requirements: ModelProfileRequirements
    public var capabilities: ModelProfileCapabilities

    public init(
        id: String,
        model: SupportedModel,
        rank: Int,
        isVisible: Bool = true,
        requirements: ModelProfileRequirements = .init(),
        capabilities: ModelProfileCapabilities? = nil
    ) {
        self.id = id
        self.model = model
        self.rank = rank
        self.isVisible = isVisible
        self.requirements = requirements
        self.capabilities = capabilities ?? .init(
            supportsImageInput: model.supportsImageInput,
            maxContextTokens: model.maxContextTokens
        )
    }
}

public struct ModelProfileRequirements: ContentModel {
    /// nil means no plan gate. Example: "max".
    public var plan: String?

    public init(plan: String? = nil) {
        self.plan = plan
    }
}

public struct ModelProfileCapabilities: ContentModel {
    public var supportsImageInput: Bool?
    public var maxContextTokens: Int?

    public init(
        supportsImageInput: Bool? = nil,
        maxContextTokens: Int? = nil
    ) {
        self.supportsImageInput = supportsImageInput
        self.maxContextTokens = maxContextTokens
    }
}
