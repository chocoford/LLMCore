//
//  LLMStats.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation

// MARK: - LLM Geo Stats (按城市聚合的调用统计)

public struct LLMCallGeoStatsItem: ContentModel {
    public let countryCode: String?
    public let city: String?
    public let latitude: Double
    public let longitude: Double
    public let callCount: Int

    public init(countryCode: String?, city: String?, latitude: Double, longitude: Double, callCount: Int) {
        self.countryCode = countryCode
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.callCount = callCount
    }
}

public struct LLMCallGeoStatsResponse: ContentModel {
    public let items: [LLMCallGeoStatsItem]
    public let totalWithGeo: Int
    public let totalWithoutGeo: Int

    public init(items: [LLMCallGeoStatsItem], totalWithGeo: Int, totalWithoutGeo: Int) {
        self.items = items
        self.totalWithGeo = totalWithGeo
        self.totalWithoutGeo = totalWithoutGeo
    }
}

// MARK: - LLM Statistics Response Models

public struct LLMStatsOverviewResponse: ContentModel {
    public let totalCalls: Int
    public let totalTokens: Int
    public let totalCostUSD: Double
    public let totalCreditsUsed: Double
    public let timeRange: TimeRangeResponse

    // 上一周期的对照值 (同跨度,紧挨 current 之前)。nil 表示无对比。
    public let previousTotalCalls: Int?
    public let previousTotalTokens: Int?
    public let previousTotalCostUSD: Double?
    public let previousTotalCreditsUsed: Double?

    public init(
        totalCalls: Int,
        totalTokens: Int,
        totalCostUSD: Double,
        totalCreditsUsed: Double,
        timeRange: TimeRangeResponse,
        previousTotalCalls: Int? = nil,
        previousTotalTokens: Int? = nil,
        previousTotalCostUSD: Double? = nil,
        previousTotalCreditsUsed: Double? = nil
    ) {
        self.totalCalls = totalCalls
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.totalCreditsUsed = totalCreditsUsed
        self.timeRange = timeRange
        self.previousTotalCalls = previousTotalCalls
        self.previousTotalTokens = previousTotalTokens
        self.previousTotalCostUSD = previousTotalCostUSD
        self.previousTotalCreditsUsed = previousTotalCreditsUsed
    }
}

public struct TimeRangeResponse: ContentModel {
    public let from: Date
    public let to: Date

    public init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }
}

public struct SourceTypeStatsResponse: ContentModel {
    public let type: String
    public let calls: Int
    public let tokens: Int
    public let costUSD: Double
    public let creditsUsed: Double

    public init(type: String, calls: Int, tokens: Int, costUSD: Double, creditsUsed: Double) {
        self.type = type
        self.calls = calls
        self.tokens = tokens
        self.costUSD = costUSD
        self.creditsUsed = creditsUsed
    }
}

public struct SourceStatsResponse: ContentModel {
    public let sourceType: String
    public let sourceID: String
    public let calls: Int
    public let tokens: Int
    public let costUSD: Double
    public let creditsUsed: Double

    public init(sourceType: String, sourceID: String, calls: Int, tokens: Int, costUSD: Double, creditsUsed: Double) {
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.calls = calls
        self.tokens = tokens
        self.costUSD = costUSD
        self.creditsUsed = creditsUsed
    }
}

public struct ModelStatsResponse: ContentModel {
    public let model: String
    public let calls: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let costUSD: Double
    public let creditsUsed: Double

    public init(model: String, calls: Int, promptTokens: Int, completionTokens: Int, totalTokens: Int, costUSD: Double, creditsUsed: Double) {
        self.model = model
        self.calls = calls
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.creditsUsed = creditsUsed
    }
}

public struct TimelineStatsResponse: ContentModel {
    public let date: String
    public let calls: Int
    public let tokens: Int
    public let costUSD: Double
    public let creditsUsed: Double

    public init(date: String, calls: Int, tokens: Int, costUSD: Double, creditsUsed: Double) {
        self.date = date
        self.calls = calls
        self.tokens = tokens
        self.costUSD = costUSD
        self.creditsUsed = creditsUsed
    }
}

public struct LLMCallLogsResponse: ContentModel {
    public let logs: [LLMCallLogResponse]
    public let pagination: PaginationResponse

    public init(logs: [LLMCallLogResponse], pagination: PaginationResponse) {
        self.logs = logs
        self.pagination = pagination
    }
}

public struct LLMCallLogResponse: ContentModel {
    public let id: UUID
    public let userIdentityID: UUID
    public let sourceType: String
    public let sourceID: String?
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let costUSD: Double
    public let creditsUsed: Double?
    public let conversationID: String?
    public let latencyMs: Int?
    public let error: String?
    public let countryCode: String?
    public let city: String?
    public let latitude: Double?
    public let longitude: Double?
    public let createdAt: Date

    public init(
        id: UUID,
        userIdentityID: UUID,
        sourceType: String,
        sourceID: String?,
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        costUSD: Double,
        creditsUsed: Double?,
        conversationID: String?,
        latencyMs: Int?,
        error: String?,
        countryCode: String? = nil,
        city: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.userIdentityID = userIdentityID
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.creditsUsed = creditsUsed
        self.conversationID = conversationID
        self.latencyMs = latencyMs
        self.error = error
        self.countryCode = countryCode
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }
}

public struct PaginationResponse: ContentModel {
    public let page: Int
    public let pageSize: Int
    public let total: Int
    public let totalPages: Int

    public init(page: Int, pageSize: Int, total: Int, totalPages: Int) {
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.totalPages = totalPages
    }
}
