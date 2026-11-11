import Foundation

/// Explicit search opt-in on the existing Chat Completions connection.
/// The upstream executes hosted tools; this never invokes an App/platform search tool.
public struct LLMBYOKWebSearch: Codable, Equatable, Sendable {
    /// Confirms that LLMServer understood the request option, not that a search ran.
    public static let acknowledgementHeader = "X-LLM-BYOK-Web-Search"

    public enum ExecutionBehavior: String, Sendable {
        case modelDecides, alwaysSearch, providerDefined
    }

    /// Wire formats, not a model allowlist. Custom gateways may select one explicitly.
    public enum Adapter: String, Codable, CaseIterable, Sendable {
        case openRouter = "openrouter_server_tool"
        case openAI = "openai_search_options"
        case dashScope = "dashscope_enable_search"
        case groq = "groq_browser_search"

        /// App UI must not promise optional/model-decided search for every provider.
        public var executionBehavior: ExecutionBehavior {
            switch self {
            case .openRouter: return .modelDecides
            case .openAI: return .alwaysSearch
            case .dashScope, .groq: return .providerDefined
            }
        }
    }

    public var adapter: Adapter
    /// false omits the opt-in; it cannot disable a provider/model's inherent search.
    public var isEnabled: Bool

    public init(adapter: Adapter, isEnabled: Bool = false) {
        self.adapter = adapter
        self.isEnabled = isEnabled
    }

    /// Preserve local function schemas, model, messages, endpoint and credentials.
    /// No forced tool_choice is added: actual execution follows the upstream contract.
    public func apply(to payload: inout [String: Any]) {
        guard isEnabled else { return }
        switch adapter {
        case .openRouter:
            appendTool(["type": "openrouter:web_search"], to: &payload)
        case .openAI:
            payload["web_search_options"] = [String: Any]()
        case .dashScope:
            payload["enable_search"] = true
        case .groq:
            appendTool(["type": "browser_search"], to: &payload)
        }
    }

    private func appendTool(_ tool: [String: Any], to payload: inout [String: Any]) {
        var tools = payload["tools"] as? [[String: Any]] ?? []
        if !tools.contains(where: { $0["type"] as? String == tool["type"] as? String }) { tools.append(tool) }
        payload["tools"] = tools
    }
}

extension LLMBYOKPreset {
    /// Verified request adapter for this preset's current Chat Completions endpoint.
    /// Availability for a specific model/account/region remains an upstream decision.
    public var webSearchAdapter: LLMBYOKWebSearch.Adapter? {
        switch self {
        case .openRouter: return .openRouter
        case .openAI: return .openAI
        case .dashScope, .dashScopeInternational: return .dashScope
        case .groq: return .groq
        default: return nil
        }
    }
}

extension LLMBYOKConfiguration {
    /// Capability information for App UI; does not enable search or mutate presets.
    public var webSearchAdapter: LLMBYOKWebSearch.Adapter? {
        webSearch?.adapter ?? preset?.webSearchAdapter
    }

    public func withWebSearch(enabled: Bool = true) throws -> Self {
        var copy = self
        guard let adapter = webSearchAdapter else {
            if !enabled { return copy }
            throw LLMBYOKWebSearchError.unsupportedProtocol
        }
        copy.webSearch = .init(adapter: adapter, isEnabled: enabled)
        return copy
    }
}

public enum LLMBYOKWebSearchError: LocalizedError, Sendable {
    case unsupportedProtocol
    public var errorDescription: String? {
        "This BYOK connection has no supported web-search adapter for its current API protocol. No fallback was attempted."
    }
}
