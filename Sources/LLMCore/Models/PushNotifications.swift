//
//  PushNotifications.swift
//  LLMCore
//

import Foundation

public enum PushPlatform: String, ContentModel, CaseIterable {
    case apns
}

public enum PushEnvironment: String, ContentModel, CaseIterable {
    case sandbox = "Sandbox"
    case production = "Production"
}

public enum PushDeviceTokenScope: String, ContentModel, CaseIterable {
    case admin
    case user
}

public struct RegisterPushDeviceTokenRequest: ContentModel {
    public let token: String
    public let platform: PushPlatform?
    public let environment: PushEnvironment?
    /// Required for admin tokens. Ignored for user tokens, where topic is derived from AppConfig.
    public let topic: String?

    public init(
        token: String,
        platform: PushPlatform? = nil,
        environment: PushEnvironment? = nil,
        topic: String? = nil
    ) {
        self.token = token
        self.platform = platform
        self.environment = environment
        self.topic = topic
    }
}

public struct UnregisterPushDeviceTokenRequest: ContentModel {
    public let token: String
    public let platform: PushPlatform?

    public init(
        token: String,
        platform: PushPlatform? = nil
    ) {
        self.token = token
        self.platform = platform
    }
}

public struct PushDeviceTokenResponse: ContentModel {
    public let id: UUID
    public let scope: PushDeviceTokenScope
    public let platform: PushPlatform
    public let environment: PushEnvironment
    public let topic: String
    public let enabled: Bool
    public let lastSeenAt: Date
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: UUID,
        scope: PushDeviceTokenScope,
        platform: PushPlatform,
        environment: PushEnvironment,
        topic: String,
        enabled: Bool,
        lastSeenAt: Date,
        createdAt: Date?,
        updatedAt: Date?
    ) {
        self.id = id
        self.scope = scope
        self.platform = platform
        self.environment = environment
        self.topic = topic
        self.enabled = enabled
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
