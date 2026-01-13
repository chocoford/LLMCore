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
    public var allowedSteps: Set<AgentStepType>

    /// Available tools for the agent
    public var tools: [String]

    /// System message for the agent
    public var systemMessage: String?

    /// Maximum number of thought steps allowed
    public var maxThoughts: Int

    /// Temperature for LLM sampling
    public var temperature: Double

    public init(
        allowedSteps: Set<AgentStepType> = [],
        tools: [String] = [],
        systemMessage: String? = nil,
        maxThoughts: Int = 10,
        temperature: Double = 0.7
    ) {
        self.allowedSteps = allowedSteps
        self.tools = tools
        self.systemMessage = systemMessage
        self.maxThoughts = maxThoughts
        self.temperature = temperature
    }

    /// Traditional chat configuration (no steps, direct response)
    public static var chat: AgentConfig {
        AgentConfig(allowedSteps: [])
    }

    /// ReAct agent configuration (thought → action with automatic observation)
    public static func react(tools: [String], maxThoughts: Int = 10) -> AgentConfig {
        AgentConfig(
            allowedSteps: [.action],
            tools: tools,
            maxThoughts: maxThoughts
        )
    }

    /// Plan-and-Execute agent configuration
    public static func planAndExecute(tools: [String], maxThoughts: Int = 10) -> AgentConfig {
        AgentConfig(
            allowedSteps: [.plan, .action],
            tools: tools,
            maxThoughts: maxThoughts
        )
    }

    /// Reflexion agent configuration (with self-reflection)
    public static func reflexion(tools: [String], maxThoughts: Int = 10) -> AgentConfig {
        AgentConfig(
            allowedSteps: [.action, .reflection],
            tools: tools,
            maxThoughts: maxThoughts
        )
    }

    /// Generate strategy instructions based on allowed steps
    /// - Returns: Combined instruction text from all allowed steps
    public func generateStrategyInstructions() -> String {
        var steps = allowedSteps
        if tools.isEmpty {
            steps.remove(.action)
        }
        
        return """
        Think step by step about what you need to do next.

        IMPORTANT: Your thought should ONLY contain your reasoning process.
        DO NOT output any action keywords (Action:, Plan:, Reflection:, Final Answer:) in your thought.
        """
        +
        (steps.isEmpty
        ? """
        After your thought is complete: respond with "Final Answer: <your_answer>" and complete the task.
        """
        : """
        After your thought is complete:
        If you already have enough information, respond with "Final Answer: <your_answer>" and complete the task.
        Otherwise, if another format is allowed, output exactly ONE of the allowed formats on a new line.
        """)
        + {
            "\n\n" + Array(steps).generatePrompt()
        }()
        +
        """
        When providing the Final Answer, respond in the same language as the user's question.
        CRITICAL: You MUST use the EXACT English keywords shown above.
        DO NOT translate these keywords to any other language. The system parser only recognizes these English keywords.
        """
        
//        IMPORTANT - Final Answer Format:
//        When you have enough information to answer the user's question, you MUST respond with:
//        Final Answer: <your_answer>
//        
//        This is the ONLY way to complete the task. Do not just provide an answer without this format.
//
    }
}
