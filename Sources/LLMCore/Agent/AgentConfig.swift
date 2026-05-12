//
//  AgentConfig.swift
//  LLMCore
//

import Foundation

/// Configuration for agent behavior.
///
/// 历史: 之前还有 `allowedSteps: Set<AgentStepType>` 字段, 用来在 prompt-based ReAct 时代
/// 让 model 输出 plan / reflection / action 等结构化 directive。切到 native tool_use 后,
/// 模型直接通过 `tool_calls` 决定动作, content 字段就是它对用户说的话, 不再需要把这些
/// 拆成"step type"。AgentExecutor 现在只看"是否注册了工具"来决定是 agent loop 还是 direct chat。
public struct AgentConfig: Codable, Sendable, Equatable {
    /// Available tools for the agent. 空 = 直接 chat 不走 ReAct loop。
    /// 公开可变: 客户端可以直接 mutate `conversation.agentConfig.tools` 来切换工具集 (比如按
    /// 当前 model 解锁不同 tools)。mutation 是 in-memory 的, 跨重启的持久化跟随
    /// `persistenceProvider` 实现 — 默认每次 sendMessage 落地 messages 时会同时把当前
    /// conversation snapshot 写盘, 自动带上最新 agentConfig。
    public var tools: [String]

    /// System prompt for the agent.
    /// 客户端 agent (例如 excalidraw-canvas) 应该把这字段留空, 由服务端在 /chat 时通过
    /// `agentID` 自动注入持有的 prompt。
    public internal(set) var systemPrompt: String?

    /// Maximum number of LLM rounds before forcing a stop.
    public internal(set) var maxThoughts: Int

    /// Temperature for LLM sampling
    public var temperature: Double

    /// 关联的服务端 domain agent 标识。设了之后, LLMKit 在每次发 /chat 时会带上这个 agentID,
    /// 服务端会校验 model + 注入 systemPrompt。
    public var agentID: String?

    public init(
        tools: [String] = [],
        systemPrompt: String? = nil,
        maxThoughts: Int = 20,
        temperature: Double = 0.7,
        agentID: String? = nil
    ) {
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.maxThoughts = maxThoughts
        self.temperature = temperature
        self.agentID = agentID
    }

    private enum CodingKeys: String, CodingKey {
        case tools
        case systemPrompt
        case systemMessage
        case maxThoughts
        case temperature
        case agentID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tools = try container.decodeIfPresent([String].self, forKey: .tools) ?? []
        self.systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
            ?? container.decodeIfPresent(String.self, forKey: .systemMessage)
        self.maxThoughts = try container.decodeIfPresent(Int.self, forKey: .maxThoughts) ?? 20
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        self.agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tools, forKey: .tools)
        try container.encodeIfPresent(systemPrompt, forKey: .systemPrompt)
        try container.encode(maxThoughts, forKey: .maxThoughts)
        try container.encode(temperature, forKey: .temperature)
        try container.encodeIfPresent(agentID, forKey: .agentID)
    }

    /// 返回一个 tools 字段被覆写的副本, 其它字段保持不变。
    /// 适合"想跑一次变体但不动 conversation 默认"的临时场景 (单元测试 / 实验性调用)。
    /// 日常 mutation 直接改 `conversation.agentConfig.tools` 即可, 不需要这个 helper。
    public func with(tools: [String]) -> AgentConfig {
        var copy = self
        copy.tools = tools
        return copy
    }

    /// Traditional chat configuration (no tools).
    public static var chat: AgentConfig {
        AgentConfig(tools: [])
    }

    /// Agent with tools. 在 native tool-use 模型下, 不再区分 react / planAndExecute / reflexion
    /// 这种 prompt-based 风格 —— 模型决定怎么编排 reasoning + tool calls, 我们只提供工具表。
    public static func withTools(
        _ tools: [String],
        maxThoughts: Int = 20,
        systemPrompt: String? = nil,
        agentID: String? = nil
    ) -> AgentConfig {
        AgentConfig(
            tools: tools,
            systemPrompt: systemPrompt,
            maxThoughts: maxThoughts,
            agentID: agentID
        )
    }

    /// Backward-compat alias for the old `react()` factory. New code should call `withTools(_:)`.
    @available(*, deprecated, message: "Use AgentConfig.withTools(...) instead. ReAct is now implicit in native tool-use.")
    public static func react(
        tools: [String],
        maxThoughts: Int = 20,
        systemPrompt: String? = nil,
        agentID: String? = nil
    ) -> AgentConfig {
        .withTools(tools, maxThoughts: maxThoughts, systemPrompt: systemPrompt, agentID: agentID)
    }

    /// Strategy instructions for the agent loop. 仅做行为级提醒, 不再约束输出格式
    /// (那由 native tool_use 协议本身搞定)。
    private func generateStrategyInstructions() -> String {
        guard !tools.isEmpty else { return "" }
        return """
            ## Workflow

            You are an agent. To finish a task you may call tools across multiple turns.
            On each turn you can:
              - reply with plain content (this is what you say to the user);
              - or call one or more tools (the system will run them and feed the results back).

            When you have done enough, simply reply with the final answer in plain content
            and call no tool. That ends the loop.

            ## Behavioral guidance

            - Do not guess values that a tool can verify. Prefer calling a tool over answering from memory.
            - If a tool errors or returns an unexpected result, do not retry the same call blindly —
              switch strategy, or surface the failure honestly to the user.
            - When the request is multi-step, keep going until every step is observably done.
            - Stay concise. Content alongside tool calls is shown to the user; explain *what you are about to do*, not restate the obvious.

            ## Tone

            - Only use emojis if the user explicitly requests it.
            - Reply in the same language as the user's question.
            - Never invent URLs unless explicitly provided or strictly required.
            """
    }

    /// Combined prompt for the agent (system prompt + lightweight strategy instructions).
    public var prompt: String {
        var parts: [String] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            parts.append(systemPrompt)
        }
        let strategyInstructions = generateStrategyInstructions()
        if !strategyInstructions.isEmpty {
            parts.append(strategyInstructions)
        }
        return parts.joined(separator: "\n\n")
    }
}
