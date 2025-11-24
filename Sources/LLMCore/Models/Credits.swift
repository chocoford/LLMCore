//
//  Credits.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation

// MARK: - Transaction Metadata Protocol
public enum CreditDeductionSource: String, ContentModel {
    case free
    case periodic
    case permanent
}
public protocol CreditTransactionMetadata: ContentModel {
    var deductionSources: [CreditDeductionSource: Double] { get }
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

public struct TransactionHistory<Metadata: ContentModel>: ContentModel {
    public var transactions: [CreditsTransaction<Metadata>]
    public var totalCount: Int
    public var page: Int
    public var pageSize: Int

    public init(
        transactions: [CreditsTransaction<Metadata>],
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

public struct CreditsTransaction<Metadata: ContentModel>: ContentModel, Identifiable {
    public var id: String
    public var type: CreditsTransactionType
    public var amount: Double              // Positive for additions, negative for usage
    public var balance: Double             // Balance after transaction (calculated, not from DB)
    public var transactionID: String?      // Apple transaction ID for purchases/subscriptions
    public var reason: String?             // Human-readable reason
    public var createdAt: Date
    public var metadata: Metadata?         // Additional info from client-side source

    public init(
        id: String,
        type: CreditsTransactionType,
        amount: Double,
        balance: Double,
        transactionID: String? = nil,
        reason: String? = nil,
        createdAt: Date,
        metadata: Metadata? = nil
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.balance = balance
        self.transactionID = transactionID
        self.reason = reason
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public enum CreditsTransactionType: String, ContentModel {
    case purchase           // Bought credits
    case subscription       // Monthly subscription quota
    case usage             // Used for API calls
    case refund            // Refunded credits
    case bonus             // Promotional credits
}
