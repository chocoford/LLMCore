//
//  Tool.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation
@preconcurrency import AnyCodable

/// Protocol for tools that agents can use
public protocol Tool: Sendable {
    /// Unique name of the tool
    var name: String { get }

    /// Description of what the tool does
    var description: String { get }

    /// JSON schema describing the tool's parameters
    var parameters: ToolParameters { get }

    /// Execute the tool with given input
    /// - Parameter input: JSON string containing the tool input
    /// - Parameter context: Optional invocation context for tool-specific data
    /// - Returns: Tool execution result as string
    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> String
}

public extension Tool {
    func execute(_ input: String) async throws -> String {
        try await execute(input, context: nil)
    }

    /// 序列化为发给 provider 的 ToolSchema (= function schema)。
    /// 默认从 `name` / `description` / `parameters` 构造; 个别工具如果有更复杂的 JSON
    /// Schema (嵌套 object / array / oneOf) 可以重写这个属性返回原始 schema。
    var schema: ToolSchema {
        let props: [String: AnyCodable] = parameters.properties.mapValues { prop in
            var dict: [String: AnyCodable] = [
                "type": AnyCodable(prop.type),
                "description": AnyCodable(prop.description),
            ]
            if let enums = prop.enum {
                dict["enum"] = AnyCodable(enums)
            }
            return AnyCodable(dict)
        }
        let schema: [String: AnyCodable] = [
            "type": AnyCodable(parameters.type),
            "properties": AnyCodable(props),
            "required": AnyCodable(parameters.required),
        ]
        return ToolSchema(
            name: name,
            description: description,
            parameters: AnyCodable(schema)
        )
    }
}

/// Tool parameter schema
public struct ToolParameters: Codable, Sendable {
    public var type: String
    public var properties: [String: ParameterProperty]
    public var required: [String]

    public init(
        type: String = "object",
        properties: [String: ParameterProperty],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

/// Individual parameter property
public struct ParameterProperty: Codable, Sendable {
    public var type: String
    public var description: String
    public var `enum`: [String]?

    public init(type: String, description: String, enum: [String]? = nil) {
        self.type = type
        self.description = description
        self.enum = `enum`
    }
}

/// Tool execution error
public enum ToolError: LocalizedError {
    case invalidInput(String)
    case executionFailed(String)
    case toolNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        }
    }
}
