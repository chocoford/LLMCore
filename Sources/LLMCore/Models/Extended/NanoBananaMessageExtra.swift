//
//  NanoBananaMessageExtra.swift
//  LLMServer
//
//  Created by Chocoford on 9/4/25.
//

import Foundation
import OpenAI

public protocol ChatCompletionUsage {
    /// Number of tokens in the generated completion.
    var completionTokens: Int { get }
    /// Number of tokens in the prompt.
    var promptTokens: Int { get }
    
    var totalTokens: Int { get }
}

public struct NanoBananaMessageExtra: Decodable, Sendable {
    public var choices: [Choice]
    
    public struct Choice: Decodable, Sendable {
        public var message: Message
        
        public struct Message: Decodable, Sendable {
            public var images: [Image]?
            
            public struct Image: ContentModel, Sendable {
                public var type: ImageType
                public var imageURL: ImageURL
                public var index: Int
                
                public enum ImageType: String, ContentModel, Sendable {
                    case imageURL = "image_url"
                }
                
                public enum CodingKeys: String, CodingKey {
                    case type
                    case imageURL = "image_url"
                    case index
                }
                
                public struct ImageURL: ContentModel, Sendable {
                    public var url: String
                }
            }
        }
    }
}

public struct NanoBananaStreamExtra: Decodable, Sendable {
    public var choices: [Choice]
    public var usage: Usage? // missing audio_tokens
    
    public struct Choice: Decodable, Sendable {
        public var delta: Message
        
        public struct Message: Decodable, Sendable {
            public var images: [Image]?
            
            public struct Image: ContentModel, Sendable {
                public var type: ImageType
                public var imageURL: ImageURL
                public var index: Int
                
                public enum ImageType: String, ContentModel, Sendable {
                    case imageURL = "image_url"
                }
                
                public enum CodingKeys: String, CodingKey {
                    case type
                    case imageURL = "image_url"
                    case index
                }
                
                public struct ImageURL: ContentModel, Sendable {
                    public var url: String
                }
            }
        }
    }
    
    public struct Usage: ChatCompletionUsage, Decodable, Sendable {
        /// Number of tokens in the generated completion.
        public let completionTokens: Int
        /// Number of tokens in the prompt.
        public let promptTokens: Int
        /// Total number of tokens used in the request (prompt + completion).
        public let totalTokens: Int
        /// Breakdown of tokens used in the prompt.
        public let promptTokensDetails: PromptTokensDetails?
        
        public struct PromptTokensDetails: Codable, Equatable, Sendable {
            /// Cached tokens present in the prompt.
            public let cachedTokens: Int
            
            enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case completionTokens = "completion_tokens"
            case promptTokens = "prompt_tokens"
            case totalTokens = "total_tokens"
            case promptTokensDetails = "prompt_tokens_details"
        }
    }
}



extension ChatResult.CompletionUsage: ChatCompletionUsage { }
