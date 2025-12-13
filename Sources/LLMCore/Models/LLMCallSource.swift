//
//  LLMCallSource.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation

/// Identifies the source of an LLM call for tracking and analytics
public enum LLMCallSource: Codable, Sendable, Equatable {
    /// Call from a mobile App (identified by bundle ID)
    case app(bundleID: String)

    /// Call from Web (identified by bundle ID)
    case web(bundleID: String)

    /// Call from a Domain Agent (identified by domain name)
    case domainAgent(domain: String)

    /// Internal/system call (for testing, admin operations, etc.)
    case system

    public var sourceType: String {
        switch self {
        case .app:
            return "app"
        case .web:
            return "web"
        case .domainAgent:
            return "domain_agent"
        case .system:
            return "system"
        }
    }

    public var sourceIdentifier: String? {
        switch self {
        case .app(let bundleID):
            return bundleID
        case .web(let bundleID):
            return bundleID
        case .domainAgent(let domain):
            return domain
        case .system:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .app(let bundleID):
            return "App: \(bundleID)"
        case .web(let bundleID):
            return "Web: \(bundleID)"
        case .domainAgent(let domain):
            return "Domain Agent: \(domain)"
        case .system:
            return "System"
        }
    }

    // Codable implementation
    private enum CodingKeys: String, CodingKey {
        case type
        case identifier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "app":
            let bundleID = try container.decode(String.self, forKey: .identifier)
            self = .app(bundleID: bundleID)
        case "web":
            let bundleID = try container.decode(String.self, forKey: .identifier)
            self = .web(bundleID: bundleID)
        case "domain_agent":
            let domain = try container.decode(String.self, forKey: .identifier)
            self = .domainAgent(domain: domain)
        case "system":
            self = .system
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown source type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceType, forKey: .type)
        if let identifier = sourceIdentifier {
            try container.encode(identifier, forKey: .identifier)
        }
    }
}
