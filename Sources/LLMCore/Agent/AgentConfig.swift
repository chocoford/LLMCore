//
//  AgentConfig.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation
/// Types of steps an agent can perform
public enum AgentStepType: String, Codable, Sendable, Hashable {
    case plan  // 规划步骤
    case action  // 使用工具（执行后自动产生观察）
    case reflection  // 自我反思
    
    /// Whether this step type automatically produces an observation
    public var needsObservation: Bool {
        switch self {
            case .action:
                return true
            case .plan, .reflection:
                return false
        }
    }
    
    /// Instruction for this step type
    public var instruction: String {
        switch self {
                
            case .action:
                return """
                Use when you need to call a tool.

                {
                  "title": "<short title>",
                  "type": "action",
                  "tool": "<tool_name>",
                  "input": <json_object>
                }

                After the action executes, you will receive an observation.
                Use that observation to decide your next step.
                """
                
            case .plan:
                return """
                Use when you need to outline a plan or next approach.

                {
                  "title": "<short title>",
                  "type": "plan",
                  "content": "<your plan>"
                }
                """
                
            case .reflection:
                return """
                Use when you need to reflect on previous steps, observations, or strategy.

                {
                  "title": "<short title>",
                  "type": "reflection",
                  "content": "<your reflection>"
                }
                """
        }
    }
}

extension Array where Element == AgentStepType {
    /// Generate prompt instructions from step types
    /// - Returns: Combined instruction text, with thought always first
    public func generatePrompt() -> String {
        // Build ordered steps: thought first, then others in defined order
        var instructions = ""
        // Add other steps in preferred order: plan -> action -> reflection
        let otherStepsOrder: [AgentStepType] = [.plan, .action, .reflection]
        for stepType in otherStepsOrder {
            if contains(stepType) {
                instructions += stepType.instruction + "\n\n"
            }
        }
        
        return instructions
    }
}

/// Configuration for agent behavior
public struct AgentConfig: Codable, Sendable, Equatable {
    /// Allowed step types for this agent
    /// Empty set means direct response (traditional chat)
    public internal(set) var allowedSteps: Set<AgentStepType>
    
    /// Available tools for the agent
    public internal(set) var tools: [String]
    
    /// System prompt for the agent
    public internal(set) var systemPrompt: String?
    
    /// Maximum number of thought steps allowed
    public internal(set) var maxThoughts: Int
    
    /// Temperature for LLM sampling
    public var temperature: Double

    /// 关联的服务端 domain agent 标识。
    /// 设了之后, LLMKit 在每次发 /chat 时会带上这个 agentID,
    /// 服务端会校验 model + 注入 systemPrompt。
    /// 客户端不需要在 `systemPrompt` 字段里塞 persona, 那部分服务端处理。
    public var agentID: String?

    public init(
        allowedSteps: Set<AgentStepType> = [],
        tools: [String] = [],
        systemPrompt: String? = nil,
        maxThoughts: Int = 20,
        temperature: Double = 0.7,
        agentID: String? = nil
    ) {
        self.allowedSteps = allowedSteps
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.maxThoughts = maxThoughts
        self.temperature = temperature
        self.agentID = agentID
    }

    private enum CodingKeys: String, CodingKey {
        case allowedSteps
        case tools
        case systemPrompt
        case systemMessage
        case maxThoughts
        case temperature
        case agentID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allowedSteps = try container.decodeIfPresent(Set<AgentStepType>.self, forKey: .allowedSteps) ?? []
        self.tools = try container.decodeIfPresent([String].self, forKey: .tools) ?? []
        self.systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        ?? container.decodeIfPresent(String.self, forKey: .systemMessage)
        self.maxThoughts = try container.decodeIfPresent(Int.self, forKey: .maxThoughts) ?? 10
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        self.agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(allowedSteps, forKey: .allowedSteps)
        try container.encode(tools, forKey: .tools)
        try container.encodeIfPresent(systemPrompt, forKey: .systemPrompt)
        try container.encode(maxThoughts, forKey: .maxThoughts)
        try container.encode(temperature, forKey: .temperature)
        try container.encodeIfPresent(agentID, forKey: .agentID)
    }
    
    /// Traditional chat configuration (no steps, direct response)
    public static var chat: AgentConfig {
        AgentConfig(allowedSteps: [])
    }
    
    /// ReAct agent configuration (thought → action with automatic observation)
    public static func react(
        tools: [String],
        maxThoughts: Int = 20,
        systemPrompt: String? = nil,
        agentID: String? = nil
    ) -> AgentConfig {
        AgentConfig(
            allowedSteps: [.action],
            tools: tools,
            systemPrompt: systemPrompt,
            maxThoughts: maxThoughts,
            agentID: agentID
        )
    }

    /// Plan-and-Execute agent configuration
    public static func planAndExecute(
        tools: [String],
        maxThoughts: Int = 20,
        systemPrompt: String? = nil,
        agentID: String? = nil
    ) -> AgentConfig {
        AgentConfig(
            allowedSteps: [.plan, .action],
            tools: tools,
            systemPrompt: systemPrompt,
            maxThoughts: maxThoughts,
            agentID: agentID
        )
    }

    /// Reflexion agent configuration (with self-reflection)
    public static func reflexion(
        tools: [String],
        maxThoughts: Int = 20,
        systemPrompt: String? = nil,
        agentID: String? = nil
    ) -> AgentConfig {
        AgentConfig(
            allowedSteps: [.action, .reflection],
            tools: tools,
            systemPrompt: systemPrompt,
            maxThoughts: maxThoughts,
            agentID: agentID
        )
    }
    
    /// Strategy instructions for the agent loop.
    ///
    /// Now that we use **native tool-use** (provider returns structured tool_calls
    /// instead of stringified JSON), the model no longer needs to be told *how*
    /// to format its output. This block is just a few high-level behavioral
    /// reminders. The bulk of the agent's persona/workflow lives in
    /// `systemPrompt` (or, for client-side agents, server-injected via agentID).
    private func generateStrategyInstructions() -> String {
        guard !allowedSteps.isEmpty else { return "" }
        return """
            ## Workflow

            You are an agent. To finish a task you may call tools across multiple turns.
            On each turn you can:
              - reply with plain content (this is your reasoning, shown to the user);
              - or call one or more tools (the system will run them and feed the results back).

            When you have done enough, simply reply with the final answer in plain content
            and call no tool. That ends the loop.

            ## Behavioral guidance

            - Do not guess values that a tool can verify. Prefer calling a tool over answering from memory.
            - If a tool errors or returns an unexpected result, do not retry the same call blindly —
              switch strategy, or surface the failure honestly to the user.
            - When the request is multi-step, keep going until every step is observably done.
            - Stay concise. Reasoning content should explain *what you are about to do*, not restate the obvious.

            ## Tone

            - Only use emojis if the user explicitly requests it.
            - Reply in the same language as the user's question.
            - Never invent URLs unless explicitly provided or strictly required.
            """
    }

    /// Combined prompt for the agent (system prompt + lightweight strategy instructions).
    /// Resume-style server-side agents still combine these into a single system message.
    /// Client-side agents (excalidraw-canvas) get systemPrompt injected by server, and
    /// only the strategy part comes from here.
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
