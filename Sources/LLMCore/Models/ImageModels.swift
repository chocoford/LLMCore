//
//  ImageModels.swift
//  LLMServer
//
//  Created by Chocoford on 9/3/25.
//

import Foundation

// MARK: - Image Scenes

public enum ImageScene: String, Codable, Sendable, CaseIterable {
    case birthdayDoodle = "birthday_doodle"
}

/// 生日涂鸦场景参数
public struct BirthdayDoodleParameters: ContentModel {
    /// 主标题，如"生日快乐"
    public var title: String
    /// 日期，如"2024.03.25"
    public var date: String
    /// 涂鸦文字内容（左右分布）
    public var text: String
    /// 参考人物图片 URL（必填）
    public var referenceImageURL: String

    public init(title: String, date: String, text: String, referenceImageURL: String) {
        self.title = title
        self.date = date
        self.text = text
        self.referenceImageURL = referenceImageURL
    }
}

// MARK: - Raw Image Request/Response

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
