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
    public var periodicCredits: PeriodicCreditsInfo?
    public var purchasedCredits: Double     // Permanently purchased / non-expiring credits

    public init(
        balance: Double,
        periodicCredits: PeriodicCreditsInfo? = nil,
        purchasedCredits: Double
    ) {
        self.balance = balance
        self.periodicCredits = periodicCredits
        self.purchasedCredits = purchasedCredits
    }

    @available(*, deprecated, message: "Use periodicCredits instead. CreditsInfo no longer exposes subscription semantics.")
    public var subscription: PeriodicCreditsInfo? {
        get { periodicCredits }
        set { periodicCredits = newValue }
    }

    @available(*, deprecated, message: "Use init(balance:periodicCredits:purchasedCredits:) instead.")
    public init(
        balance: Double,
        subscription: PeriodicCreditsInfo?,
        purchasedCredits: Double
    ) {
        self.init(
            balance: balance,
            periodicCredits: subscription,
            purchasedCredits: purchasedCredits
        )
    }

    enum CodingKeys: String, CodingKey {
        case balance
        case periodicCredits
        case subscription
        case purchasedCredits
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.balance = try container.decode(Double.self, forKey: .balance)
        if let periodicCredits = try container.decodeIfPresent(PeriodicCreditsInfo.self, forKey: .periodicCredits) {
            self.periodicCredits = periodicCredits
        } else {
            self.periodicCredits = try container.decodeIfPresent(PeriodicCreditsInfo.self, forKey: .subscription)
        }
        self.purchasedCredits = try container.decode(Double.self, forKey: .purchasedCredits)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(balance, forKey: .balance)
        try container.encodeIfPresent(periodicCredits, forKey: .periodicCredits)
        try container.encode(purchasedCredits, forKey: .purchasedCredits)
    }
}

public struct PeriodicCreditsInfo: ContentModel {
    public var quota: Double                // Total credits granted for the current period
    public var used: Double                 // Credits used during the current period
    public var remaining: Double            // Credits remaining in the current period
    public var resetDate: Date              // When the current period resets/expires

    public init(
        quota: Double,
        used: Double,
        remaining: Double,
        resetDate: Date
    ) {
        self.quota = quota
        self.used = used
        self.remaining = remaining
        self.resetDate = resetDate
    }

    @available(*, deprecated, message: "Use quota instead. This value describes periodic credits, not a subscription quota.")
    public var monthlyQuota: Double {
        get { quota }
        set { quota = newValue }
    }

    @available(*, deprecated, message: "Use used instead.")
    public var usedQuota: Double {
        get { used }
        set { used = newValue }
    }

    @available(*, deprecated, message: "Use remaining instead.")
    public var remainingQuota: Double {
        get { remaining }
        set { remaining = newValue }
    }

    @available(*, deprecated, message: "Use resetDate instead.")
    public var renewalDate: Date {
        get { resetDate }
        set { resetDate = newValue }
    }

    @available(*, deprecated, message: "Use init(quota:used:remaining:resetDate:) instead.")
    public init(
        monthlyQuota: Double,
        usedQuota: Double,
        remainingQuota: Double,
        renewalDate: Date
    ) {
        self.init(
            quota: monthlyQuota,
            used: usedQuota,
            remaining: remainingQuota,
            resetDate: renewalDate
        )
    }

    enum CodingKeys: String, CodingKey {
        case quota
        case used
        case remaining
        case resetDate
        case monthlyQuota
        case usedQuota
        case remainingQuota
        case renewalDate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.quota = try container.decodeIfPresent(Double.self, forKey: .quota)
            ?? container.decode(Double.self, forKey: .monthlyQuota)
        self.used = try container.decodeIfPresent(Double.self, forKey: .used)
            ?? container.decode(Double.self, forKey: .usedQuota)
        self.remaining = try container.decodeIfPresent(Double.self, forKey: .remaining)
            ?? container.decode(Double.self, forKey: .remainingQuota)
        self.resetDate = try container.decodeIfPresent(Date.self, forKey: .resetDate)
            ?? container.decode(Date.self, forKey: .renewalDate)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quota, forKey: .quota)
        try container.encode(used, forKey: .used)
        try container.encode(remaining, forKey: .remaining)
        try container.encode(resetDate, forKey: .resetDate)
    }
}

@available(*, deprecated, message: "Use PeriodicCreditsInfo. This type describes periodic credits, not subscription state.")
public typealias SubscriptionInfo = PeriodicCreditsInfo

public enum SubscriptionStatus: String, ContentModel {
    case active
    case expired
    case revoked
    case refunded
    case billingRetry
    case gracePeriod
}

public struct SubscriptionStateInfo: ContentModel {
    public let provider: String
    public let environment: SubscriptionEnvironment
    public let productId: String
    public let subscriptionGroupID: String?
    public let status: SubscriptionStatus
    public let currentPeriodStart: Date?
    public let currentPeriodEnd: Date?
    public let clientVerifiedAt: Date?
    public let asnConfirmedAt: Date?
    public let updatedAt: Date?

    public init(
        provider: String,
        environment: SubscriptionEnvironment,
        productId: String,
        subscriptionGroupID: String?,
        status: SubscriptionStatus,
        currentPeriodStart: Date?,
        currentPeriodEnd: Date?,
        clientVerifiedAt: Date?,
        asnConfirmedAt: Date?,
        updatedAt: Date?
    ) {
        self.provider = provider
        self.environment = environment
        self.productId = productId
        self.subscriptionGroupID = subscriptionGroupID
        self.status = status
        self.currentPeriodStart = currentPeriodStart
        self.currentPeriodEnd = currentPeriodEnd
        self.clientVerifiedAt = clientVerifiedAt
        self.asnConfirmedAt = asnConfirmedAt
        self.updatedAt = updatedAt
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
}

// `metadata` typed view (decodedUserMetadata / chatContext / usage / deductionSources / 整段 decodedMetadata)
// 由 MetadataCarrying protocol 默认实现统一提供, 这里只 conform 即可。
extension CreditsTransaction: MetadataCarrying {}

// MARK: - Pay Order

/// 支付提供商。
///
/// 与 `UserIdentityProvider` 的认证方式一一对应：
/// - `wechatPay` ↔ `weixinMiniProgram`（openID 即支付用户标识）
/// - 未来：`applePay` ↔ `appStore`，`stripe` ↔ Web 认证方式
///
/// 不同 provider 的用户通常只使用对应的支付方式，无需跨 provider 映射。
public enum PayOrderProvider: String, ContentModel {
    case wechatPay
    /// 微信小程序虚拟支付 2.0 (XPay)。
    /// 与 wechatPay 的差异：
    /// - 服务端不预下单,客户端 wx.requestVirtualPayment 触发微信侧建单
    /// - 走 api.weixin.qq.com/xpay/* 接口而非 api.mch.weixin.qq.com
    /// - iOS 端会被微信代收 30% 苹果税
    case wechatVirtualPay
}

public enum PayOrderStatus: String, ContentModel {
    case pending
    case paidUnverified
    case paid
    case refunded
    case closed
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

    /// 邀请奖励（邀请人或被邀请人通过邀请关系获得的积分）
    case referral

    /// 成就奖励（用户达成成就条件后领取的积分）
    case achievement
}

// MARK: - Referral (User-facing)

/// 用户的邀请码信息
public struct MyInviteCodeResponse: ContentModel {
    public let inviteCode: String
    public let createdAt: Date?

    public init(inviteCode: String, createdAt: Date?) {
        self.inviteCode = inviteCode
        self.createdAt = createdAt
    }
}

/// 用户邀请的人的简要信息
public struct MyReferralItem: ContentModel {
    public let inviteeRegisteredAt: Date?
    public let totalRewardsEarned: Double
    /// 被邀请人的画像 (nickname / avatarURL), 没注册过或没填资料时为 nil
    public let inviteeProfile: UserIdentityProfile?

    public init(
        inviteeRegisteredAt: Date?,
        totalRewardsEarned: Double,
        inviteeProfile: UserIdentityProfile? = nil
    ) {
        self.inviteeRegisteredAt = inviteeRegisteredAt
        self.totalRewardsEarned = totalRewardsEarned
        self.inviteeProfile = inviteeProfile
    }
}

/// 我是通过谁的邀请码注册的
public struct MyInviterInfo: ContentModel {
    /// 邀请人的邀请码 (展示用,例如 "来自 ABC123 的邀请")
    public let inviteCode: String
    /// 我自己的注册时间 (= 邀请码被使用的时间)
    public let registeredAt: Date?
    /// 邀请人的画像, 没填资料时为 nil
    public let inviterProfile: UserIdentityProfile?

    public init(
        inviteCode: String,
        registeredAt: Date?,
        inviterProfile: UserIdentityProfile? = nil
    ) {
        self.inviteCode = inviteCode
        self.registeredAt = registeredAt
        self.inviterProfile = inviterProfile
    }
}

/// 用户的邀请总览
public struct MyReferralSummaryResponse: ContentModel {
    public let inviteCode: String
    public let totalInvited: Int
    public let totalRewardsEarned: Double
    public let referrals: [MyReferralItem]
    /// 我被谁邀请的 (如果我是通过邀请码注册的)
    public let inviter: MyInviterInfo?

    public init(
        inviteCode: String,
        totalInvited: Int,
        totalRewardsEarned: Double,
        referrals: [MyReferralItem],
        inviter: MyInviterInfo? = nil
    ) {
        self.inviteCode = inviteCode
        self.totalInvited = totalInvited
        self.totalRewardsEarned = totalRewardsEarned
        self.referrals = referrals
        self.inviter = inviter
    }
}
