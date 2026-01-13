//
//  ToolContext.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation

public protocol ChatInvocationContext: Sendable, Codable {}

public extension ChatInvocationContext {
    func resolve<T: ToolContext>(_ type: T.Type) throws -> T {
        let data: Data
        do {
            data = try JSONEncoder().encode(self)
        } catch {
            throw ToolContextError.encodingFailed(error.localizedDescription)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ToolContextError.decodingFailed(error.localizedDescription)
        }
    }
}

public protocol ToolContext: Sendable, Codable {}

public enum ToolContextError: Error, LocalizedError {
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let message):
            return "Failed to encode ChatInvocationContext: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode ToolContext: \(message)"
        }
    }
}
