//
//  AgentStep.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation

/// Represents a single step in an agent's execution
public struct AgentStep: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var stepNumber: Int
    public var type: StepType
    public var content: String
    public var title: String?
    public var timestamp: Date

    public enum StepType: String, Codable, Sendable {
        case thought      // Agent's reasoning/thinking
        case action       // Tool invocation
        case observation  // Tool execution result
        case plan         // Planning step
        case reflection   // Self-reflection
    }

    public init(
        id: UUID = UUID(),
        stepNumber: Int,
        type: StepType,
        content: String,
        title: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.stepNumber = stepNumber
        self.type = type
        self.content = content
        self.title = title
        self.timestamp = timestamp
    }
}

