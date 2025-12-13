//
//  LLMStats.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation

// MARK: - LLM Statistics Response Models

public struct LLMStatsOverviewResponse: ContentModel {
    public let totalCalls: Int
    public let totalTokens: Int
    public let totalCostUSD: Double
    public let totalCreditsUsed: Double
    public let timeRange: TimeRangeResponse

    public init(totalCalls: Int, totalTokens: Int, totalCostUSD: Double, totalCreditsUsed: Double, timeRange: TimeRangeResponse) {
        self.totalCalls = totalCalls
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.totalCreditsUsed = totalCreditsUsed
        self.timeRange = timeRange
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
    public let createdAt: Date

    public init(id: UUID, userIdentityID: UUID, sourceType: String, sourceID: String?, model: String, promptTokens: Int, completionTokens: Int, totalTokens: Int, costUSD: Double, creditsUsed: Double?, conversationID: String?, latencyMs: Int?, error: String?, createdAt: Date) {
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
