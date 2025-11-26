//
//  Credits.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation
@preconcurrency import AnyCodable

// MARK: - Transaction Metadata Protocol
public enum CreditDeductionSource: String, ContentModel {
    case free
    case periodic
    case permanent
}

public protocol CreditTransactionMetadata: ContentModel {
    var model: String { get }                                      // Server-side: Model used
    var usage: Usage { get }                                  // Server-side: Token usage
    var deductionSources: [CreditDeductionSource: Double] { get }  // Server-side: Balance pools used
}

// MARK: - Credits Info
public struct CreditsInfo: ContentModel {
    public var balance: Double              // Total available credits
    public var subscription: SubscriptionInfo?
    public var purchasedCredits: Double     // Credits purchased outside subscription

    public init(
        balance: Double,
        subscription: SubscriptionInfo? = nil,
        purchasedCredits: Double
    ) {
        self.balance = balance
        self.subscription = subscription
        self.purchasedCredits = purchasedCredits
    }
}

public struct SubscriptionInfo: ContentModel {
    public var monthlyQuota: Double         // Monthly quota from subscription
    public var usedQuota: Double            // Used quota this month
    public var remainingQuota: Double       // Remaining quota this month
    public var renewalDate: Date            // When quota resets

    public init(
        monthlyQuota: Double,
        usedQuota: Double,
        remainingQuota: Double,
        renewalDate: Date
    ) {
        self.monthlyQuota = monthlyQuota
        self.usedQuota = usedQuota
        self.remainingQuota = remainingQuota
        self.renewalDate = renewalDate
    }
}

// MARK: - Transaction History

public protocol CreditsTransactionMetaData: ContentModel {
    associatedtype Context: ContentModel
    
    var id: String { get }
    var date: Date { get }
    
    var userInfo: [String : AnyCodable] { get }
    var context: Context { get }
}

public struct TransactionHistory: ContentModel {
    public var transactions: [CreditsTransaction]
    public var totalCount: Int
    public var page: Int
    public var pageSize: Int

    public init(
        transactions: [CreditsTransaction],
        totalCount: Int,
        page: Int,
        pageSize: Int
    ) {
        self.transactions = transactions
        self.totalCount = totalCount
        self.page = page
        self.pageSize = pageSize
    }
}

public struct CreditsTransaction: ContentModel, Identifiable {
    public var id: String
    public var type: CreditsTransactionType
    public var amount: Double              // Positive for additions, negative for usage
    public var transactionID: String?      // Apple transaction ID for purchases/subscriptions
    public var reason: String?             // Human-readable reason
    public var createdAt: Date
    public var metadata: [String : AnyCodable]?         // Additional info from client-side source

    public init(
        id: String,
        type: CreditsTransactionType,
        amount: Double,
        transactionID: String? = nil,
        reason: String? = nil,
        createdAt: Date,
        metadata: [String : AnyCodable]?
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.transactionID = transactionID
        self.reason = reason
        self.createdAt = createdAt
        self.metadata = metadata
    }
    
    
    // convenient functions for metadata
    public func getMetadataValue<T: Codable>(key: String) -> T? {
        guard let codable = self.metadata?[key] else {
            return nil
        }
        do {
            let data = try JSONEncoder().encode(codable)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print(error)
            return nil
        }
    }

    public struct DeductionSources: Codable {
        var permanent: Double?
        var periodic: Double?
        var free: Double?
    }
    public func deductionSources() -> DeductionSources? {
        getMetadataValue(key: "deductionSources")
    }
    public func usage() -> Usage? {
        getMetadataValue(key: "usage")
    }
}

public enum CreditsTransactionType: String, ContentModel {
    /// 用户直接购买（一次性购买）
    case purchase

    /// 用户使用或消耗 credits（聊天、绘图等）
    case consume

    /// 推广活动奖励 / 手动发放奖励
    case promotion

    /// 苹果或系统退款
    case refund

    // MARK: 订阅相关
    /// 订阅
    case subscribe
    ///  重新订阅
    case resubscribe
    /// 订阅续期产生的新周期 credit 增加
    case renewal
    /// 订阅周期结束，周期性 credit 过期清零
    case expiration
}

