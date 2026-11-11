import Foundation

/// One actual model request, independent of platform credit settlement.
/// Snapshots of the same request replace each other; they must never be added together.
public struct LLMInferenceUsage: ContentModel, Identifiable {
    public var id: String
    public var responseID: String?
    public var generationID: String?
    public var modelID: String?
    public var billingSource: LLMAccessBillingSource?
    /// Extensible classification, e.g. "chat", "title" or "summary".
    public var purpose: String
    /// nil means the provider did not report usage, NOT zero tokens.
    public var tokens: Usage?
    /// Whether the response completed successfully, including transport validation.
    /// Reported usage can survive a failed/incomplete response.
    public var isComplete: Bool

    public init(id: String = UUID().uuidString, responseID: String? = nil,
                generationID: String? = nil, modelID: String? = nil,
                billingSource: LLMAccessBillingSource? = nil, purpose: String = "chat",
                tokens: Usage? = nil, isComplete: Bool = false) {
        self.id = id; self.responseID = responseID; self.generationID = generationID
        self.modelID = modelID; self.billingSource = billingSource; self.purpose = purpose
        self.tokens = tokens; self.isComplete = isComplete
    }
}

/// Derived totals, never a replacement for the individual persisted request records.
/// Includes every model/tool round and deduplicates cumulative streaming snapshots by request ID.
public struct LLMUsageSummary: Equatable, Sendable {
    public let requests: [LLMInferenceUsage]

    public init(_ records: [LLMInferenceUsage]) {
        var indices: [String: Int] = [:]
        var requests: [LLMInferenceUsage] = []
        for record in records {
            if let index = indices[record.id] {
                requests[index] = record
            } else {
                indices[record.id] = requests.count
                requests.append(record)
            }
        }
        self.requests = requests
    }

    public var requestCount: Int { requests.count }
    public var unreportedRequestCount: Int { requests.filter { $0.tokens == nil }.count }
    public var incompleteRequestCount: Int { requests.filter { !$0.isComplete }.count }
    public var isComplete: Bool { !requests.isEmpty && unreportedRequestCount == 0 && incompleteRequestCount == 0 }

    /// A partial sum when some requests are unreported; consult isComplete alongside it.
    public var tokens: Usage? {
        let values = requests.compactMap(\.tokens)
        guard !values.isEmpty else { return nil }
        func sum(_ keyPath: KeyPath<Usage, Int>) -> Int {
            values.reduce(0) { total, value in
                let (sum, overflow) = total.addingReportingOverflow(value[keyPath: keyPath])
                return overflow ? Int.max : sum
            }
        }
        return .init(promptTokens: sum(\.promptTokens), completionTokens: sum(\.completionTokens), totalTokens: sum(\.totalTokens))
    }

    public func filtered(generationID: String? = nil, purpose: String? = nil,
                         billingSource: LLMAccessBillingSource? = nil) -> Self {
        .init(requests.filter {
            (generationID == nil || $0.generationID == generationID)
                && (purpose == nil || $0.purpose == purpose)
                && (billingSource == nil || $0.billingSource == billingSource)
        })
    }
}

extension ChatMessageContent {
    /// Upsert accounting snapshots without changing content, files or tool arguments.
    public mutating func recordInferenceUsage(_ record: LLMInferenceUsage) {
        var records = inferenceUsage ?? []
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        else { records.append(record) }
        inferenceUsage = records
    }

    public var usageSummary: LLMUsageSummary { .init(inferenceUsage ?? []) }
}
