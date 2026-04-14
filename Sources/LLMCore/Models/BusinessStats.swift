//
//  BusinessStats.swift
//  LLMCore
//
//  Dashboard 业务洞察用的聚合 DTO。分组原则:
//  - User/Revenue/Credits/LLM 四大类
//  - 所有带 `date` 字段的都是 "yyyy-MM-dd" 字符串,便于前端直接丢给 Chart
//

import Foundation

// MARK: - Business Overview (顶部概览卡)

public struct BusinessOverviewResponse: ContentModel {
    public let revenueCents: Int        // 周期内 paid 订单总金额(分)
    public let newUsers: Int            // 周期内新建 UserIdentity 数
    public let activeUsers: Int         // 周期内至少一次 LLM 调用的独立用户数
    public let llmCostUSD: Double       // 周期内 LLM 总 cost (我方成本)
    public let timeRange: TimeRangeResponse

    // 上一周期的同维度数据 (同样 days 跨度,刚好紧挨在 current 之前)。
    // 均为可选: 若周期跨度太长超出数据起点,服务端可传 nil,客户端不展示对比。
    public let previousRevenueCents: Int?
    public let previousNewUsers: Int?
    public let previousActiveUsers: Int?
    public let previousLLMCostUSD: Double?

    public init(
        revenueCents: Int,
        newUsers: Int,
        activeUsers: Int,
        llmCostUSD: Double,
        timeRange: TimeRangeResponse,
        previousRevenueCents: Int? = nil,
        previousNewUsers: Int? = nil,
        previousActiveUsers: Int? = nil,
        previousLLMCostUSD: Double? = nil
    ) {
        self.revenueCents = revenueCents
        self.newUsers = newUsers
        self.activeUsers = activeUsers
        self.llmCostUSD = llmCostUSD
        self.timeRange = timeRange
        self.previousRevenueCents = previousRevenueCents
        self.previousNewUsers = previousNewUsers
        self.previousActiveUsers = previousActiveUsers
        self.previousLLMCostUSD = previousLLMCostUSD
    }
}

// MARK: - Revenue

/// 每日收入 (可按 provider 分组后在前端聚合成堆叠条形图)
public struct RevenueStatsItem: ContentModel {
    public let date: String
    public let provider: String         // "wechatPay" / "wechatVirtualPay" / "appStore" / ...
    public let amountCents: Int
    public let orderCount: Int

    public init(date: String, provider: String, amountCents: Int, orderCount: Int) {
        self.date = date
        self.provider = provider
        self.amountCents = amountCents
        self.orderCount = orderCount
    }
}

// MARK: - User Growth

public struct UserGrowthStatsItem: ContentModel {
    public let date: String
    public let bundleID: String         // AppConfig.bundleID,便于前端分组
    public let platform: String         // apple / web / weixinMiniProgram
    public let newUsers: Int

    public init(date: String, bundleID: String, platform: String, newUsers: Int) {
        self.date = date
        self.bundleID = bundleID
        self.platform = platform
        self.newUsers = newUsers
    }
}

// MARK: - DAU

public struct DAUStatsItem: ContentModel {
    public let date: String
    public let bundleID: String
    public let dau: Int                 // 当日 distinct user_identity_id

    public init(date: String, bundleID: String, dau: Int) {
        self.date = date
        self.bundleID = bundleID
        self.dau = dau
    }
}

// MARK: - Top Products

public struct TopProductStatsItem: ContentModel {
    public let productID: String
    public let orderCount: Int
    public let revenueCents: Int
    public let totalCredits: Double

    public init(productID: String, orderCount: Int, revenueCents: Int, totalCredits: Double) {
        self.productID = productID
        self.orderCount = orderCount
        self.revenueCents = revenueCents
        self.totalCredits = totalCredits
    }
}

// MARK: - Order Conversion Funnel

public struct OrderConversionStatsItem: ContentModel {
    public let date: String
    public let created: Int             // 当日创建
    public let paid: Int                // 当日支付成功
    public let refunded: Int
    public let closed: Int

    public init(date: String, created: Int, paid: Int, refunded: Int, closed: Int) {
        self.date = date
        self.created = created
        self.paid = paid
        self.refunded = refunded
        self.closed = closed
    }
}

// MARK: - Credits Economy

public struct CreditsEconomyStatsItem: ContentModel {
    public let date: String
    public let issued: Double           // 发放 (purchase + promotion + referral + achievement + subscribe/renewal)
    public let consumed: Double         // 消耗 (consume type,正值,表示花出去多少)

    public init(date: String, issued: Double, consumed: Double) {
        self.date = date
        self.issued = issued
        self.consumed = consumed
    }
}

// MARK: - Top Users

public struct TopUserStatsItem: ContentModel {
    public let userIdentityID: UUID
    public let externalID: String
    public let bundleID: String
    public let calls: Int
    public let tokens: Int
    public let costUSD: Double
    public let revenueCents: Int        // 该用户在周期内付费总额

    public init(userIdentityID: UUID, externalID: String, bundleID: String, calls: Int, tokens: Int, costUSD: Double, revenueCents: Int) {
        self.userIdentityID = userIdentityID
        self.externalID = externalID
        self.bundleID = bundleID
        self.calls = calls
        self.tokens = tokens
        self.costUSD = costUSD
        self.revenueCents = revenueCents
    }
}

// MARK: - LLM Error Rate

public struct LLMErrorRateStatsItem: ContentModel {
    public let date: String
    public let totalCalls: Int
    public let errorCalls: Int
    public let errorRate: Double        // [0, 1]

    public init(date: String, totalCalls: Int, errorCalls: Int, errorRate: Double) {
        self.date = date
        self.totalCalls = totalCalls
        self.errorCalls = errorCalls
        self.errorRate = errorRate
    }
}
