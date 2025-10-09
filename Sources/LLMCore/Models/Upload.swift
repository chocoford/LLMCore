//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 10/8/25.
//

import Foundation
import CryptoKit

public struct SignUploadRequest: ContentModel {
    public var method: String
    public var url: URL
    public var headers: [String: String] = [:]
    public var bodyHash: String
    
    public init(method: String, url: URL, headers: [String : String], bodyHash: String) {
        self.method = method
        self.url = url
        self.headers = headers
        self.bodyHash = bodyHash
    }
    
}

public struct R2SignSignature: ContentModel {
    public let authorization: String
    public let amzDate: String
    public let signedHeaders: String
    
    public init(
        authorization: String,
        amzDate: String,
        signedHeaders: String
    ) {
        self.authorization = authorization
        self.amzDate = amzDate
        self.signedHeaders = signedHeaders
    }
}
