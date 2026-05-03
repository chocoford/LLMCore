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
    /// 推荐使用的模型。客户端无 UI 选择时直接用它。
    public var defaultModel: SupportedModel
    /// 该用户被允许使用的模型列表(始终包含 defaultModel)。
    /// 客户端可做 picker, 也可只用 default。**真正的权威校验仍发生在 /chat 端点**,
    /// 这里只是 UX 提示和客户端 fast-path 拦截。
    public var allowedModels: [SupportedModel]

    public init(
        defaultModel: SupportedModel,
        allowedModels: [SupportedModel]
    ) {
        self.defaultModel = defaultModel
        self.allowedModels = allowedModels
    }
}
