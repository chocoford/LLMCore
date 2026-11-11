import Foundation

/// Untrusted source links reported by an upstream model service. Never fetched by the SDK.
public struct LLMSourceCitation: ContentModel, Hashable, Identifiable {
    public var url: URL
    public var title: String?
    public var id: String { url.absoluteString }

    public init(url: URL, title: String? = nil) { self.url = url; self.title = title }

    static func safeURL(_ text: String) -> URL? {
        guard text.utf8.count <= 8192, let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

extension ChatMessageContent {
    /// Source snapshots can be repeated or incremental. Preserve order and deduplicate by URL.
    public mutating func mergeCitations(_ incoming: [LLMSourceCitation]) {
        guard !incoming.isEmpty else { return }
        var values = citations ?? []
        for citation in incoming {
            guard LLMSourceCitation.safeURL(citation.url.absoluteString) != nil else { continue }
            if let index = values.firstIndex(where: { $0.url == citation.url }) {
                if let title = citation.title { values[index].title = title }
            } else if values.count < 256 {
                values.append(citation)
            }
        }
        if !values.isEmpty { citations = values }
    }
}

/// Shared, bounded metadata normalization for Direct and server-mediated Chat Completions.
/// Does not interpret server-hosted tools as locally executable function calls.
public struct LLMChatCompletionsMetadata: Decodable, Sendable {
    public private(set) var citations: [LLMSourceCitation] = []
    /// Provider-reported counters only, separate from token totals and platform credits.
    public private(set) var providerToolUsage: [String: Int]?
    public init() {}

    public init(from decoder: any Decoder) throws {
        let root = try Node(from: decoder)
        let choice = root["choices"].array.first ?? .null
        let nodes = [root, choice["message"], choice["delta"]]
        var seen = Set<String>()
        func add(_ value: Node) {
            let source = value["url_citation"].isObject ? value["url_citation"] : value
            guard let text = source["url"].string ?? source["uri"].string,
                  let url = LLMSourceCitation.safeURL(text), citations.count < 256 else { return }
            let title = source["title"].string.map { String($0.prefix(1024)) }
            if seen.insert(url.absoluteString).inserted { citations.append(.init(url: url, title: title)) }
            else if let title, let index = citations.firstIndex(where: { $0.url == url }) { citations[index].title = title }
        }
        for node in nodes {
            for annotation in node["annotations"].array where annotation["type"].string == "url_citation" {
                add(annotation)
            }
            for citation in node["citations"].array {
                if let text = citation.string { add(.object(["url": .string(text)])) }
                else { add(citation) }
            }
            for result in node["search_results"].array + node["search_info"]["search_results"].array { add(result) }
        }
        // Some compatible gateways expose native grounding metadata alongside Chat choices.
        for grounding in [root["groundingMetadata"], choice["message"]["grounding_metadata"],
                          choice["message"]["extra_content"]["google"]["grounding_metadata"]] {
            for chunk in grounding["groundingChunks"].array + grounding["grounding_chunks"].array { add(chunk["web"]) }
        }
        var counters: [String: Int] = [:]
        for container in [root["usage"]["server_tool_use_details"], root["usage"]["server_tool_use"]] {
            for (key, value) in container.object where counters.count < 128 {
                guard let count = value.integer, count >= 0, key.utf8.count <= 128 else { continue }
                counters[key] = count
            }
        }
        if let count = root["usage"]["plugins"]["search"]["count"].integer, count >= 0 {
            counters["web_search_requests"] = count
        }
        if let count = root["usage"]["num_search_queries"].integer, count >= 0 {
            counters["web_search_requests"] = count
        }
        providerToolUsage = counters.isEmpty ? nil : counters
    }

    /// Only recognized citation entries may appear in an otherwise content-free terminal delta.
    static func isCitationAnnotations(_ value: Any) -> Bool {
        guard let annotations = value as? [[String: Any]] else { return false }
        return annotations.allSatisfy {
            guard $0["type"] as? String == "url_citation",
                  let source = $0["url_citation"] as? [String: Any],
                  let url = source["url"] as? String else { return false }
            return LLMSourceCitation.safeURL(url) != nil
        }
    }

    private indirect enum Node: Decodable {
        case object([String: Node]), array([Node]), string(String), integer(Int), other, null
        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() { self = .null }
            else if let object = try? value.decode([String: Node].self) { self = .object(object) }
            else if let array = try? value.decode([Node].self) { self = .array(array) }
            else if let string = try? value.decode(String.self) { self = .string(string) }
            else if (try? value.decode(Bool.self)) != nil { self = .other }
            else if let number = try? value.decode(Int.self) { self = .integer(number) }
            else { _ = try value.decode(Double.self); self = .other }
        }
        subscript(_ key: String) -> Self { object[key] ?? .null }
        var object: [String: Self] { if case .object(let value) = self { return value }; return [:] }
        var array: [Self] { if case .array(let value) = self { return value }; return [] }
        var string: String? { if case .string(let value) = self { return value }; return nil }
        var integer: Int? { if case .integer(let value) = self { return value }; return nil }
        var isObject: Bool { if case .object = self { return true }; return false }
    }
}
