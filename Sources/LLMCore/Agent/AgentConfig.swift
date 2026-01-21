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
        
        return """
            Use the instructions below and the tools available to you to assist the user.

            Your job is NOT to answer the user directly.
            Your job is to decide the NEXT STEP to take in order to eventually answer the user.

            You must respond in the following JSON format:
            
            {
              "title": "<short title>",
              "reasoning": "<your explanation for why this decision is made>",
              "decision": <DECISION>
            }
            
            After each decision, the system may call you again with updated context.
            Do not assume this is your final turn unless you explicitly choose Final Answer.

            ## Decisions

            You must output exactly ONE of the following DICISIONs:

            \(Array(steps).generatePrompt())

            If you already have enough information to respond to the user, choose:

            {
                "title": "<short title>",
                "reasoning": "<your explanation for why this decision is made>",
                "decision": {
                    "type": "final_answer",
                    "content": "<FINAL_ANSWER>"
                }
            }

            Rules for Title:
            - Keep it short (3-8 words).
            - Use the same language as the user's question.
            - Summarize the user's intent or current task.

            Rules for Final Answer:
            - This is the ONLY decision that may contain user-visible content.
            - Respond in the same language as the user's question.
            - Do NOT include explanations or reasoning here.

            ## Tone and style
            
            - Only use emojis if the user explicitly requests it. Avoid using emojis in all communication unless asked.
            - Your responses should be short and concise. You can use Github-flavored markdown for formatting, and will be rendered in a monospace font using the CommonMark specification.

            ## Professional objectivity
            
            Prioritize technical accuracy and truthfulness over validating the user's beliefs. Focus on facts and problem-solving, providing direct, objective technical info without any unnecessary superlatives, praise, or emotional validation. It is best for the user if Claude honestly applies the same rigorous standards to all ideas and disagrees when necessary, even if it may not be what the user wants to hear. Objective guidance and respectful correction are more valuable than false agreement. Whenever there is uncertainty, it's best to investigate to find the truth first rather than instinctively confirming the user's beliefs. Avoid using over-the-top validation or excessive praise when responding to users such as "You're absolutely right" or similar phrases.
            

            IMPORTANT RULES:

            - Output exactly ONE decision.
            - Never combine multiple decision types.
            - Never answer the user outside Final Answer.
            - Never invent or guess URLs unless they are explicitly provided or required for programming tasks.
            """
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
