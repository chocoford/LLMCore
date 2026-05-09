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

