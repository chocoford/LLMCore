//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 10/8/25.
//

import Foundation

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

// MARK: - Tencent COS STS

public struct COSSTSRequest: ContentModel {
    /// 临时凭证有效时长，单位秒。可选,服务端会限制最大值。
    public var durationSeconds: Int?
    /// 可选的子目录,会拼接在用户根目录之后。例如传入 "avatars",
    /// 最终允许上传到 `uploads/<userID>/avatars/*`。
    public var subPath: String?

    public init(durationSeconds: Int? = nil, subPath: String? = nil) {
        self.durationSeconds = durationSeconds
        self.subPath = subPath
    }
}

// MARK: - Tencent COS POST Object Presign (小程序直传)

public struct COSPresignRequest: ContentModel {
    /// 项目标识,作为对象 key 的顶级前缀。服务端会校验是否在白名单中。
    /// 例如 "birthday-doodle"。每个项目可在 COS 侧独立配置 bucket policy 和生命周期规则。
    public var project: String
    /// 文件扩展名,小写,不带点。白名单: jpg / jpeg / png
    public var ext: String
    /// 对象是否需要持久保留。
    /// - `.ephemeral`: 参考图 / 中间产物等,COS 侧挂生命周期规则定期清理
    /// - `.persistent`: 用户资料(头像)或最终作品等,不被清理
    /// 不传则默认 `.ephemeral`,保持上线前行为不变。
    public var lifecycle: COSObjectLifecycle?
    /// 仅当 `lifecycle == .persistent` 时必填,用于把同一项目下不同语义的持久化数据分组。
    /// 例: "avatar", "artwork"。字符集 `[a-z0-9-]`, 1~32 字符。服务端不白名单只校验格式。
    public var category: String?

    public init(project: String, ext: String, lifecycle: COSObjectLifecycle? = nil, category: String? = nil) {
        self.project = project
        self.ext = ext
        self.lifecycle = lifecycle
        self.category = category
    }
}

public enum COSObjectLifecycle: String, ContentModel {
    case persistent
    case ephemeral
}

public struct COSPresignFormData: ContentModel {
    public let key: String
    public let policy: String
    public let qSignAlgorithm: String
    public let qAk: String
    public let qKeyTime: String
    public let qSignTime: String
    public let qSignature: String

    public init(
        key: String,
        policy: String,
        qSignAlgorithm: String,
        qAk: String,
        qKeyTime: String,
        qSignTime: String,
        qSignature: String
    ) {
        self.key = key
        self.policy = policy
        self.qSignAlgorithm = qSignAlgorithm
        self.qAk = qAk
        self.qKeyTime = qKeyTime
        self.qSignTime = qSignTime
        self.qSignature = qSignature
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case policy
        case qSignAlgorithm = "q-sign-algorithm"
        case qAk = "q-ak"
        case qKeyTime = "q-key-time"
        case qSignTime = "q-sign-time"
        case qSignature = "q-signature"
    }
}

public struct COSPresignResponse: ContentModel {
    /// COS bucket 域名,小程序 wx.uploadFile 的 url 字段
    public let uploadUrl: String
    /// 上传成功后图片的访问地址(走自定义域名)
    public let publicUrl: String
    /// 完整的 multipart 表单字段,小程序原样透传给 wx.uploadFile 的 formData
    public let formData: COSPresignFormData

    public init(uploadUrl: String, publicUrl: String, formData: COSPresignFormData) {
        self.uploadUrl = uploadUrl
        self.publicUrl = publicUrl
        self.formData = formData
    }
}

public struct COSSTSResponse: ContentModel {
    public let tmpSecretId: String
    public let tmpSecretKey: String
    public let sessionToken: String
    /// 凭证生效起始时间(Unix 时间戳,秒)
    public let startTime: Int
    /// 凭证过期时间(Unix 时间戳,秒)
    public let expiredTime: Int
    public let bucket: String
    public let region: String
    /// 实际授予的对象前缀,客户端上传时 Key 必须以此为前缀。
    public let allowPrefix: String

    public init(
        tmpSecretId: String,
        tmpSecretKey: String,
        sessionToken: String,
        startTime: Int,
        expiredTime: Int,
        bucket: String,
        region: String,
        allowPrefix: String
    ) {
        self.tmpSecretId = tmpSecretId
        self.tmpSecretKey = tmpSecretKey
        self.sessionToken = sessionToken
        self.startTime = startTime
        self.expiredTime = expiredTime
        self.bucket = bucket
        self.region = region
        self.allowPrefix = allowPrefix
    }
}
