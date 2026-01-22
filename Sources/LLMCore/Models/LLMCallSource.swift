//
//  LLMCallSource.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation

/// Identifies the source of an LLM call for tracking and analytics
public enum LLMCallSource: Codable, Sendable, Equatable {
    /// Call from an App (identified by bundle ID and platform)
    case app(bundleID: String, platform: AppPlatform)

    /// Call from a Domain Agent (identified by domain name)
    case domainAgent(domain: String)

    /// Internal/system call (for testing, admin operations, etc.)
    case system

    public var sourceType: String {
        switch self {
        case .app(_, let platform):
            return platform.rawValue
        case .domainAgent:
            return "domain_agent"
        case .system:
            return "system"
        }
    }

    public var sourceIdentifier: String? {
        switch self {
        case .app(let bundleID, _):
            return bundleID
        case .domainAgent(let domain):
            return domain
        case .system:
            return nil
        }
    }
    
    public var platform: AppPlatform? {
        switch self {
        case .app(_, let platform):
            return platform
        default:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .app(let bundleID, let platform):
            let platformName: String
            switch platform {
            case .apple:
                platformName = "Apple App"
            case .web:
                platformName = "Web App"
            case .weixinMiniProgram:
                platformName = "微信小程序"
            }
            return "\(platformName): \(bundleID)"
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
        case platform
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "apple", "web", "weixinMiniProgram":
            let bundleID = try container.decode(String.self, forKey: .identifier)
            let platformString = try container.decodeIfPresent(String.self, forKey: .platform) ?? type
            let platform = AppPlatform(rawValue: platformString) ?? .apple
            self = .app(bundleID: bundleID, platform: platform)
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
        if let platform = platform {
            try container.encode(platform.rawValue, forKey: .platform)
        }
    }
}
