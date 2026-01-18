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
                When you need to use a tool, respond with:
                Action: <tool_name>
                Input: <json_input>

                After the action executes, you will receive an observation with the result.
                """
        case .plan:
            return """
                When you need to create a plan, respond with:
                Plan: <your_plan>
                """
        case .reflection:
            return """
                When you need to reflect on your actions, respond with:
                Reflection: <your_reflection>
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

    public init(
        allowedSteps: Set<AgentStepType> = [],
        tools: [String] = [],
        systemPrompt: String? = nil,
        maxThoughts: Int = 10,
        temperature: Double = 0.7
    ) {
        self.allowedSteps = allowedSteps
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.maxThoughts = maxThoughts
        self.temperature = temperature
    }

    private enum CodingKeys: String, CodingKey {
        case allowedSteps
        case tools
        case systemPrompt
        case systemMessage
        case maxThoughts
        case temperature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allowedSteps = try container.decodeIfPresent(Set<AgentStepType>.self, forKey: .allowedSteps) ?? []
        self.tools = try container.decodeIfPresent([String].self, forKey: .tools) ?? []
        self.systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
            ?? container.decodeIfPresent(String.self, forKey: .systemMessage)
        self.maxThoughts = try container.decodeIfPresent(Int.self, forKey: .maxThoughts) ?? 10
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(allowedSteps, forKey: .allowedSteps)
        try container.encode(tools, forKey: .tools)
        try container.encodeIfPresent(systemPrompt, forKey: .systemPrompt)
        try container.encode(maxThoughts, forKey: .maxThoughts)
        try container.encode(temperature, forKey: .temperature)
    }

    /// Traditional chat configuration (no steps, direct response)
    public static var chat: AgentConfig {
        AgentConfig(allowedSteps: [])
    }

    /// ReAct agent configuration (thought → action with automatic observation)
    public static func react(
        tools: [String],
        maxThoughts: Int = 10,
        systemPrompt: String? = nil
    ) -> AgentConfig {
        AgentConfig(
            allowedSteps: [.action],
            tools: tools,
            systemPrompt: systemPrompt,
            maxThoughts: maxThoughts
        )
    }

    /// Plan-and-Execute agent configuration
    public static func planAndExecute(
        tools: [String],
        maxThoughts: Int = 10,
        systemPrompt: String? = nil
    ) -> AgentConfig {
        AgentConfig(
            allowedSteps: [.plan, .action],
            tools: tools,
            systemPrompt: systemPrompt,
            maxThoughts: maxThoughts
        )
    }

    /// Reflexion agent configuration (with self-reflection)
    public static func reflexion(
        tools: [String],
        maxThoughts: Int = 10,
        systemPrompt: String? = nil
    ) -> AgentConfig {
        AgentConfig(
            allowedSteps: [.action, .reflection],
            tools: tools,
            systemPrompt: systemPrompt,
            maxThoughts: maxThoughts
        )
    }

    /// Generate strategy instructions based on allowed steps
    /// - Returns: Combined instruction text from all allowed steps
    private func generateStrategyInstructions() -> String {
        let steps = allowedSteps
        let finalAnswerToolName = "final_answer"
        let thoughtKeywordNotice = "DO NOT output any action keywords (Action:, Plan:, Reflection:) in your thought."

        let finalAnswerInstruction: String
        if steps.isEmpty {
            finalAnswerInstruction = """
            After your thought is complete, respond with:
            Action: \(finalAnswerToolName)
            Input: {"answer": "<your_answer>"}
            """
        } else {
            finalAnswerInstruction = """
            After your thought is complete:
            If you already have enough information, respond with:
            Action: \(finalAnswerToolName)
            Input: {"answer": "<your_answer>"}
            Otherwise, if another format is allowed, output exactly ONE of the allowed formats on a new line.
            """
        }

        let finalAnswerKeywords = """
        When providing the final answer, respond in the same language as the user's question.
        CRITICAL: You MUST use the EXACT English keywords "Action:" and "Input:" shown above.
        DO NOT translate these keywords to any other language. The system parser only recognizes these English keywords.
        """

        return """
        # Strategy Instructions

        Think step by step about what you need to do next.
        You should reach the final answer by thinking the problem through, and when you do, always frame your thoughts as "the user asked me to xxx."

        IMPORTANT: Your thought should ONLY contain your reasoning process.
        \(thoughtKeywordNotice)
        """
        + finalAnswerInstruction
        + {
            "\n\n" + Array(steps).generatePrompt()
        }()
        + "\n\n" + finalAnswerKeywords

//        IMPORTANT - Final Answer Format:
//        When you have enough information to answer the user's question, you MUST respond with:
//        Final Answer: <your_answer>
//
//        This is the ONLY way to complete the task. Do not just provide an answer without this format.
//
    }

    /// Combined prompt for the agent (system prompt + strategy instructions).
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
