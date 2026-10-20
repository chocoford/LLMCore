import Foundation

/// Portable connection settings only. API keys must never be added to this Codable type.
public struct LLMBYOKConfiguration: Codable, Equatable, Sendable {
    public enum APIFormat: String, Codable, Sendable { case chatCompletions = "chat_completions" }
    public enum TokenLimitParameter: String, Codable, Sendable {
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
    }

    public struct ModelMapping: Codable, Equatable, Sendable {
        public var aliases: [String: String]
        public var stripPrefix: String?
        public var replacePeriodsWithHyphens: Bool

        public init(
            aliases: [String: String] = [:], stripPrefix: String? = nil,
            replacePeriodsWithHyphens: Bool = false
        ) {
            self.aliases = aliases
            self.stripPrefix = stripPrefix
            self.replacePeriodsWithHyphens = replacePeriodsWithHyphens
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            aliases = try values.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
            stripPrefix = try values.decodeIfPresent(String.self, forKey: .stripPrefix)
            replacePeriodsWithHyphens = try values.decodeIfPresent(Bool.self, forKey: .replacePeriodsWithHyphens) ?? false
        }

        public func resolve(_ requestedModel: String) throws -> String {
            var model = aliases[requestedModel] ?? requestedModel
            if let stripPrefix, model.hasPrefix(stripPrefix) { model.removeFirst(stripPrefix.count) }
            if replacePeriodsWithHyphens { model = model.replacingOccurrences(of: ".", with: "-") }
            // Model availability, account permissions and modalities belong to the upstream.
            // This value only normalizes IDs; it must not become a platform model catalog.
            guard Self.validModel(model) else {
                throw LLMBYOKConfigurationValidationError.invalidModel
            }
            return model
        }

        private static func validModel(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 512 && value.utf8.allSatisfy { (33...126).contains($0) }
        }
    }

    /// These are protocol capabilities/options, not runtime switches on a vendor enum.
    public struct CompatibilityOptions: Codable, Equatable, Sendable {
        public var includeUsage: Bool
        public var sendStoreFalse: Bool
        public var outputTokenLimit: Int?
        public var tokenLimitParameter: TokenLimitParameter
        public var preserveGoogleThoughtSignatures: Bool
        public var openRouterExtensions: Bool
        /// Selects the existing OpenRouter-style image response adapter, not model permission.
        public var supportsImageGeneration: Bool
        public var requiresDoneMarker: Bool
        public var auxiliaryModel: String?

        public init(
            includeUsage: Bool = true, sendStoreFalse: Bool = false,
            outputTokenLimit: Int? = nil, tokenLimitParameter: TokenLimitParameter = .maxTokens,
            preserveGoogleThoughtSignatures: Bool = false, openRouterExtensions: Bool = false,
            supportsImageGeneration: Bool = false, requiresDoneMarker: Bool = true,
            auxiliaryModel: String? = nil
        ) {
            self.includeUsage = includeUsage
            self.sendStoreFalse = sendStoreFalse
            self.outputTokenLimit = outputTokenLimit
            self.tokenLimitParameter = tokenLimitParameter
            self.preserveGoogleThoughtSignatures = preserveGoogleThoughtSignatures
            self.openRouterExtensions = openRouterExtensions
            self.supportsImageGeneration = supportsImageGeneration
            self.requiresDoneMarker = requiresDoneMarker
            self.auxiliaryModel = auxiliaryModel
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            includeUsage = try values.decodeIfPresent(Bool.self, forKey: .includeUsage) ?? true
            sendStoreFalse = try values.decodeIfPresent(Bool.self, forKey: .sendStoreFalse) ?? false
            outputTokenLimit = try values.decodeIfPresent(Int.self, forKey: .outputTokenLimit)
            tokenLimitParameter = try values.decodeIfPresent(TokenLimitParameter.self, forKey: .tokenLimitParameter) ?? .maxTokens
            preserveGoogleThoughtSignatures = try values.decodeIfPresent(Bool.self, forKey: .preserveGoogleThoughtSignatures) ?? false
            openRouterExtensions = try values.decodeIfPresent(Bool.self, forKey: .openRouterExtensions) ?? false
            supportsImageGeneration = try values.decodeIfPresent(Bool.self, forKey: .supportsImageGeneration) ?? false
            requiresDoneMarker = try values.decodeIfPresent(Bool.self, forKey: .requiresDoneMarker) ?? true
            auxiliaryModel = try values.decodeIfPresent(String.self, forKey: .auxiliaryModel)
        }
    }

    public var version: Int
    /// API root, e.g. https://example.com/v1/. The protocol appends chat/completions.
    public var baseURL: URL
    public var apiFormat: APIFormat
    public var defaultModel: String?
    public var modelMapping: ModelMapping
    public var options: CompatibilityOptions

    public init(
        baseURL: URL, apiFormat: APIFormat = .chatCompletions, defaultModel: String? = nil,
        modelMapping: ModelMapping = .init(), options: CompatibilityOptions = .init()
    ) {
        self.version = 1
        self.baseURL = baseURL
        self.apiFormat = apiFormat
        self.defaultModel = defaultModel
        self.modelMapping = modelMapping
        self.options = options
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        baseURL = try values.decode(URL.self, forKey: .baseURL)
        apiFormat = try values.decodeIfPresent(APIFormat.self, forKey: .apiFormat) ?? .chatCompletions
        defaultModel = try values.decodeIfPresent(String.self, forKey: .defaultModel)
        modelMapping = try values.decodeIfPresent(ModelMapping.self, forKey: .modelMapping) ?? .init()
        options = try values.decodeIfPresent(CompatibilityOptions.self, forKey: .options) ?? .init()
    }

    public var chatCompletionsURL: URL {
        let url = baseURL.appendingPathComponent("chat/completions")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.url ?? url
    }
    public var preset: LLMBYOKPreset? { LLMBYOKPreset.allCases.first { $0.configuration == self } }

    /// Syntactic checks are shared with the App. DNS/IP checks are a backend responsibility.
    public func validate() throws {
        guard version == 1 else { throw LLMBYOKConfigurationValidationError.unsupportedVersion }
        guard let url = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port.map({ (1...65535).contains($0) }) ?? true,
              !url.percentEncodedHost.orEmpty.contains("%"),
              url.percentEncodedPath.utf8.allSatisfy({
                  (45...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [95, 126].contains($0)
              }),
              !url.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              !host.contains("%"), host.utf8.count <= 253,
              host.utf8.allSatisfy({ (45...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [58, 91, 93].contains($0) }) else {
            throw LLMBYOKConfigurationValidationError.invalidEndpoint
        }
        if let limit = options.outputTokenLimit, !(1...1_000_000).contains(limit) {
            throw LLMBYOKConfigurationValidationError.invalidConfiguration
        }
        for value in [defaultModel, options.auxiliaryModel].compactMap({ $0 }) {
            _ = try modelMapping.resolve(value)
        }
        guard try JSONEncoder().encode(self).count <= 4096 else {
            throw LLMBYOKConfigurationValidationError.invalidConfiguration
        }
    }
}

public enum LLMBYOKPreset: String, Codable, CaseIterable, Sendable {
    case openRouter = "openrouter", openAI = "openai", anthropic, gemini

    public var configuration: LLMBYOKConfiguration {
        switch self {
        case .openRouter:
            return .init(baseURL: URL(string: "https://openrouter.ai/api/v1/")!, options: .init(
                openRouterExtensions: true, supportsImageGeneration: true, auxiliaryModel: "openai/gpt-3.5-turbo"
            ))
        case .openAI:
            return .init(baseURL: URL(string: "https://api.openai.com/v1/")!, modelMapping: .init(
                aliases: ["openai/gpt-4o-latest": "chatgpt-4o-latest", "gpt-4o-latest": "chatgpt-4o-latest"],
                stripPrefix: "openai/"
            ), options: .init(sendStoreFalse: true))
        case .anthropic:
            return .init(baseURL: URL(string: "https://api.anthropic.com/v1/")!, modelMapping: .init(
                stripPrefix: "anthropic/", replacePeriodsWithHyphens: true
            ), options: .init(outputTokenLimit: 8192))
        case .gemini:
            return .init(baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/")!, modelMapping: .init(
                stripPrefix: "google/"
            ), options: .init(preserveGoogleThoughtSignatures: true))
        }
    }
}

extension LLMBYOKConfiguration {
    public static var openRouter: Self { LLMBYOKPreset.openRouter.configuration }
    public static var openAI: Self { LLMBYOKPreset.openAI.configuration }
    public static var anthropic: Self { LLMBYOKPreset.anthropic.configuration }
    public static var gemini: Self { LLMBYOKPreset.gemini.configuration }
}

public enum LLMBYOKConfigurationValidationError: LocalizedError, Sendable {
    case invalidEndpoint, invalidModel, invalidConfiguration, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "BYOK requires an HTTPS API root without URL credentials, query, fragment or encoded path."
        case .invalidModel: return "A BYOK model ID must be non-empty printable ASCII and at most 512 bytes."
        case .invalidConfiguration: return "The BYOK configuration is invalid or too large."
        case .unsupportedVersion: return "The BYOK configuration version is not supported."
        }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
