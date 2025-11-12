//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 11/12/25.
//

import Foundation
import OpenAI

public struct ChatResponse: ContentModel {
    public var model: String
    public var choices: [ChatChoice]
    
    public init(model: String, choices: [ChatChoice]) {
        self.model = model
        self.choices = choices
    }
}

public enum StreamChatResponse: ContentModel {
    case message(MessagResult)
    case settlement(CreditsResult)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let settlement = try? container.decode(CreditsResult.self) {
            self = .settlement(settlement)
        } else {
            self = .message(try container.decode(MessagResult.self))
        }
    }
    
    public struct MessagResult: ContentModel {
        public let id: String
        public var model: String
        public var choices: [StreamChatChoiceDelta]
    }
}

