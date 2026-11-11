import Foundation
import Testing
@testable import LLMCore

@Suite("Actual model usage is independent of platform credits")
struct LLMInferenceUsageTests {
    @Test("Legacy messages decode unchanged and new records survive history round trips")
    func historyCompatibility() throws {
        let legacy = Data(#"{"id":"old","role":"assistant","content":"Hello","usage":{"consumed":2,"remains":8}}"#.utf8)
        var message = try JSONDecoder().decode(ChatMessageContent.self, from: legacy)
        #expect(message.inferenceUsage == nil)
        #expect(message.usage?.consumed == 2)
        message.recordInferenceUsage(.init(id: "request", generationID: "generation", modelID: "arbitrary/model",
            billingSource: .byok, tokens: .init(promptTokens: 7, completionTokens: 3, totalTokens: 10), isComplete: true))
        let data = try JSONEncoder().encode(ChatMessage.content(message))
        let restored = try JSONDecoder().decode(ChatMessage.self, from: data)
        #expect(restored.inferenceUsage == message.inferenceUsage)
        #expect(restored.usage?.consumed == 2)
        #expect(restored.usageSummary.tokens?.totalTokens == 10)
    }

    @Test("Cumulative snapshots replace; distinct tool rounds and retry requests add")
    func aggregation() {
        let first = LLMInferenceUsage(id: "one", generationID: "generation", billingSource: .byok,
            tokens: .init(promptTokens: 1, completionTokens: 1, totalTokens: 2))
        var final = first
        final.tokens = .init(promptTokens: 7, completionTokens: 3, totalTokens: 10)
        final.isComplete = true
        let second = LLMInferenceUsage(id: "two", generationID: "generation", billingSource: .byok,
            tokens: .init(promptTokens: 10, completionTokens: 5, totalTokens: 15), isComplete: true)
        let title = LLMInferenceUsage(id: "title", billingSource: .byok, purpose: "title",
            tokens: .init(promptTokens: 2, completionTokens: 1, totalTokens: 3), isComplete: true)
        let summary = LLMUsageSummary([first, final, second, title])
        #expect(summary.requestCount == 3)
        #expect(summary.tokens?.totalTokens == 28)
        #expect(summary.filtered(generationID: "generation", purpose: "chat").tokens?.totalTokens == 25)
        #expect(summary.filtered(purpose: "title").tokens?.totalTokens == 3)
        #expect(summary.filtered(billingSource: .platform).tokens == nil)
        #expect(summary.isComplete)
        var platform = second
        platform.id = "platform"
        platform.billingSource = .platform
        let mixed = LLMUsageSummary([final, second, platform])
        #expect(mixed.filtered(billingSource: .byok).tokens?.totalTokens == 25)
        #expect(mixed.filtered(billingSource: .platform).tokens?.totalTokens == 15)
    }

    @Test("Missing usage is not zero and failed responses retain reported totals")
    func incompleteUsage() {
        let missing = LLMInferenceUsage(id: "missing", isComplete: true)
        #expect(LLMUsageSummary([missing]).tokens == nil)
        let partial = LLMInferenceUsage(id: "partial",
            tokens: .init(promptTokens: 7, completionTokens: 3, totalTokens: 10))
        let summary = LLMUsageSummary([missing, partial])
        #expect(summary.tokens?.totalTokens == 10)
        #expect(summary.unreportedRequestCount == 1)
        #expect(summary.incompleteRequestCount == 1)
        #expect(!summary.isComplete)
    }
}
