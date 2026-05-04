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

    /// JSON Schema describing the tool's input. 主入口是这个 enum, 不再要求 Swift 平铺结构。
    /// 简单工具用 `.parameters(...)`, 复杂工具用 `.bundleResource(...)` 加载 .json。
    var inputSchema: ToolInputSchema { get }

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
    /// 通过 `inputSchema.resolve()` 把 enum 各分支统一成 raw JSON Schema (AnyCodable)。
    var schema: ToolSchema {
        get throws {
            ToolSchema(
                name: name,
                description: description,
                parameters: try inputSchema.resolve()
            )
        }
    }
}

/// Tool 输入参数 schema 的来源。
///
/// - `.parameters`: Swift 便利构造, 适合简单平铺 object
/// - `.bundleResource`: 从 Bundle 里加载 .json 文件 (复杂 schema 推荐)
/// - `.raw`: 直接给 raw JSON Schema (programmatic 生成 / inline 大字典)
public enum ToolInputSchema: Sendable {
    case parameters(ToolParameters)
    case bundleResource(name: String, bundle: Bundle = .main, ext: String = "json")
    case raw(AnyCodable)

    /// 把 enum 各分支统一解析成 raw JSON Schema (= AnyCodable 字典)。
    public func resolve() throws -> AnyCodable {
        switch self {
        case .parameters(let params):
            return Self.derive(from: params)
        case .bundleResource(let name, let bundle, let ext):
            return try Self.loadJSON(name: name, bundle: bundle, ext: ext)
        case .raw(let any):
            return any
        }
    }

    private static func derive(from parameters: ToolParameters) -> AnyCodable {
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
        return AnyCodable(schema)
    }

    private static func loadJSON(name: String, bundle: Bundle, ext: String) throws -> AnyCodable {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw ToolInputSchemaError.resourceNotFound(name: name, ext: ext, bundle: bundle.bundleIdentifier ?? "<unknown>")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AnyCodable.self, from: data)
    }
}

public enum ToolInputSchemaError: LocalizedError {
    case resourceNotFound(name: String, ext: String, bundle: String)

    public var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name, let ext, let bundle):
            return "Tool input schema resource '\(name).\(ext)' not found in bundle '\(bundle)'"
        }
    }
}

/// Tool parameter schema (Swift 便利结构, 仅适合简单平铺 object)。
/// 复杂 schema (oneOf / $ref / 嵌套 object / array) 请改用 `.bundleResource` 或 `.raw`。
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
