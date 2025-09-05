//
//  File.swift
//  LLMServer
//
//  Created by Chocoford on 9/3/25.
//

import Foundation

public struct APIResponse<T: LLMCore.ContentModel>: ContentModel {
    public var data: T?
    public var usage: Usage?
    public var error: APIError?

    public init(data: T, usage: Usage?) {
        self.data = data
        self.usage = usage
        self.error = nil
    }

    public init(error: APIError) {
        self.data = nil
        self.usage = nil
        self.error = error
    }
}

public struct APIError: ContentModel {
    public var code: Int
    public var message: String
    
    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}
