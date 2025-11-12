//
//  File.swift
//  LLMCore
//
//  Created by Chocoford on 11/12/25.
//

import Foundation
import OpenAI

// MARK: Copied from OpenAI SDK


/// Extension of OpenAI's ChatStreamResult
public struct ChatStreamResponse: ContentModel {
    /// A unique identifier for the chat completion. Each chunk has the same ID.
    public let id: String

    /// The object type, which is always `chat.completion.chunk`.
    public let object: String

    /// The Unix timestamp (in seconds) of when the chat completion was created. Each chunk has the same timestamp.
    public let created: TimeInterval

    /// The model to generate the completion.
    public let model: String
    
    /// A list of chat completion choices. Can contain more than one element if `n` is greater than 1.
    /// Can also be empty for the last chunk if you set `stream_options: {"include_usage": true}`.
    public let choices: [StreamChatChoiceDelta]
    
    /// This fingerprint represents the backend configuration that the model runs with.
    /// Can be used in conjunction with the `seed` request parameter to understand when backend changes
    /// have been made that might impact determinism.
    ///
    /// Note: Even though [API Reference - The chat completion chunk object - system_fingerprint](https://platform.openai.com/docs/api-reference/chat-streaming/streaming#chat-streaming/streaming-system_fingerprint) declares the type as `string` (aka non-optional) - the response chunk may not contain the value, so we have had to make it optional `String?` in the Swift type
    /// See https://github.com/MacPaw/OpenAI/issues/331 for more details on such a case.
    public let systemFingerprint: String?
    
    /// Usage statistics for the completion request.
    public let usage: ChatResult.CompletionUsage?
    
    /// Specifies the latency tier to use for processing the request. This parameter is relevant
    /// for customers subscribed to the scale tier service:
    ///
    /// - If set to 'auto', and the Project is Scale tier enabled, the system will utilize scale tier credits until they are exhausted.
    /// - If set to 'auto', and the Project is not Scale tier enabled, the request will be processed using the default service tier with a lower uptime SLA and no latency guarantee.
    /// - If set to 'default', the request will be processed using the default service tier with a lower uptime SLA and no latency guarantee.
    /// - If set to 'flex', the request will be processed with the Flex Processing service tier.
    ///   [Learn more](https://platform.openai.com/docs/guides/flex-processing).
    /// - When not set, the default behavior is 'auto'.
    ///
    /// When this parameter is set, the response body will include the `service_tier` utilized.
    public let serviceTier: ServiceTier?
    
    /// A list of citations for the completion.
    ///
    /// - Note: the field is not a part of OpenAI API but is used by other providers
    public let citations: [String]?

    public init(base: ChatStreamResult, extentedChoices: [StreamChatChoiceDelta]) {
        self.id = base.id
        self.object = base.object
        self.created = base.created
        self.model = base.model
        self.choices = extentedChoices
        self.systemFingerprint = base.systemFingerprint
        self.usage = base.usage
        self.serviceTier = base.serviceTier
        self.citations = base.citations
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case model
        case citations
        case choices
        case systemFingerprint = "system_fingerprint"
        case usage
        case serviceTier = "service_tier"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let parsingOptions = decoder.userInfo[CodingUserInfoKey(rawValue: "parsingOptions")!] as? ParsingOptions ?? []
        
        self.id = try container.decodeString(forKey: .id, parsingOptions: parsingOptions)
        self.object = try container.decodeString(forKey: .object, parsingOptions: parsingOptions)
        self.created = try container.decode(TimeInterval.self, forKey: .created)
        self.model = try container.decodeString(forKey: .model, parsingOptions: parsingOptions)
        self.citations = try container.decodeIfPresent([String].self, forKey: .citations)
        self.choices = try container.decode([StreamChatChoiceDelta].self, forKey: .choices)
        self.systemFingerprint = try container.decodeIfPresent(String.self, forKey: .systemFingerprint)
        
        // Even though API Reference declares that usage field should be either informative or null: https://platform.openai.com/docs/api-reference/chat/create#chat-create-stream_options
        // In some cases it can be present, but empty: https://github.com/MacPaw/OpenAI/issues/338
        //
        // To make things simpler, we're not going to check the correctnes of payload before trying to decode
        // We're just going to ignore all the errors here by using optional try and fallback to nil `usage`
        self.usage = try? container.decodeIfPresent(ChatResult.CompletionUsage.self, forKey: .usage)
        self.serviceTier = try container.decodeIfPresent(ServiceTier.self, forKey: .serviceTier)
    }
}

extension KeyedDecodingContainer {
    func decodeString(forKey key: KeyedDecodingContainer<K>.Key, parsingOptions: ParsingOptions) throws -> String {
        try self.decode(String.self, forKey: key, parsingOptions: parsingOptions, defaultValue: "")
    }
    
    func decodeTimeInterval(forKey key: KeyedDecodingContainer<K>.Key, parsingOptions: ParsingOptions) throws -> TimeInterval {
        try self.decode(TimeInterval.self, forKey: key, parsingOptions: parsingOptions, defaultValue: 0)
    }
    
    func decode<T: Decodable>(_ type: T.Type, forKey key: KeyedDecodingContainer<K>.Key, parsingOptions: ParsingOptions, defaultValue: T) throws -> T {
        do {
            return try decode(T.self, forKey: key)
        } catch {
            switch error {
            case DecodingError.keyNotFound:
                if parsingOptions.contains(.fillRequiredFieldIfKeyNotFound) {
                    return defaultValue
                } else {
                    throw error
                }
            case DecodingError.valueNotFound:
                if parsingOptions.contains(.fillRequiredFieldIfValueNotFound) {
                    return defaultValue
                } else {
                    throw error
                }
            default:
                throw error
            }
        }
    }
}
