//
//  NanoBananaMessageExtra.swift
//  LLMServer
//
//  Created by Chocoford on 9/4/25.
//

import Foundation

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
