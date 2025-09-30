//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 9/8/25.
//

import Foundation

public struct IAPAuthRequest: ContentModel {
    public var originalTransactionID: String
    public var bundleID: String
    public var ascAppID: Int64?
    
    public init(
        originalTransactionID: String,
        bundleID: String,
        ascAppID: Int64?
    ) {
        self.originalTransactionID = originalTransactionID
        self.bundleID = bundleID
        self.ascAppID = ascAppID
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
