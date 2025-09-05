//
//  ImageModels.swift
//  LLMServer
//
//  Created by Chocoford on 9/3/25.
//

import Foundation

public struct ImageRequest: ContentModel {
    public var projectID: String
    public var model: SupportedModel
    public var prompt: String
    public var size: String? // e.g. "512x512"
    
    public init(projectID: String, model: SupportedModel, prompt: String, size: String? = nil) {
        self.projectID = projectID
        self.model = model
        self.prompt = prompt
        self.size = size
    }
}

public struct ImageData: ContentModel {
    public var url: String?
    public var base64EncodedDataString: String?
    
    public init(url: String? = nil, base64EncodedDataString: String? = nil) {
        self.url = url
        self.base64EncodedDataString = base64EncodedDataString
    }
}

public struct ImageResponse: ContentModel {
    public var model: String
    public var data: [ImageData]
    
    public init(model: String, data: [ImageData]) {
        self.model = model
        self.data = data
    }
}
