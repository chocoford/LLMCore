//
//  Admin.swift
//  LLMCore
//
//  Created by Chocoford on 11/4/25.
//

import Foundation
@preconcurrency import AnyCodable

// MARK: - Enums

public enum AppPlatform: String, Codable, Sendable {
    case apple
    case web
    case weixinMiniProgram
}

// MARK: - Admin Response Models

public struct UserResponse: ContentModel {
    public let id: UUID
    public let email: String?

    public init(id: UUID, email: String?) {
        self.id = id
        self.email = email
    }
}

public struct UserIdentityResponse: ContentModel {
    public let id: UUID
    public let userId: UUID?
    public let provider: String
    public let externalId: String
    public let verified: Bool

    public init(id: UUID, userId: UUID?, provider: String, externalId: String, verified: Bool) {
        self.id = id
        self.userId = userId
        self.provider = provider
        self.externalId = externalId
        self.verified = verified
    }
}

public struct CreditResponse: ContentModel {
    public let id: UUID
    public let userIdentityId: UUID
    public let permanentBalance: Double
    public let periodicBalance: Double
    public let periodicStart: Date?
    public let periodicExpiration: Date?
    public let freeDailyCredits: Double

    public init(id: UUID, userIdentityId: UUID, permanentBalance: Double, periodicBalance: Double, periodicStart: Date?, periodicExpiration: Date?, freeDailyCredits: Double) {
        self.id = id
        self.userIdentityId = userIdentityId
        self.permanentBalance = permanentBalance
        self.periodicBalance = periodicBalance
        self.periodicStart = periodicStart
        self.periodicExpiration = periodicExpiration
        self.freeDailyCredits = freeDailyCredits
    }
}

public struct CreditTransactionResponse: ContentModel {
    public let id: UUID
    public let userIdentityId: UUID
    public let amount: Double
    public let type: String
    public let transactionId: String?
    public let reason: String?
    public let metadata: String?  // JSON string
    public let createdAt: Date?

    public init(
        id: UUID,
        userIdentityId: UUID,
        amount: Double,
        type: String,
        transactionId: String?,
        reason: String?,
        metadata: String?,
        createdAt: Date?
    ) {
        self.id = id
        self.userIdentityId = userIdentityId
        self.amount = amount
        self.type = type
        self.transactionId = transactionId
        self.reason = reason
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct PromotionResponse: ContentModel {
    public let id: UUID
    public let title: String
    public let credits: Double
    public let type: String
    public let startAt: Date
    public let endAt: Date?

    public init(id: UUID, title: String, credits: Double, type: String, startAt: Date, endAt: Date?) {
        self.id = id
        self.title = title
        self.credits = credits
        self.type = type
        self.startAt = startAt
        self.endAt = endAt
    }
}

public struct PromotionClaimResponse: ContentModel {
    public let id: UUID
    public let userIdentityId: UUID
    public let promotionEventId: UUID
    public let claimedAt: Date?

    public init(id: UUID, userIdentityId: UUID, promotionEventId: UUID, claimedAt: Date?) {
        self.id = id
        self.userIdentityId = userIdentityId
        self.promotionEventId = promotionEventId
        self.claimedAt = claimedAt
    }
}

public struct SubscriptionEventResponse: ContentModel {
    public let id: UUID
    public let userIdentityId: UUID
    public let provider: String
    public let productId: String
    public let type: String
    public let status: String
    public let rawPayload: String?
    public let processed: Bool
    public let createdAt: Date?

    public init(id: UUID, userIdentityId: UUID, provider: String, productId: String, type: String, status: String, rawPayload: String?, processed: Bool, createdAt: Date?) {
        self.id = id
        self.userIdentityId = userIdentityId
        self.provider = provider
        self.productId = productId
        self.type = type
        self.status = status
        self.rawPayload = rawPayload
        self.processed = processed
        self.createdAt = createdAt
    }
}

public struct AppConfigResponse: ContentModel {
    public let id: UUID
    public let bundleId: String
    public let platform: AppPlatform
    public let ascAppId: Int64?
    public let appSecret: String?
    public let allowAnon: Bool
    public let initialFreeCredits: Double
    public let freeDailyCredits: Double
    public let freeTierRateLimit: Int
    public let fixedCreditsPerCall: Double?
    public let creditsPerUsd: Double

    public init(id: UUID, bundleId: String, platform: AppPlatform, ascAppId: Int64?, appSecret: String?, allowAnon: Bool, initialFreeCredits: Double, freeDailyCredits: Double, freeTierRateLimit: Int, fixedCreditsPerCall: Double?, creditsPerUsd: Double) {
        self.id = id
        self.bundleId = bundleId
        self.platform = platform
        self.ascAppId = ascAppId
        self.appSecret = appSecret
        self.allowAnon = allowAnon
        self.initialFreeCredits = initialFreeCredits
        self.freeDailyCredits = freeDailyCredits
        self.freeTierRateLimit = freeTierRateLimit
        self.fixedCreditsPerCall = fixedCreditsPerCall
        self.creditsPerUsd = creditsPerUsd
    }
}

public struct AppProductConfigResponse: ContentModel {
    public let id: UUID
    public let productId: String
    public let type: String
    public let credits: Double
    public let subscriptionGroupID: String?
    public let appConfigId: UUID

    public init(id: UUID, productId: String, type: String, credits: Double, subscriptionGroupID: String?, appConfigId: UUID) {
        self.id = id
        self.productId = productId
        self.type = type
        self.credits = credits
        self.subscriptionGroupID = subscriptionGroupID
        self.appConfigId = appConfigId
    }
}

// MARK: - Admin Request Models

public struct PromotionCreateRequest: ContentModel {
    public let title: String
    public let credits: Double
    public let type: String
    public let startAt: Date
    public let endAt: Date?

    public init(title: String, credits: Double, type: String, startAt: Date, endAt: Date?) {
        self.title = title
        self.credits = credits
        self.type = type
        self.startAt = startAt
        self.endAt = endAt
    }
}

public struct AppConfigCreateRequest: ContentModel {
    public let bundleId: String
    public let platform: AppPlatform
    public let ascAppId: Int64?
    public let appSecret: String?
    public let allowAnon: Bool
    public let initialFreeCredits: Double
    public let freeDailyCredits: Double
    public let freeTierRateLimit: Int
    public let fixedCreditsPerCall: Double?
    public let creditsPerUsd: Double

    public init(bundleId: String, platform: AppPlatform, ascAppId: Int64?, appSecret: String?, allowAnon: Bool, initialFreeCredits: Double, freeDailyCredits: Double, freeTierRateLimit: Int, fixedCreditsPerCall: Double?, creditsPerUsd: Double) {
        self.bundleId = bundleId
        self.platform = platform
        self.ascAppId = ascAppId
        self.appSecret = appSecret
        self.allowAnon = allowAnon
        self.initialFreeCredits = initialFreeCredits
        self.freeDailyCredits = freeDailyCredits
        self.freeTierRateLimit = freeTierRateLimit
        self.fixedCreditsPerCall = fixedCreditsPerCall
        self.creditsPerUsd = creditsPerUsd
    }
}

public struct AppConfigUpdateRequest: ContentModel {
    public let bundleId: String
    public let platform: AppPlatform
    public let ascAppId: Int64?
    public let appSecret: String?
    public let allowAnon: Bool
    public let initialFreeCredits: Double
    public let freeDailyCredits: Double
    public let freeTierRateLimit: Int
    public let fixedCreditsPerCall: Double?
    public let creditsPerUsd: Double

    public init(bundleId: String, platform: AppPlatform, ascAppId: Int64?, appSecret: String?, allowAnon: Bool, initialFreeCredits: Double, freeDailyCredits: Double, freeTierRateLimit: Int, fixedCreditsPerCall: Double?, creditsPerUsd: Double) {
        self.bundleId = bundleId
        self.platform = platform
        self.ascAppId = ascAppId
        self.appSecret = appSecret
        self.allowAnon = allowAnon
        self.initialFreeCredits = initialFreeCredits
        self.freeDailyCredits = freeDailyCredits
        self.freeTierRateLimit = freeTierRateLimit
        self.fixedCreditsPerCall = fixedCreditsPerCall
        self.creditsPerUsd = creditsPerUsd
    }
}

public struct AppProductConfigCreateRequest: ContentModel {
    public let productId: String
    public let type: String
    public let credits: Double
    public let subscriptionGroupID: String?
    public let appConfigId: UUID

    public init(productId: String, type: String, credits: Double, subscriptionGroupID: String? = nil, appConfigId: UUID) {
        self.productId = productId
        self.type = type
        self.credits = credits
        self.subscriptionGroupID = subscriptionGroupID
        self.appConfigId = appConfigId
    }
}

// MARK: - Model Pricing

public struct ModelPricingResponse: ContentModel {
    public let modelId: String
    public let prompt: Double?
    public let completion: Double?
    public let request: Double?
    public let image: Double?
    public let webSearch: Double?
    public let internalReasoning: Double?
    public let inputCacheRead: Double?
    public let audio: Double?
    public let inputCacheWrite: Double?

    public init(modelId: String, prompt: Double?, completion: Double?, request: Double?, image: Double?, webSearch: Double?, internalReasoning: Double?, inputCacheRead: Double?, audio: Double?, inputCacheWrite: Double?) {
        self.modelId = modelId
        self.prompt = prompt
        self.completion = completion
        self.request = request
        self.image = image
        self.webSearch = webSearch
        self.internalReasoning = internalReasoning
        self.inputCacheRead = inputCacheRead
        self.audio = audio
        self.inputCacheWrite = inputCacheWrite
    }
}

// MARK: - Logs

public struct LogEntryResponse: ContentModel {
    public let id: UUID
    public let level: String
    public let message: String
    public let metadata: [String: AnyCodable]?
    public let requestId: String?
    public let createdAt: Date

    public init(id: UUID, level: String, message: String, metadata: [String: AnyCodable]?, requestId: String?, createdAt: Date) {
        self.id = id
        self.level = level
        self.message = message
        self.metadata = metadata
        self.requestId = requestId
        self.createdAt = createdAt
    }
}

public struct LogHistoryResponse: ContentModel {
    public var logs: [LogEntryResponse]
    public var totalCount: Int
    public var page: Int
    public var pageSize: Int

    public init(logs: [LogEntryResponse], totalCount: Int, page: Int, pageSize: Int) {
        self.logs = logs
        self.totalCount = totalCount
        self.page = page
        self.pageSize = pageSize
    }
}
