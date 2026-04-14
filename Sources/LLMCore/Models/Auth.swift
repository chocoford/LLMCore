//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 9/8/25.
//

import Foundation

protocol AnonymousableAuthRequest: ContentModel {
    var deviceToken: String { get }
}

public struct AnonAuthRequest: ContentModel {
    public var platform: AppPlatform
    public var bundleID: String
    public var anonID: String
    public var deviceToken: String

    public init(
        platform: AppPlatform,
        bundleID: String,
        anonID: String,
        deviceToken: String
    ) {
        self.platform = platform
        self.bundleID = bundleID
        self.anonID = anonID
        self.deviceToken = deviceToken
    }
}


public struct IAPAuthRequest: ContentModel {
    public var jws: String
    public var bundleID: String
    public var ascAppID: Int64?
    
    public init(
        jws: String,
        bundleID: String,
        ascAppID: Int64?
    ) {
        self.jws = jws
        self.bundleID = bundleID
        self.ascAppID = ascAppID
    }
}

public struct WeixinMiniProgramAuthRequest: ContentModel {
    public var bundleID: String
    public var code: String
    public var inviteCode: String?
    /// 可选:客户端在登录时一并传入用户画像(微信 wx.getUserProfile 获取)。
    /// 也可以登录后通过单独的接口更新。
    public var profile: UserIdentityProfile?

    public init(
        bundleID: String,
        code: String,
        inviteCode: String? = nil,
        profile: UserIdentityProfile? = nil
    ) {
        self.bundleID = bundleID
        self.code = code
        self.inviteCode = inviteCode
        self.profile = profile
    }
}

public struct AuthResponse: ContentModel {
    public var token: String

    public init(token: String) {
        self.token = token
    }
}

// MARK: - User Identity Profile

/// 用户画像信息,存储在 UserIdentity 上,作为 JSON 列。
/// 新增可选字段时只需改这个 struct,不需要 DB migration。
public struct UserIdentityProfile: ContentModel {
    public var nickname: String?
    public var avatarURL: String?

    public init(nickname: String? = nil, avatarURL: String? = nil) {
        self.nickname = nickname
        self.avatarURL = avatarURL
    }
}

// MARK: - Credit

public struct CreditAddRequest: ContentModel {
    public var transactionSignedData: String
    public var bundleID: String
    public var ascAppID: Int64?
    
    public init(
        transactionSignedData: String,
        bundleID: String,
        ascAppID: Int64?
    ) {
        self.transactionSignedData = transactionSignedData
        self.bundleID = bundleID
        self.ascAppID = ascAppID
    }
}

public struct CreditAddResponse: ContentModel {
    public var balance: Double

    public init(balance: Double) {
        self.balance = balance
    }
}

// MARK: - WeChat Pay

public struct UserPayOrderResponse: ContentModel {
    public let id: UUID
    public let outTradeNo: String
    public let productId: String
    public let quantity: Int
    public let totalAmount: Int
    public let currency: String
    public let credits: Double
    public let provider: PayOrderProvider
    public let status: PayOrderStatus
    public let createdAt: Date?
    public let paidAt: Date?

    public init(
        id: UUID,
        outTradeNo: String,
        productId: String,
        quantity: Int,
        totalAmount: Int,
        currency: String,
        credits: Double,
        provider: PayOrderProvider,
        status: PayOrderStatus,
        createdAt: Date?,
        paidAt: Date?
    ) {
        self.id = id
        self.outTradeNo = outTradeNo
        self.productId = productId
        self.quantity = quantity
        self.totalAmount = totalAmount
        self.currency = currency
        self.credits = credits
        self.provider = provider
        self.status = status
        self.createdAt = createdAt
        self.paidAt = paidAt
    }
}

public struct WeixinPayReportPaymentRequest: ContentModel {
    public var outTradeNo: String

    public init(outTradeNo: String) {
        self.outTradeNo = outTradeNo
    }
}

public struct WeixinPayCreateOrderRequest: ContentModel {
    public var productID: String
    public var quantity: Int

    public init(productID: String, quantity: Int = 1) {
        self.productID = productID
        self.quantity = quantity
    }
}

public struct WeixinPayQueryOrderResponse: ContentModel {
    public var outTradeNo: String
    public var status: PayOrderStatus
    public var credits: Double?

    public init(outTradeNo: String, status: PayOrderStatus, credits: Double? = nil) {
        self.outTradeNo = outTradeNo
        self.status = status
        self.credits = credits
    }
}

public struct WeixinPayCreateOrderResponse: ContentModel {
    public var outTradeNo: String
    public var timeStamp: String
    public var nonceStr: String
    /// 格式: "prepay_id=xxx"
    public var package: String
    /// 固定值 "RSA"
    public var signType: String
    public var paySign: String

    public init(
        outTradeNo: String,
        timeStamp: String,
        nonceStr: String,
        package: String,
        signType: String,
        paySign: String
    ) {
        self.outTradeNo = outTradeNo
        self.timeStamp = timeStamp
        self.nonceStr = nonceStr
        self.package = package
        self.signType = signType
        self.paySign = paySign
    }
}

// MARK: - 微信小程序虚拟支付 2.0 (XPay)

public struct WeixinXPayCreateOrderRequest: ContentModel {
    public var productID: String
    public var quantity: Int

    public init(productID: String, quantity: Int = 1) {
        self.productID = productID
        self.quantity = quantity
    }
}

/// XPay 客户端 wx.requestVirtualPayment 调用所需的参数包。
///
/// 客户端拿到后直接组装:
/// ```js
/// wx.requestVirtualPayment({
///   mode: response.mode,
///   signData: response.signData,
///   paySig: response.paySig,
///   signature: response.signature,
/// })
/// ```
public struct WeixinXPayCreateOrderResponse: ContentModel {
    /// 商户订单号 (= signData.outTradeNo,客户端可单独使用方便后续查询)
    public var outTradeNo: String
    /// 客户端 mode 字段,如 "short_series_goods"
    public var mode: String
    /// 序列化好的 JSON 字符串,客户端必须原样传给 wx.requestVirtualPayment
    /// (任何字段顺序变化都会让 paySig 失效)
    public var signData: String
    /// hex(HMAC_SHA256(appKey, "/wxa/requestVirtualPayment&" + signData))
    public var paySig: String
    /// hex(HMAC_SHA256(sessionKey, signData))
    public var signature: String

    public init(
        outTradeNo: String,
        mode: String,
        signData: String,
        paySig: String,
        signature: String
    ) {
        self.outTradeNo = outTradeNo
        self.mode = mode
        self.signData = signData
        self.paySig = paySig
        self.signature = signature
    }
}
