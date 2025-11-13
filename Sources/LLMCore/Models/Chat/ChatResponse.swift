//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 11/12/25.
//

import Foundation
import OpenAI

// ChatStreamResult
public enum StreamChatResponse: ContentModel {
    case message(ChatMessage)
    case settlement(CreditsResult)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let settlement = try? container.decode(CreditsResult.self) {
            self = .settlement(settlement)
        } else {
            self = .message(try container.decode(ChatMessage.self))
        }
    }
}

