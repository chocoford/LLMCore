//
//  MetadataCarrying.swift
//  LLMCore
//
//  统一抽象: 任何带 `metadata: [String: AnyCodable]?` 字段的 model 都可以 conform,
//  自动获得 typed view (`decodedUserMetadata`, `chatContext`, `usage`, `deductionSources` 等)。
//
//  背景: server 端 metadata 必然是 type-erased 字典 (server 不知道 client 的 typed shape),
//  但 client 把 typed metadata 发出去之后再读回来, 自己应当能 typed 解出来。
//  这个 protocol 就是这层 client typed-view 的统一出口。
//

import Foundation
@preconcurrency import AnyCodable

public protocol MetadataCarrying {
    var metadata: [String: AnyCodable]? { get }
}

internal extension MetadataCarrying {
    /// 内部 helper, 给具体语义化 accessor 复用。不暴露 public, 避免外部按字符串 key 戳。
    func _decodeMetadataField<T: Decodable>(at key: String, as type: T.Type) -> T? {
        guard let value = metadata?[key] else { return nil }
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }
}

public extension MetadataCarrying {
    /// 整段 metadata typed 解码 (调用方传期望的 envelope shape, 通常对应当初发出去的结构)。
    func decodedMetadata<T: Decodable>(as type: T.Type) -> T? {
        guard let metadata else { return nil }
        do {
            let data = try JSONEncoder().encode(metadata)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    /// 用户当初通过 sendMessage 附带的 metadata (typed)。
    /// 跟 LLMKit 注入的 context 字段并列, 解出来是 user 自己定义的 Codable 类型。
    func decodedUserMetadata<T: Decodable>(as type: T.Type) -> T? {
        _decodeMetadataField(at: "userInfo", as: type)
    }

    /// LLMKit 注入的 chat context (conversationID / agentStep / source)。
    /// 仅对 chat 来源的 transaction / log 有意义, 其它来源返回 nil。
    func chatContext() -> ChatRequestInternalMetadata? {
        _decodeMetadataField(at: "context", as: ChatRequestInternalMetadata.self)
    }

    /// 计费扣款来源分布 (permanent / periodic / free)。
    /// 仅在 LLM 计费场景产生的记录里出现, 其它场景返回 nil。
    func deductionSources() -> DeductionSources? {
        _decodeMetadataField(at: "deductionSources", as: DeductionSources.self)
    }

    /// LLM token usage (prompt / completion / total)。
    /// 仅在 LLM 计费场景产生的记录里出现, 其它场景返回 nil。
    func usage() -> Usage? {
        _decodeMetadataField(at: "usage", as: Usage.self)
    }
}

/// 一笔 LLM 扣款在不同钱包余额上的分布 (permanent 永久 / periodic 周期 / free 免费配额)。
/// 服务端结算时写进 transaction 的 metadata, 客户端通过 `MetadataCarrying.deductionSources()` 拿到 typed 视图。
public struct DeductionSources: Codable, Equatable, Sendable {
    public var permanent: Double?
    public var periodic: Double?
    public var free: Double?

    public init(permanent: Double? = nil, periodic: Double? = nil, free: Double? = nil) {
        self.permanent = permanent
        self.periodic = periodic
        self.free = free
    }
}
