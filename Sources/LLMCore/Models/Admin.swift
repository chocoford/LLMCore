//
//  Admin.swift
//  LLMCore
//
//  Created by Chocoford on 11/4/25.
//

import Foundation

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
    public let createdAt: Date?

    public init(id: UUID, userIdentityId: UUID, amount: Double, type: String, transactionId: String?, reason: String?, createdAt: Date?) {
        self.id = id
        self.userIdentityId = userIdentityId
        self.amount = amount
        self.type = type
        self.transactionId = transactionId
        self.reason = reason
        self.createdAt = createdAt
    }
}

public struct PromotionResponse: ContentModel {
    public let id: UUID
    public let title: String
    public let credits: Double
    public let type: String
    public let startAt: Date
    public let endAt: Date

    public init(id: UUID, title: String, credits: Double, type: String, startAt: Date, endAt: Date) {
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

public struct AnonUserResponse: ContentModel {
    public let id: UUID
    public let deviceId: String

    public init(id: UUID, deviceId: String) {
        self.id = id
        self.deviceId = deviceId
    }
}

public struct AnonUsageResponse: ContentModel {
    public let id: UUID
    public let anonUserId: UUID
    public let date: Date
    public let usedCredits: Double

    public init(id: UUID, anonUserId: UUID, date: Date, usedCredits: Double) {
        self.id = id
        self.anonUserId = anonUserId
        self.date = date
        self.usedCredits = usedCredits
    }
}

public struct AppConfigResponse: ContentModel {
    public let id: UUID
    public let bundleId: String
    public let ascAppId: Int64?
    public let allowAnon: Bool
    public let initialFreeCredits: Double
    public let freeDailyCredits: Double
    public let freeTierRateLimit: Int

    public init(id: UUID, bundleId: String, ascAppId: Int64?, allowAnon: Bool, initialFreeCredits: Double, freeDailyCredits: Double, freeTierRateLimit: Int) {
        self.id = id
        self.bundleId = bundleId
        self.ascAppId = ascAppId
        self.allowAnon = allowAnon
        self.initialFreeCredits = initialFreeCredits
        self.freeDailyCredits = freeDailyCredits
        self.freeTierRateLimit = freeTierRateLimit
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
    public let endAt: Date

    public init(title: String, credits: Double, type: String, startAt: Date, endAt: Date) {
        self.title = title
        self.credits = credits
        self.type = type
        self.startAt = startAt
        self.endAt = endAt
    }
}

public struct AppConfigCreateRequest: ContentModel {
    public let bundleId: String
    public let ascAppId: Int64?
    public let allowAnon: Bool
    public let initialFreeCredits: Double
    public let freeDailyCredits: Double
    public let freeTierRateLimit: Int

    public init(bundleId: String, ascAppId: Int64?, allowAnon: Bool, initialFreeCredits: Double, freeDailyCredits: Double, freeTierRateLimit: Int) {
        self.bundleId = bundleId
        self.ascAppId = ascAppId
        self.allowAnon = allowAnon
        self.initialFreeCredits = initialFreeCredits
        self.freeDailyCredits = freeDailyCredits
        self.freeTierRateLimit = freeTierRateLimit
    }
}

public struct AppConfigUpdateRequest: ContentModel {
    public let bundleId: String
    public let ascAppId: Int64?
    public let allowAnon: Bool
    public let initialFreeCredits: Double
    public let freeDailyCredits: Double
    public let freeTierRateLimit: Int

    public init(bundleId: String, ascAppId: Int64?, allowAnon: Bool, initialFreeCredits: Double, freeDailyCredits: Double, freeTierRateLimit: Int) {
        self.bundleId = bundleId
        self.ascAppId = ascAppId
        self.allowAnon = allowAnon
        self.initialFreeCredits = initialFreeCredits
        self.freeDailyCredits = freeDailyCredits
        self.freeTierRateLimit = freeTierRateLimit
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
