//
//  AgentDirective.swift
//  LLMCore
//
//  Created by Codex
//

import Foundation

/// Directive produced after a thought step, describing the next action to take.
public enum AgentDirective: Sendable, Equatable {
    case plan(String)
    case reflection(String)
    case action(ToolCall)
    case finalAnswer(String)
}
