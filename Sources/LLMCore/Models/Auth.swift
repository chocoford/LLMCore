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
    public enum Platform: String, ContentModel {
        case apple
        case web
    }
    
    public var platform: Platform
    public var bundleID: String
    public var anonID: String
    public var deviceToken: String
    
    public init(
        platform: Platform,
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
    public var token: String

    public init(
        bundleID: String,
        token: String
    ) {
        self.bundleID = bundleID
        self.token = token
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
