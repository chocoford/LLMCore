//
//  Tool.swift
//  LLMCore
//
//  Created by Claude Code
//

import Foundation
@preconcurrency import AnyCodable

/// Protocol for tools that agents can use
public protocol Tool: Sendable {
    /// Unique name of the tool
    var name: String { get }

    /// UI 展示用的友好名。默认 = `name`。
    /// **必须在 protocol 里声明**, 否则 `any Tool` 调用走静态分派, 具体类型的 override 被忽略。
    var displayName: String { get }

    /// Description of what the tool does
    var description: String { get }

    /// JSON Schema describing the tool's input. 主入口是这个 enum, 不再要求 Swift 平铺结构。
    /// 简单工具用 `.parameters(...)`, 复杂工具用 `.bundleResource(...)` 加载 .json。
    var inputSchema: ToolInputSchema { get }

    /// 工具级 approval 配置 (always / auto / never)。默认 `.auto`。
    /// **必须在 protocol 里声明**, 否则 override 走不到动态分派。
    var approvalRequirement: ApprovalRequirement { get }

    /// 给定一次 input, 决定是否需要走 approval 流程。
    /// 默认实现读 `approvalRequirement`, `.auto` 时还会探测 input 顶层的 `approvalReason` 字段。
    /// **必须在 protocol 里声明**, 否则 override 走不到动态分派。
    func approvalPolicy(input: String) -> ApprovalPolicy

    /// Execute the tool with given input
    /// - Parameter input: JSON string containing the tool input
    /// - Parameter context: Optional invocation context for tool-specific data
    /// - Returns: 工具执行结果, 可以只是文本, 也可以混合 text + image (如截图工具)
    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult
}

public extension Tool {
    func execute(_ input: String) async throws -> ToolResult {
        try await execute(input, context: nil)
    }

    /// UI 展示用的友好名。默认 = `name` (机器名), 工具作者想要更友好的展示就 override。
    /// LLM 看到的仍然是 `name`, 不影响 tool_calls 的协议层。
    var displayName: String { name }

    /// 序列化为发给 provider 的 ToolSchema (= function schema)。
    /// 通过 `inputSchema.resolve()` 把 enum 各分支统一成 raw JSON Schema (AnyCodable)。
    var schema: ToolSchema {
        get throws {
            ToolSchema(
                name: name,
                description: description,
                parameters: try inputSchema.resolve()
            )
        }
    }

    // MARK: - Approval

    /// 默认 `.auto`: AI 在 input 顶层填了 `approvalReason` 就过审, 没填就直跑。
    /// - 本质上危险的工具 (发邮件 / 删文件 / 不可逆操作) override 成 `.always`。
    /// - 绝对安全的只读工具 override 成 `.never`, 防 AI 误填 approvalReason 触发无意义弹窗。
    var approvalRequirement: ApprovalRequirement { .auto }

    /// 给定一次 input, 决定是否需要走 approval 流程。
    /// 默认实现按 `approvalRequirement` 走; `.auto` 时探测 input 顶层 `approvalReason` 字段。
    /// 需要更复杂判断的工具可以 override 这个方法。
    func approvalPolicy(input: String) -> ApprovalPolicy {
        switch approvalRequirement {
        case .always:
            return .requiresApproval(reason: nil)
        case .never:
            return .autoApprove
        case .auto:
            if let reason = Self._extractApprovalReason(from: input) {
                return .requiresApproval(reason: reason)
            }
            return .autoApprove
        }
    }

    /// LLMKit 协议级保留字段名: AI 在 tool input 顶层填这个 string, LLMKit 自动弹审批。
    /// 工具的 JSON Schema 里需要把这个字段声明出来 AI 才会填。
    static func _extractApprovalReason(from input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let probe = try? JSONDecoder().decode(_ApprovalProbe.self, from: data)
        else {
            // input 不是合法 JSON 时返回 nil → autoApprove → 走到 execute 时工具自己会 throw,
            // 错误统一在 execute 那条路径处理, 不在这里二次解析。
            return nil
        }
        // 空字符串也视作没填, 避免 AI 给个 "" 触发空理由弹窗。
        guard let reason = probe.approvalReason, !reason.isEmpty else { return nil }
        return reason
    }
}

/// 仅用于探测 input 顶层 `approvalReason` 字段, 其它字段一律 ignore。
private struct _ApprovalProbe: Decodable {
    let approvalReason: String?
}

/// 工具级 approval 配置 (静态属性), 决定 LLMKit 默认实现如何判断 approval。
/// 复杂判断 (例如"含 delete op 才弹") 仍然可以用更通用的 `.auto` + 在 input 里教 AI 填 `approvalReason`,
/// 不必专门 override `approvalPolicy(input:)`。
public enum ApprovalRequirement: Sendable {
    /// 默认: input 顶层含非空 `approvalReason` 字段 → 弹审批; 否则放行。
    /// AI 在 system prompt 里被教"什么场景该填 approvalReason", 由模型自决。
    case auto

    /// 不论 input 怎么填, 每次都过审。
    /// 用于本质危险的工具: 发邮件 / 删文件 / 不可逆操作。
    case always

    /// 不论 input 怎么填, 永远不过审。
    /// 用于绝对安全的只读工具, 防 AI 误填 approvalReason 触发无意义弹窗。
    case never
}

/// Tool 决定本次 input 要不要走 approval。
public enum ApprovalPolicy: Sendable {
    case autoApprove
    /// 需要用户批准。reason 用于 UI 显示, nil 时由 LLMKit 兜底成 "Need approval to use <toolName>"。
    case requiresApproval(reason: String?)
}

/// 客户端 ApprovalHandler 拿到的请求载荷。
/// `Identifiable` 用 `toolCallID` 作 id, 让 SwiftUI 的 `.sheet(item:)` 直接能用。
public struct ToolApprovalRequest: Sendable, Identifiable {
    public var id: String { toolCallID }

    /// 机器名 (跟 `Tool.name` 对应), 用于日志、dedupe、注册 approveAlways 等。
    public let toolName: String
    /// UI 展示用的友好名 (跟 `Tool.displayName` 对应)。
    public let toolDisplayName: String
    public let toolDescription: String
    /// LLM 给的 raw arguments JSON 字符串, 客户端自己渲染要不要 pretty-print。
    public let arguments: String
    public let conversationID: String
    /// 跟当前正在执行的 toolCall id 对应, 客户端可以用它 dedupe / 关联 UI。
    public let toolCallID: String
    /// Tool 自己提供的 reason; nil 时被替换成 "Need approval to use <toolName>"。
    public let reason: String

    public init(
        toolName: String,
        toolDisplayName: String,
        toolDescription: String,
        arguments: String,
        conversationID: String,
        toolCallID: String,
        reason: String
    ) {
        self.toolName = toolName
        self.toolDisplayName = toolDisplayName
        self.toolDescription = toolDescription
        self.arguments = arguments
        self.conversationID = conversationID
        self.toolCallID = toolCallID
        self.reason = reason
    }
}

/// 客户端 ApprovalHandler 返回的决策。
public enum ToolApprovalDecision: Sendable {
    /// 单次同意, 下次同名工具仍会询问。
    case approve
    /// 本次会话剩余轮次内, 同名工具不再询问 (per-conversation 内存集合)。
    case approveAlways
    /// 拒绝。reason 作为 tool result observation 喂回 LLM, 模型下一轮会响应。
    case deny(reason: String?)
}

/// 闭包形态的 approval handler。nil 等价于"自动 approve"(向后兼容)。
public typealias ToolApprovalHandler = @Sendable (ToolApprovalRequest) async -> ToolApprovalDecision

/// Tool 输入参数 schema 的来源。
///
/// - `.parameters`: Swift 便利构造, 适合简单平铺 object
/// - `.bundleResource`: 从 Bundle 里加载 .json 文件 (复杂 schema 推荐)
/// - `.raw`: 直接给 raw JSON Schema (programmatic 生成 / inline 大字典)
public enum ToolInputSchema: Sendable {
    case parameters(ToolParameters)
    case bundleResource(name: String, bundle: Bundle = .main, ext: String = "json")
    case raw(AnyCodable)

    /// 把 enum 各分支统一解析成 raw JSON Schema (= AnyCodable 字典)。
    public func resolve() throws -> AnyCodable {
        switch self {
        case .parameters(let params):
            return Self.derive(from: params)
        case .bundleResource(let name, let bundle, let ext):
            return try Self.loadJSON(name: name, bundle: bundle, ext: ext)
        case .raw(let any):
            return any
        }
    }

    private static func derive(from parameters: ToolParameters) -> AnyCodable {
        let props: [String: AnyCodable] = parameters.properties.mapValues { prop in
            var dict: [String: AnyCodable] = [
                "type": AnyCodable(prop.type),
                "description": AnyCodable(prop.description),
            ]
            if let enums = prop.enum {
                dict["enum"] = AnyCodable(enums)
            }
            return AnyCodable(dict)
        }
        let schema: [String: AnyCodable] = [
            "type": AnyCodable(parameters.type),
            "properties": AnyCodable(props),
            "required": AnyCodable(parameters.required),
        ]
        return AnyCodable(schema)
    }

    private static func loadJSON(name: String, bundle: Bundle, ext: String) throws -> AnyCodable {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw ToolInputSchemaError.resourceNotFound(name: name, ext: ext, bundle: bundle.bundleIdentifier ?? "<unknown>")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AnyCodable.self, from: data)
    }
}

public enum ToolInputSchemaError: LocalizedError {
    case resourceNotFound(name: String, ext: String, bundle: String)

    public var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name, let ext, let bundle):
            return "Tool input schema resource '\(name).\(ext)' not found in bundle '\(bundle)'"
        }
    }
}

// MARK: - Tool result

/// 工具执行结果。
///
/// - 简单工具用 `.text("...")` 即可
/// - 截图 / 渲染 类工具用 `.parts([.text("desc"), .image(.data(png, mediaType: "image/png"))])`
///
/// 协议适配层会负责把 `.parts` 拆成对应 provider 的格式 (Anthropic 原生 image block /
/// OpenAI 路径 fallback 到 user multimodal message 接力)。
public enum ToolResult: Sendable {
    case text(String)
    case parts([Part])

    public enum Part: Sendable {
        case text(String)
        case image(ImageSource)
    }

    public enum ImageSource: Sendable {
        case data(Data, mediaType: String)
        case url(URL)
    }

    /// 给 LLM 发回的纯文本部分 (合并所有 .text part); 图片必须靠 imageFiles 单独走。
    public var textObservation: String {
        switch self {
        case .text(let t):
            return t
        case .parts(let parts):
            let texts = parts.compactMap { part -> String? in
                if case .text(let t) = part { return t }
                return nil
            }
            return texts.joined(separator: "\n")
        }
    }

    /// 工具产出的图片, 转成 ChatMessageContent.File 形态由 transport 层接力。
    /// `.base64EncodedImage` 内部约定是完整 data URI (`data:<mediaType>;base64,<...>`),
    /// 这样 transport 层 (asOpenAIMessages) 和自动上传层 (LLMR2UploadProvider) 都能直接消费。
    public var imageFiles: [ChatMessageContent.File] {
        guard case .parts(let parts) = self else { return [] }
        return parts.compactMap { part in
            guard case .image(let src) = part else { return nil }
            switch src {
            case .url(let url):
                return .image(url)
            case .data(let data, let mediaType):
                let dataURI = "data:\(mediaType);base64,\(data.base64EncodedString())"
                return .base64EncodedImage(dataURI)
            }
        }
    }
}

/// Tool parameter schema (Swift 便利结构, 仅适合简单平铺 object)。
/// 复杂 schema (oneOf / $ref / 嵌套 object / array) 请改用 `.bundleResource` 或 `.raw`。
public struct ToolParameters: Codable, Sendable {
    public var type: String
    public var properties: [String: ParameterProperty]
    public var required: [String]

    public init(
        type: String = "object",
        properties: [String: ParameterProperty],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

/// Individual parameter property
public struct ParameterProperty: Codable, Sendable {
    public var type: String
    public var description: String
    public var `enum`: [String]?

    public init(type: String, description: String, enum: [String]? = nil) {
        self.type = type
        self.description = description
        self.enum = `enum`
    }
}

/// Tool execution error
public enum ToolError: LocalizedError {
    case invalidInput(String)
    case executionFailed(String)
    case toolNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        }
    }
}
