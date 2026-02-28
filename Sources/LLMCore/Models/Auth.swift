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

    public init(
        bundleID: String,
        code: String
    ) {
        self.bundleID = bundleID
        self.code = code
    }
}

public struct AuthResponse: ContentModel {
    public var token: String
    
    public init(token: String) {
        self.token = token
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
