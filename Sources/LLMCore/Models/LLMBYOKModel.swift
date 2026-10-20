import Foundation

/// Provider-reported discovery metadata, not a guarantee of Chat Completions/tool support.
/// A missing model in this list must never prevent manually selecting its ID.
public struct LLMBYOKModel: ContentModel, Identifiable {
    public let id: String
    public let name: String?

    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }

    public var displayName: String { name ?? id }
    public var model: SupportedModel { .init(rawValue: id) }
}
