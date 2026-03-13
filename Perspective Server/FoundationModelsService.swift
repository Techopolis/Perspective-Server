//
//  FoundationModelsService.swift
//  Perspective Server
//
//  Created by Michael Doise on 9/14/25.
//

import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif
// We use system model APIs for on-device language model access

// MARK: - OpenAI-Compatible Types

nonisolated struct ChatCompletionRequest: Codable, Sendable {
    struct Message: Codable {
        let role: String
        let content: String

        // Support both classic string content and OpenAI-style structured content arrays.
        // We'll flatten any array of content parts into a single text string by concatenating text segments.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.role = (try? c.decode(String.self, forKey: .role)) ?? "user"
            // Try as plain string first
            if let s = try? c.decode(String.self, forKey: .content) {
                self.content = s
                return
            }
            // Try as array of strings
            if let arr = try? c.decode([String].self, forKey: .content) {
                self.content = arr.joined(separator: "\n")
                return
            }
            // Try as array of structured parts
            if let parts = try? c.decode([OAContentPart].self, forKey: .content) {
                let text = parts.compactMap { $0.text }.joined(separator: "")
                self.content = text
                return
            }
            // Try as a single structured part object
            if let part = try? c.decode(OAContentPart.self, forKey: .content) {
                self.content = part.text ?? ""
                return
            }
            // Fallback empty
            self.content = ""
        }

        init(role: String, content: String) {
            self.role = role
            self.content = content
        }

        enum CodingKeys: String, CodingKey { case role, content }
    }
    let model: String
    let messages: [Message]
    let temperature: Double?
    let max_tokens: Int?
    let stream: Bool?
    let multi_segment: Bool?
    // OpenAI-style tools support (optional)
    let tools: [OAITool]?
    let tool_choice: ToolChoice?
    var session_id: String?
}

// Content part per OpenAI structured content. We only use text; non-text parts are ignored.
nonisolated private struct OAContentPart: Codable, Sendable {
    let type: String?
    let text: String?
}

nonisolated struct ChatCompletionResponse: Codable, Sendable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }
        let index: Int
        let message: Message
        let finish_reason: String?
    }
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    var session_id: String?
}

// MARK: - OpenAI Tools Types

nonisolated struct OAITool: Codable, Sendable {
    let type: String // expecting "function"
    let function: OAIFunction?
}

nonisolated struct OAIFunction: Codable, Sendable {
    let name: String
    let description: String?
    let parameters: JSONValue? // arbitrary JSON schema, not used by executor
}

nonisolated enum ToolChoice: Codable, Sendable {
    case none
    case auto
    case required
    case function(name: String)

    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            switch s {
            case "none": self = .none
            case "auto": self = .auto
            case "required": self = .required
            default: self = .auto
            }
            return
        }
        struct FuncWrap: Codable { let type: String?; let function: Func? }
        struct Func: Codable { let name: String }
        if let f = try? decoder.singleValueContainer().decode(FuncWrap.self), let name = f.function?.name {
            self = .function(name: name)
            return
        }
        self = .auto
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .none: var c = encoder.singleValueContainer(); try c.encode("none")
        case .auto: var c = encoder.singleValueContainer(); try c.encode("auto")
        case .required: var c = encoder.singleValueContainer(); try c.encode("required")
        case .function(let name):
            struct Wrapper: Codable { let type: String; let function: Inner }
            struct Inner: Codable { let name: String }
            var c = encoder.singleValueContainer()
            try c.encode(Wrapper(type: "function", function: Inner(name: name)))
        }
    }
}

// A minimal JSON value tree for decoding arbitrary tool parameter shapes
nonisolated enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let o = try? decoder.container(keyedBy: DynamicCodingKeys.self) {
            var dict: [String: JSONValue] = [:]
            for key in o.allKeys {
                let v = try o.decode(JSONValue.self, forKey: key)
                dict[key.stringValue] = v
            }
            self = .object(dict)
            return
        }
        if var a = try? decoder.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !a.isAtEnd { arr.append(try a.decode(JSONValue.self)) }
            self = .array(arr)
            return
        }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s): var c = encoder.singleValueContainer(); try c.encode(s)
        case .number(let d): var c = encoder.singleValueContainer(); try c.encode(d)
        case .bool(let b): var c = encoder.singleValueContainer(); try c.encode(b)
        case .null: var c = encoder.singleValueContainer(); try c.encodeNil()
        case .object(let dict):
            var o = encoder.container(keyedBy: DynamicCodingKeys.self)
            for (k,v) in dict { try o.encode(v, forKey: DynamicCodingKeys(stringValue: k)!) }
        case .array(let arr):
            var a = encoder.unkeyedContainer()
            for v in arr { try a.encode(v) }
        }
    }
}

nonisolated struct DynamicCodingKeys: CodingKey, Sendable {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
}

// MARK: - OpenAI-Compatible Text Completions

nonisolated struct TextCompletionRequest: Codable, Sendable {
    let model: String
    let prompt: String
    let temperature: Double?
    let max_tokens: Int?
    let stream: Bool?

    // Support legacy clients that send prompt as either a string or an array of strings
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try c.decode(String.self, forKey: .model)
        self.temperature = try? c.decode(Double.self, forKey: .temperature)
        self.max_tokens = try? c.decode(Int.self, forKey: .max_tokens)
        self.stream = try? c.decode(Bool.self, forKey: .stream)
        if let s = try? c.decode(String.self, forKey: .prompt) {
            self.prompt = s
        } else if let arr = try? c.decode([String].self, forKey: .prompt) {
            self.prompt = arr.joined(separator: "\n\n")
        } else {
            self.prompt = ""
        }
    }
}

nonisolated struct TextCompletionResponse: Codable, Sendable {
    struct Choice: Codable {
        let text: String
        let index: Int
        let logprobs: String? // null in our case
        let finish_reason: String?
    }
    let id: String
    let object: String // "text_completion"
    let created: Int
    let model: String
    let choices: [Choice]
}

// MARK: - OpenAI-Compatible Models

nonisolated struct OpenAIModel: Codable, Sendable {
    let id: String
    let object: String // "model"
    let created: Int
    let owned_by: String
}

nonisolated struct OpenAIModelList: Codable, Sendable {
    let object: String // "list"
    let data: [OpenAIModel]
}

// MARK: - Inference Semaphore

/// Limits concurrent LLM inference calls to prevent memory pressure and optimize throughput.
/// Requests beyond the limit wait in a FIFO queue until a slot opens.
actor InferenceSemaphore {
    private let maxConcurrent: Int
    private var running: Int = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Total requests completed since server start
    private var totalCompleted: Int = 0
    /// Total requests that had to wait in queue
    private var totalQueued: Int = 0

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        totalQueued += 1
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    func release() {
        running -= 1
        totalCompleted += 1
        if !waiting.isEmpty {
            let next = waiting.removeFirst()
            running += 1
            next.resume()
        }
    }

    var stats: (running: Int, queued: Int, maxConcurrent: Int, totalCompleted: Int, totalQueued: Int) {
        (running, waiting.count, maxConcurrent, totalCompleted, totalQueued)
    }
}

// MARK: - Session Manager

#if canImport(FoundationModels)
/// Caches LanguageModelSession instances by ID so conversations maintain context across turns.
/// Sessions expire after 30 minutes of inactivity and the cache holds at most 50 sessions.
@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
actor SessionManager {
    private struct CachedSession {
        let session: LanguageModelSession
        var lastAccessed: Date
    }

    private var cache: [String: CachedSession] = [:]
    private let maxSessions = 50
    private let ttl: TimeInterval = 30 * 60

    func get(_ id: String) -> LanguageModelSession? {
        guard var entry = cache[id] else { return nil }
        if Date().timeIntervalSince(entry.lastAccessed) > ttl {
            cache.removeValue(forKey: id)
            return nil
        }
        entry.lastAccessed = Date()
        cache[id] = entry
        return entry.session
    }

    func store(_ id: String, session: LanguageModelSession) {
        evictIfNeeded()
        cache[id] = CachedSession(session: session, lastAccessed: Date())
    }

    private func evictIfNeeded() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.lastAccessed) <= ttl }
        while cache.count >= maxSessions {
            if let oldest = cache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed }) {
                cache.removeValue(forKey: oldest.key)
            }
        }
    }

    var count: Int { cache.count }
}
#endif

// MARK: - Foundation Models Service

/// A service that bridges OpenAI-compatible requests to Apple's on-device Foundation Models.
nonisolated final class FoundationModelsService: @unchecked Sendable {
    static let shared = FoundationModelsService()
    private let logger = Logger(subsystem: "com.example.PerspectiveServer", category: "FoundationModelsService")
    private let createdEpoch: Int = Int(Date().timeIntervalSince1970)

    /// Controls how many LLM inference calls run concurrently.
    /// Additional requests queue in FIFO order until a slot opens.
    let inferenceSemaphore = InferenceSemaphore(maxConcurrent: 3)

    /// Backing storage for the session manager (type-erased for conditional compilation)
    private var _sessionManager: Any? = nil

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    var sessionManager: SessionManager {
        if let existing = _sessionManager as? SessionManager { return existing }
        let manager = SessionManager()
        _sessionManager = manager
        return manager
    }
    #endif

    private init() {}

    // MARK: Public API

    /// Handles an OpenAI-compatible chat completion request and returns a response.
    /// Requests are queued through the inference semaphore to manage concurrency.
    func handleChatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        await inferenceSemaphore.acquire()
        defer { Task { await inferenceSemaphore.release() } }

        let inferenceStart = ContinuousClock.now

        // Always use tools for file operations - this enables the model to create/edit files
        // even when the client doesn't explicitly request tool support
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            // Use native Foundation Models with built-in file tools
            let result = try await handleChatCompletionWithBuiltInTools(request)
            let elapsed = ContinuousClock.now - inferenceStart
            let ttft = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let outputLen = result.choices.first?.message.content.count ?? 0
            await ServerMetrics.shared.recordInference(tokens: max(1, outputLen / 4), timeToFirstToken: ttft)
            return result
        }
        #endif

        // Fallback for older systems: If tools are provided, run the tool-calling orchestration flow.
        if let tools = request.tools, !tools.isEmpty {
            let result = try await handleChatCompletionWithTools(request, tools: tools)
            let elapsed = ContinuousClock.now - inferenceStart
            let ttft = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let outputLen = result.choices.first?.message.content.count ?? 0
            await ServerMetrics.shared.recordInference(tokens: max(1, outputLen / 4), timeToFirstToken: ttft)
            return result
        }

        // Build a context-aware prompt that fits within the model's context by summarizing older content when needed.
        let prompt = await prepareChatPrompt(messages: request.messages, model: request.model, temperature: request.temperature, maxTokens: request.max_tokens)
        logger.log("[chat] model=\(request.model, privacy: .public) messages=\(request.messages.count) promptLen=\(prompt.count)")

        // Call into Foundation Models.
        let output = try await generateText(model: request.model, prompt: prompt, temperature: request.temperature, maxTokens: request.max_tokens)
        logger.log("[chat] outputLen=\(output.count)")

        let elapsed = ContinuousClock.now - inferenceStart
        let ttft = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        await ServerMetrics.shared.recordInference(tokens: max(1, output.count / 4), timeToFirstToken: ttft)

        let response = ChatCompletionResponse(
            id: "chatcmpl_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: request.model,
            choices: [
                .init(
                    index: 0,
                    message: .init(role: "assistant", content: output),
                    finish_reason: "stop"
                )
            ]
        )
        return response
    }

    // MARK: - True Token Streaming

    /// Streams a chat completion token-by-token using Foundation Models' streamResponse API.
    /// Each delta (new text since last yield) is passed to the `emit` callback immediately.
    /// Falls back to single-response chunking on systems without FoundationModels.
    /// Returns the resolved session ID (existing or newly created) for the caller to include in SSE.
    @discardableResult
    func streamChatCompletion(
        messages: [ChatCompletionRequest.Message],
        model: String,
        temperature: Double?,
        sessionID: String? = nil,
        emit: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        await inferenceSemaphore.acquire()
        defer { Task { await inferenceSemaphore.release() } }

        let resolvedID = sessionID ?? UUID().uuidString

        // Metrics: track TTFT and token count via a Sendable tracker
        let tracker = StreamMetricsTracker()

        let wrappedEmit: @Sendable (String) async -> Void = { delta in
            tracker.recordDelta(delta)
            await emit(delta)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            try await streamWithFoundationModels(
                messages: messages,
                model: model,
                temperature: temperature,
                sessionID: resolvedID,
                emit: wrappedEmit
            )
            await ServerMetrics.shared.recordInference(tokens: tracker.tokenCount, timeToFirstToken: tracker.ttft)
            return resolvedID
        }
        #endif

        // Fallback for systems without FoundationModels: generate full response and chunk it
        let prompt = await prepareChatPrompt(
            messages: messages, model: model,
            temperature: temperature, maxTokens: nil
        )
        let output = try await generateText(
            model: model, prompt: prompt,
            temperature: temperature, maxTokens: nil
        )
        for chunk in StreamChunker.chunk(text: output, size: 16) {
            await wrappedEmit(chunk)
        }
        await ServerMetrics.shared.recordInference(tokens: tracker.tokenCount, timeToFirstToken: tracker.ttft)
        return resolvedID
    }

    #if canImport(FoundationModels)
    /// True token-by-token streaming using LanguageModelSession.streamResponse(to:).
    /// Reuses a cached session when sessionID matches, otherwise creates and caches a new one.
    /// The stream yields cumulative content; we compute deltas by comparing with previous content.
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    private func streamWithFoundationModels(
        messages: [ChatCompletionRequest.Message],
        model: String,
        temperature: Double?,
        sessionID: String,
        emit: @escaping @Sendable (String) async -> Void
    ) async throws {
        let systemModel = SystemLanguageModel.default

        switch systemModel.availability {
        case .available:
            break
        case .unavailable(let reason):
            logger.error("[fm-stream] Model unavailable: \(String(describing: reason))")
            throw NSError(
                domain: "FoundationModelsService", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model unavailable: \(String(describing: reason))"]
            )
        }

        // Extract the system prompt from messages (sent by the web app as the first message).
        // This goes into the session's instructions parameter, NOT into the user prompt.
        // Mixing system instructions into the user message triggers guardrail false positives.
        let clientSystemPrompt = messages.first(where: { $0.role == "system" })?.content
        let instructions = clientSystemPrompt ?? "You are a helpful assistant."

        // Extract ONLY the last user message — this is what we send to the model.
        // Previous conversation context is maintained by the session's built-in transcript.
        let userMessage = messages.last(where: { $0.role == "user" })?.content ?? messages.last?.content ?? ""

        // Try to reuse a cached session
        var session: LanguageModelSession
        let isExistingSession: Bool

        if let cached = await sessionManager.get(sessionID) {
            session = cached
            isExistingSession = true
            logger.log("[fm-stream] reusing cached session \(sessionID, privacy: .public)")
        } else {
            // Create session with clean instructions (matching Perspective Chat pattern).
            // DO NOT include model identifiers, temperature text, or other metadata in instructions.
            // Temperature is handled via GenerationOptions, not instruction text.
            session = LanguageModelSession(instructions: instructions)
            isExistingSession = false
            logger.log("[fm-stream] created new session \(sessionID, privacy: .public) instructions=\(instructions.prefix(80), privacy: .public)")
        }

        // Always send just the user's message — never a concatenated prompt blob.
        // The session maintains conversation history internally for multi-turn context.
        let prompt = userMessage

        logger.log("[fm-stream] starting stream, prompt len=\(prompt.count), cached=\(isExistingSession)")

        do {
            let stream = session.streamResponse(to: prompt)

            var lastContent = ""
            for try await partialResponse in stream {
                let currentContent = partialResponse.content
                if currentContent.count > lastContent.count {
                    let delta = String(currentContent.dropFirst(lastContent.count))
                    if !delta.isEmpty {
                        await emit(delta)
                    }
                }
                lastContent = currentContent
            }

            // Check if the model returned a soft refusal (not thrown as an error).
            // These poison the session transcript and cause every follow-up to refuse too.
            // IMPORTANT: Apple's model often uses Unicode curly apostrophes (\u{2019}) instead of ASCII ('),
            // so we normalize them before matching.
            let lower = lastContent.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            let isSoftRefusal = lower.contains("i can't assist") ||
                lower.contains("i cannot assist") ||
                lower.contains("i'm not able to help") ||
                lower.contains("i can't help with that") ||
                lower.contains("i cannot help with that") ||
                lower.contains("sorry, but i can't") ||
                lower.contains("sorry, i can't") ||
                (lower.contains("sorry") && lower.contains("can't") && lastContent.count < 150)

            if isSoftRefusal {
                // Evict the poisoned session so the next message gets a fresh one
                logger.warning("[fm-stream] Soft refusal detected for session \(sessionID, privacy: .public) — evicting to prevent refusal spiral")
                await sessionManager.store(sessionID, session: LanguageModelSession(instructions: instructions))
            } else {
                // Cache the healthy session for reuse
                await sessionManager.store(sessionID, session: session)
            }

            let cachedCount = await sessionManager.count
            logger.log("[fm-stream] stream complete, total len=\(lastContent.count), refusal=\(isSoftRefusal), session=\(sessionID, privacy: .public), cached sessions=\(cachedCount)")
        } catch {
            // Handle ALL errors gracefully to prevent the "Unable to stream" fallback.
            // Always evict the session on error — a poisoned transcript causes refusal spirals.
            let errorDesc = String(reflecting: error).lowercased()
            let isGuardrail = errorDesc.contains("guardrailviolation") || errorDesc.contains("refusal") || errorDesc.contains("safety")

            if isGuardrail {
                logger.warning("[fm-stream] Guardrail/refusal for session \(sessionID, privacy: .public) — evicting session: \(errorDesc.prefix(120), privacy: .public)")
            } else {
                logger.error("[fm-stream] Stream error for session \(sessionID, privacy: .public) — evicting session: \(errorDesc.prefix(200), privacy: .public)")
            }

            // Always evict — any error during streaming may have corrupted the session transcript
            await sessionManager.store(sessionID, session: LanguageModelSession(instructions: instructions))
            await emit("I'm not able to help with that particular request. Could you try rephrasing or asking something different?")
        }
    }
    #endif

    #if canImport(FoundationModels)
    /// Handle chat completion with built-in file tools using native Foundation Models
    /// IMPORTANT: Apple's on-device model has a strict 4096 token limit (~16K chars total including tools)
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    private func handleChatCompletionWithBuiltInTools(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let systemModel = SystemLanguageModel.default
        
        // Check availability
        switch systemModel.availability {
        case .available:
            break
        case .unavailable(let reason):
            logger.error("[fm-builtin] Model unavailable: \(String(describing: reason))")
            throw NSError(domain: "FoundationModelsService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model unavailable: \(String(describing: reason))"])
        }
        
        // CRITICAL: Keep instructions VERY short - tool definitions take ~1500 tokens
        // Total budget: 4096 tokens ≈ 16K chars, but tools+response need ~8K
        // So we only have ~8K chars for instructions + prompt combined
        let toolInstructions = """
        You have file operation tools. Use them directly when asked:
        - write_file: create/write files (path, content)
        - read_file: read file contents (path)
        - edit_file: modify files (path, oldText, newText)
        - delete_file: remove files (path)
        - list_directory: list folder contents (path)
        - create_directory: make folders (path)
        Use paths like: "file.txt" (saves to Documents), "~/Desktop/file.txt", etc.
        ALWAYS use tools for file operations - never explain how to do it manually.
        """
        
        // Extract ONLY the last user message - this is what they actually want
        let userMessages = request.messages.filter { $0.role == "user" }
        guard let lastUserMessage = userMessages.last else {
            throw NSError(domain: "FoundationModelsService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No user message found"])
        }
        
        // Extract just the user's actual request from structured content
        // Xcode sends huge context blobs - we need to find the actual question
        var userRequest = lastUserMessage.content
        
        // Look for "The user has asked:" pattern from Xcode extension
        if let askedRange = userRequest.range(of: "The user has asked:", options: .caseInsensitive) {
            userRequest = String(userRequest[askedRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let askedRange = userRequest.range(of: "user:", options: [.caseInsensitive, .backwards]) {
            // Fallback: get content after last "user:"
            userRequest = String(userRequest[askedRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Aggressively truncate to stay within context (leave room for tools + response)
        // Max prompt: ~2000 chars to be safe (500 tokens)
        let maxPromptChars = 2000
        if userRequest.count > maxPromptChars {
            userRequest = String(userRequest.prefix(maxPromptChars)) + "..."
        }
        
        // Simple, direct prompt
        let prompt = userRequest
        
        let totalChars = toolInstructions.count + prompt.count
        let estimatedTokens = (totalChars + 3) / 4
        logger.log("[fm-builtin] Creating session: instructions=\(toolInstructions.count) chars, prompt=\(prompt.count) chars, est tokens=\(estimatedTokens)")
        
        // Create session with file tools
        let session = LanguageModelSession(
            tools: [
                ReadFileTool(),
                WriteFileTool(),
                EditFileTool(),
                DeleteFileTool(),
                MoveFileTool(),
                ListDirectoryTool(),
                CreateDirectoryTool(),
                CheckPathTool()
            ],
            instructions: toolInstructions
        )
        
        let response = try await session.respond(to: prompt)
        logger.log("[fm-builtin] Got response len=\(response.content.count)")
        
        return ChatCompletionResponse(
            id: "chatcmpl_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: request.model,
            choices: [
                .init(index: 0, message: .init(role: "assistant", content: response.content), finish_reason: "stop")
            ]
        )
    }
    #endif

    /// Tool-calling orchestration using native Foundation Models Tool protocol.
    /// The LanguageModelSession handles tool execution automatically when tools are provided.
    private func handleChatCompletionWithTools(_ request: ChatCompletionRequest, tools: [OAITool]) async throws -> ChatCompletionResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            do {
                let output = try await generateWithNativeTools(request: request, tools: tools)
                return ChatCompletionResponse(
                    id: "chatcmpl_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                    object: "chat.completion",
                    created: Int(Date().timeIntervalSince1970),
                    model: request.model,
                    choices: [
                        .init(index: 0, message: .init(role: "assistant", content: output), finish_reason: "stop")
                    ]
                )
            } catch {
                logger.error("[tools] Native tool calling failed: \(String(describing: error))")
                // Fall through to legacy text-based approach
            }
        }
        #endif
        
        // Legacy fallback: text-based tool calling for older systems
        return try await handleChatCompletionWithToolsLegacy(request, tools: tools)
    }
    
    /// Legacy text-based tool calling (fallback when native tools unavailable)
    private func handleChatCompletionWithToolsLegacy(_ request: ChatCompletionRequest, tools: [OAITool]) async throws -> ChatCompletionResponse {
        // Build an augmented system instruction describing available tools and the exact JSON contract.
        let toolIntro = toolsDescription(tools)
        var msgs: [ChatCompletionRequest.Message] = []
        msgs.append(.init(role: "system", content: toolIntro))
        msgs.append(contentsOf: request.messages)

        // First round: ask the model if it wants to call a tool; if so, it must reply ONLY with the JSON envelope.
        let prompt1 = await prepareChatPrompt(messages: msgs, model: request.model, temperature: request.temperature, maxTokens: request.max_tokens)
        let out1 = try await generateText(model: request.model, prompt: prompt1, temperature: request.temperature, maxTokens: request.max_tokens)
        logger.log("[tools] first-round len=\(out1.count)")

        if let call = parseToolCall(from: out1) {
            // Execute tool
            let result = try await ToolsRegistry.shared.execute(name: call.name, arguments: call.arguments)
            let resultText = jsonString(result) ?? String(describing: result)
            // Append tool call and tool result, then ask for the final answer.
            msgs.append(.init(role: "assistant", content: out1))
            msgs.append(.init(role: "tool", content: resultText))
            let prompt2 = await prepareChatPrompt(messages: msgs, model: request.model, temperature: request.temperature, maxTokens: request.max_tokens)
            let out2 = try await generateText(model: request.model, prompt: prompt2, temperature: request.temperature, maxTokens: request.max_tokens)
            return ChatCompletionResponse(
                id: "chatcmpl_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                object: "chat.completion",
                created: Int(Date().timeIntervalSince1970),
                model: request.model,
                choices: [
                    .init(index: 0, message: .init(role: "assistant", content: out2), finish_reason: "stop")
                ]
            )
        } else {
            // No tool call requested; treat out1 as the final answer.
            return ChatCompletionResponse(
                id: "chatcmpl_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                object: "chat.completion",
                created: Int(Date().timeIntervalSince1970),
                model: request.model,
                choices: [
                    .init(index: 0, message: .init(role: "assistant", content: out1), finish_reason: "stop")
                ]
            )
        }
    }
    
    #if canImport(FoundationModels)
    /// Generate response using native Foundation Models Tool protocol.
    /// The session automatically handles tool calling and execution.
    /// CRITICAL: Must stay within 4096 token limit (~16K chars total)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func generateWithNativeTools(request: ChatCompletionRequest, tools: [OAITool]) async throws -> String {
        let systemModel = SystemLanguageModel.default
        
        // Check availability
        switch systemModel.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw NSError(domain: "FoundationModelsService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model unavailable: \(String(describing: reason))"])
        }
        
        // VERY short instructions - tool definitions already take ~1500 tokens
        let instructions = """
        You have file tools. Use them directly for file operations:
        - write_file(path, content): create/write files
        - read_file(path): read files
        - edit_file(path, oldText, newText): modify files
        - delete_file(path): remove files
        Use simple paths like "file.txt" or "~/Desktop/file.txt".
        """
        
        // Extract ONLY the last user message's actual request
        let userMessages = request.messages.filter { $0.role == "user" }
        var prompt = userMessages.last?.content ?? ""
        
        // Extract the actual request if wrapped in Xcode boilerplate
        if let askedRange = prompt.range(of: "The user has asked:", options: .caseInsensitive) {
            prompt = String(prompt[askedRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Strictly limit prompt size
        if prompt.count > 2000 {
            prompt = String(prompt.prefix(2000)) + "..."
        }
        
        // Create session with file tools - the session handles tool calling automatically
        let session = LanguageModelSession(
            tools: [
                ReadFileTool(),
                WriteFileTool(),
                EditFileTool(),
                DeleteFileTool(),
                MoveFileTool(),
                ListDirectoryTool(),
                CreateDirectoryTool(),
                CheckPathTool()
            ],
            instructions: instructions
        )
        
        logger.log("[fm-native-tools] requesting response, prompt len=\(prompt.count)")
        
        // The respond method automatically executes tools when the model requests them
        let response = try await session.respond(to: prompt)
        
        logger.log("[fm-native-tools] got response len=\(response.content.count)")
        return response.content
    }
    #endif

    // MARK: - Context management for Chat

    /// Prepares a clean user prompt from the messages array.
    /// System prompts are NOT included here — they belong in LanguageModelSession instructions.
    /// Mixing role prefixes (e.g., "system:", "user:") into the prompt text triggers guardrail
    /// false positives because the model interprets it as prompt injection.
    private func prepareChatPrompt(messages: [ChatCompletionRequest.Message], model: String, temperature: Double?, maxTokens: Int?) async -> String {
        // Apple's model has a HARD 4096 token limit (~16K chars total).
        // With response needing ~1000 tokens, we can only use ~3000 tokens (~12K chars) for input.
        // Being conservative: target 4K chars max to leave room for response + instructions.
        let maxInputChars = 4000

        // Find the LAST user message - this is what actually matters
        var lastUserContent = ""
        for msg in messages.reversed() {
            if msg.role == "user" {
                lastUserContent = msg.content
                break
            }
        }

        // Extract just the user's actual request (skip Xcode boilerplate)
        var userRequest = lastUserContent

        // Look for "The user has asked:" pattern from Xcode extension
        if let askedRange = userRequest.range(of: "The user has asked:", options: .caseInsensitive) {
            userRequest = String(userRequest[askedRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Truncate user request if needed
        if userRequest.count > maxInputChars {
            userRequest = String(userRequest.prefix(maxInputChars)) + "..."
        }

        let estimatedTokens = approxTokenCount(userRequest)
        logger.log("[chat.ctx] final prompt: chars=\(userRequest.count) tokens≈\(estimatedTokens)")

        // Return ONLY the user's message — no role prefixes, no "assistant:" suffix.
        // The LanguageModelSession handles role separation internally.
        return userRequest
    }

    /// Rough token estimate (heuristic): ~4 chars per token.
    private func approxTokenCount(_ text: String) -> Int {
        return max(1, (text.count + 3) / 4)
    }

    /// Clamp very large input before summarization to avoid exceeding FM limits during the summarization step.
    private func clampForSummarization(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        // Keep head and tail slices to retain both early and late context in the summary input
        let half = maxChars / 2
        let head = text.prefix(half)
        let tail = text.suffix(maxChars - half)
        return String(head) + "\n…\n" + String(tail)
    }

    /// Summarize text using FoundationModels when available; fallback to a naïve extract if not.
    private func summarizeText(_ text: String, targetChars: Int, model: String, temperature: Double?) async -> String {
        let instruction = "Summarize the following content in under \(targetChars) characters, preserving key technical details, APIs, and decisions relevant to the user’s most recent request. Use concise bullet points if helpful."
        let prompt = "Instructions:\n\(instruction)\n\nContent to summarize:\n\n\(text)"
        do {
            let out = try await generateText(model: model, prompt: prompt, temperature: temperature, maxTokens: nil)
            if out.count > targetChars {
                // Light clamp on the generated summary to respect target size
                return String(out.prefix(targetChars))
            }
            return out
        } catch {
            // Fall back to a naïve extract when FM is not available
            let sentences = text.split(separator: ".")
            let head = sentences.prefix(8).joined(separator: ". ")
            let tail = sentences.suffix(4).joined(separator: ". ")
            let combined = "\(head). … \(tail)."
            if combined.count > targetChars {
                return String(combined.prefix(targetChars))
            }
            return combined
        }
    }

    /// Handles an OpenAI-compatible text completion request and returns a response.
    func handleCompletion(_ request: TextCompletionRequest) async throws -> TextCompletionResponse {
        await inferenceSemaphore.acquire()
        defer { Task { await inferenceSemaphore.release() } }
        logger.log("[text] model=\(request.model, privacy: .public) promptLen=\(request.prompt.count)")
        let output = try await generateText(model: request.model, prompt: request.prompt, temperature: request.temperature, maxTokens: request.max_tokens)
        logger.log("[text] outputLen=\(output.count)")

        let response = TextCompletionResponse(
            id: "cmpl_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            object: "text_completion",
            created: Int(Date().timeIntervalSince1970),
            model: request.model,
            choices: [
                .init(text: output, index: 0, logprobs: nil, finish_reason: "stop")
            ]
        )
        return response
    }

    // MARK: - Ollama-compatible chat

    struct OllamaMessage: Codable {
        let role: String
        let content: String
    }

    struct OllamaChatRequest: Codable {
        let model: String
        let messages: [OllamaMessage]
        let stream: Bool?
        let options: OllamaChatOptions?
    }

    struct OllamaChatOptions: Codable {
        let temperature: Double?
        let num_predict: Int?
    }

    struct OllamaChatResponse: Codable {
        let model: String
        let created_at: String
        let message: OllamaMessage
        let done: Bool
        let total_duration: Int64?
    }

    func handleOllamaChat(_ request: OllamaChatRequest) async throws -> OllamaChatResponse {
        await inferenceSemaphore.acquire()
        defer { Task { await inferenceSemaphore.release() } }
        let temperature = request.options?.temperature
        let maxTokens = request.options?.num_predict
        // Reuse our chat completion pipeline by mapping roles/content
        let mapped = request.messages.map { ChatCompletionRequest.Message(role: $0.role, content: $0.content) }
    let chatReq = ChatCompletionRequest(model: request.model, messages: mapped, temperature: temperature, max_tokens: maxTokens, stream: false, multi_segment: nil, tools: nil, tool_choice: nil)
        let resp = try await handleChatCompletion(chatReq)
        let iso = ISO8601DateFormatter()
        let createdAt = iso.string(from: Date(timeIntervalSince1970: TimeInterval(resp.created)))
        let outMessage = OllamaMessage(role: resp.choices.first?.message.role ?? "assistant", content: resp.choices.first?.message.content ?? "")
        return OllamaChatResponse(model: resp.model, created_at: createdAt, message: outMessage, done: true, total_duration: nil)
    }

    /// Returns the list of available models in OpenAI format. For now we expose a single on-device model id.
    func listModels() -> OpenAIModelList {
        let models = availableModels()
        return OpenAIModelList(object: "list", data: models)
    }

    /// Returns a single model by id in OpenAI format, if available.
    func getModel(id: String) -> OpenAIModel? {
        return availableModels().first { $0.id == id }
    }

    // MARK: Ollama-compatible models list (/api/tags)

    struct OllamaTagDetails: Codable {
        let format: String?
        let family: String?
        let families: [String]?
        let parameter_size: String?
        let quantization_level: String?
    }

    struct OllamaTagModel: Codable {
        let name: String
        let modified_at: String
        let size: Int64?
        let digest: String?
        let details: OllamaTagDetails?
    }

    struct OllamaTagsResponse: Codable {
        let models: [OllamaTagModel]
    }

    func listOllamaTags() -> OllamaTagsResponse {
        let iso = ISO8601DateFormatter()
        let modified = iso.string(from: Date(timeIntervalSince1970: TimeInterval(createdEpoch)))
        let model = OllamaTagModel(
            name: "apple.local:latest",
            modified_at: modified,
            size: nil,
            digest: nil,
            details: OllamaTagDetails(
                format: "system",
                family: "apple-intelligence",
                families: ["apple-intelligence"],
                parameter_size: nil,
                quantization_level: nil
            )
        )
        return OllamaTagsResponse(models: [model])
    }

    // MARK: - Private helpers

    private func buildPrompt(from messages: [ChatCompletionRequest.Message]) -> String {
        // Simple concatenation of messages in role: content format.
        var parts: [String] = []
        for msg in messages {
            parts.append("\(msg.role): \(msg.content)")
        }
        parts.append("assistant:")
        return parts.joined(separator: "\n")
    }

    // Build a tool intro system message describing available tools and the JSON envelope to request them
    private func toolsDescription(_ tools: [OAITool]) -> String {
        var lines: [String] = []
        lines.append("You have access to file operation tools. When you need to read, write, edit, or manage files, use these tools.")
        lines.append("")
        lines.append("To call a tool, reply ONLY with a single JSON object in this exact format (no other text):")
        lines.append("{\"tool_call\": {\"name\": \"<tool-name>\", \"arguments\": { ... }}}")
        lines.append("")
        lines.append("Available tools:")
        
        // Include client-provided tools
        for t in tools {
            if t.type == "function", let f = t.function {
                let desc = f.description ?? ""
                lines.append("- \(f.name): \(desc)")
            }
        }
        
        // Always include built-in file tools
        lines.append("")
        lines.append("Built-in file tools (always available):")
        lines.append("- read_file: Read contents of a file. Args: {\"path\": \"/absolute/path\", \"max_bytes\": 1048576}")
        lines.append("- write_file: Create or overwrite a file. Args: {\"path\": \"/absolute/path\", \"content\": \"file contents\"}")
        lines.append("- edit_file: Edit a file by replacing text. Args: {\"path\": \"/path\", \"old_text\": \"text to find\", \"new_text\": \"replacement\"}")
        lines.append("- delete_file: Delete a file or directory. Args: {\"path\": \"/path\", \"recursive\": false}")
        lines.append("- move_file: Move or rename a file. Args: {\"source_path\": \"/from\", \"destination_path\": \"/to\"}")
        lines.append("- copy_file: Copy a file. Args: {\"source_path\": \"/from\", \"destination_path\": \"/to\"}")
        lines.append("- list_directory: List directory contents. Args: {\"path\": \"/dir\", \"recursive\": false, \"include_hidden\": false}")
        lines.append("- create_directory: Create a directory. Args: {\"path\": \"/new/dir\"}")
        lines.append("- check_path: Check if path exists. Args: {\"path\": \"/path\"}")
        lines.append("")
        lines.append("IMPORTANT: Use absolute paths starting with /. After calling a tool, I will provide the result and you should respond based on it.")
        
        return lines.joined(separator: "\n")
    }

    // Parse a tool call from model output, expecting a JSON envelope as instructed
    private func parseToolCall(from text: String) -> (name: String, arguments: JSONValue)? {
        struct Envelope: Codable { let tool_call: Inner }
        struct Inner: Codable { let name: String; let arguments: JSONValue }
        // Try direct decode first
        if let data = text.data(using: .utf8), let env = try? JSONDecoder().decode(Envelope.self, from: data) {
            return (env.tool_call.name, env.tool_call.arguments)
        }
        // Try to find a JSON object substring
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            let sub = String(text[start...end])
            if let data = sub.data(using: .utf8), let env = try? JSONDecoder().decode(Envelope.self, from: data) {
                return (env.tool_call.name, env.tool_call.arguments)
            }
        }
        return nil
    }

    // Serialize JSONValue to a compact string
    private func jsonString(_ v: JSONValue) -> String? {
        func encode(_ v: JSONValue) -> Any {
            switch v {
            case .string(let s): return s
            case .number(let d): return d
            case .bool(let b): return b
            case .null: return NSNull()
            case .object(let o): return o.mapValues { encode($0) }
            case .array(let a): return a.map { encode($0) }
            }
        }
        let any = encode(v)
        guard JSONSerialization.isValidJSONObject(any) else { return nil }
        if let data = try? JSONSerialization.data(withJSONObject: any, options: []) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    // Replace this with actual Foundation Models generation when available in your target.
    private func generateText(model: String, prompt: String, temperature: Double?, maxTokens: Int?) async throws -> String {
        // Prefer Apple Intelligence on supported platforms; otherwise return a graceful fallback
        logger.log("Generating text (FoundationModels if available, else fallback)")

        #if canImport(FoundationModels)
        logger.log("[fm] FoundationModels framework is available at compile time")
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            logger.log("[fm] Runtime availability check passed - attempting to use FoundationModels")
            do {
                return try await generateWithFoundationModels(model: model, prompt: prompt, temperature: temperature)
            } catch {
                logger.error("FoundationModels failed: \(String(describing: error))")
                // Fall through to fallback message below without truncating the prompt
            }
        } else {
            logger.warning("[fm] Runtime availability check FAILED - macOS 26.0+ required. Current OS version does not meet requirements.")
        }
        #else
        logger.warning("[fm] FoundationModels framework NOT available at compile time")
        #endif

        // Fallback path when FoundationModels is not available on this platform/SDK.
        let trimmed = prompt.split(separator: "\n").last.map(String.init) ?? prompt
        let fallback = "(Local fallback) Apple Intelligence unavailable: returning a synthetic response. Based on your prompt, here's an echo: \(trimmed.replacingOccurrences(of: "assistant:", with: "").trimmingCharacters(in: .whitespaces)))"
        return fallback
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func generateWithFoundationModels(model: String, prompt: String, temperature: Double?) async throws -> String {
        // Use the system-managed on-device language model
        let systemModel = SystemLanguageModel.default

        // Check availability and provide descriptive errors for callers
        switch systemModel.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            throw NSError(domain: "FoundationModelsService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Device not eligible for Apple Intelligence."])
        case .unavailable(.appleIntelligenceNotEnabled):
            throw NSError(domain: "FoundationModelsService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence is not enabled. Please enable it in Settings."])
        case .unavailable(.modelNotReady):
            throw NSError(domain: "FoundationModelsService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Model not ready (e.g., downloading). Try again later."])
        case .unavailable(let other):
            throw NSError(domain: "FoundationModelsService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Model unavailable: \(String(describing: other))"])
        }

        // Lean instructions only — no model identifiers or temperature text.
        // Matches the Perspective Chat pattern: minimal instructions to avoid guardrail triggers.
        let instructions = "You are a helpful assistant."

        // Create a short-lived session for this request
        let session = LanguageModelSession(instructions: instructions)

        logger.log("[fm] requesting response len=\(prompt.count)")
        do {
            let response = try await session.respond(to: prompt)
            logger.log("[fm] got response len=\(response.content.count)")
            return response.content
        } catch {
            let errorDesc = String(reflecting: error).lowercased()
            if errorDesc.contains("guardrailviolation") || errorDesc.contains("refusal") {
                logger.warning("[fm] Guardrail/refusal hit — returning friendly message")
                return "I'm not able to help with that particular request. Could you try rephrasing or asking something different?"
            }
            throw error
        }
    }
    
    /// Generate text with native Foundation Models Tool support
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func generateWithTools(model: String, prompt: String, temperature: Double?) async throws -> String {
        let systemModel = SystemLanguageModel.default
        
        // Check availability
        switch systemModel.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw NSError(domain: "FoundationModelsService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model unavailable: \(String(describing: reason))"])
        }
        
        // Lean instructions — no model identifiers or temperature text (wastes tokens, confuses model)
        let instructions = "You are a helpful assistant with access to file operation tools. When you need to read, write, edit, or manage files, use the available tools."
        
        // Create session with file tools
        let session = LanguageModelSession(
            tools: [
                ReadFileTool(),
                WriteFileTool(),
                EditFileTool(),
                DeleteFileTool(),
                MoveFileTool(),
                ListDirectoryTool(),
                CreateDirectoryTool(),
                CheckPathTool()
            ],
            instructions: instructions
        )
        
        logger.log("[fm-tools] requesting response with tools, prompt len=\(prompt.count)")
        let response = try await session.respond(to: prompt)
        logger.log("[fm-tools] got response len=\(response.content.count)")
        return response.content
    }
    #endif

    // MARK: - Models inventory

    private func availableModels() -> [OpenAIModel] {
        // Single logical model ID exposed to clients using OpenAI format. Keep stable for compatibility.
        // We report ownership as "system" since it's provided by on-device Apple Intelligence.
        let model = OpenAIModel(
            id: "apple.local",
            object: "model",
            created: createdEpoch,
            owned_by: "system"
        )
        return [model]
    }
}

// MARK: - Multi-segment chat generation (optional)

extension FoundationModelsService {
    /// Generate a long-form response in multiple segments by chaining short sessions.
    /// Each segment is streamed back via the `emit` callback as soon as it's generated.
    func generateChatSegments(messages: [ChatCompletionRequest.Message], model: String, temperature: Double?, segmentChars: Int = 900, maxSegments: Int = 4, emit: @escaping (String) async -> Void) async throws {
        await inferenceSemaphore.acquire()
        defer { Task { await inferenceSemaphore.release() } }
        // Prepare initial prompt within context budget
        let basePrompt = await prepareChatPrompt(messages: messages, model: model, temperature: temperature, maxTokens: nil)
        let tokens = approxTokenCount(basePrompt)
        logger.log("[chat.multi] basePromptLen=\(basePrompt.count) tokens=\(tokens) segChars=\(segmentChars) maxSeg=\(maxSegments)")
        var soFar = ""

        // Helper to build instructions for each segment
        func instructions(forRound round: Int) -> String {
            var parts: [String] = []
            parts.append("You are a helpful assistant. Continue the answer succinctly and cohesively.")
            parts.append("Aim for about \(segmentChars) characters in this segment; do not repeat prior content.")
            if round > 1 {
                parts.append("So far, you've written the following (do not repeat, only continue):\n\(soFar.suffix(1500))")
            }
            return parts.joined(separator: "\n")
        }

        // First segment uses the full prepared prompt
        for round in 1...maxSegments {
            let prompt: String
            if round == 1 {
                prompt = basePrompt
            } else {
                prompt = "\(basePrompt)\n\nassistant:"
            }

            do {
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                    // Create a fresh short-lived session per segment with tailored instructions
                    let session = LanguageModelSession(instructions: instructions(forRound: round))
                    let response = try await session.respond(to: prompt)
                    let segment = response.content
                    logger.log("[chat.multi] round=\(round) segLen=\(segment.count)")
                    if !segment.isEmpty {
                        soFar += segment
                        await emit(segment)
                    }
                } else {
                    let segment = try await self.generateText(model: model, prompt: instructions(forRound: round) + "\n\n" + prompt, temperature: temperature, maxTokens: nil)
                    logger.log("[chat.multi] round=\(round) segLen=\(segment.count)")
                    if !segment.isEmpty {
                        soFar += segment
                        await emit(segment)
                    }
                }
                #else
                let segment = try await self.generateText(model: model, prompt: instructions(forRound: round) + "\n\n" + prompt, temperature: temperature, maxTokens: nil)
                logger.log("[chat.multi] round=\(round) segLen=\(segment.count)")
                if !segment.isEmpty {
                    soFar += segment
                    await emit(segment)
                }
                #endif
            } catch {
                // Propagate error so caller can send a friendly fallback and finalize the stream
                throw error
            }

            // Heuristic stop: if the last segment is short, assume completion
            if soFar.count >= segmentChars * (round - 1) + Int(Double(segmentChars) * 0.6) {
                // continue
            } else {
                break
            }
        }
    }
}

// (no prompt truncation utilities by design)


// MARK: - Tools Registry

nonisolated private final class ToolsRegistry: @unchecked Sendable {
    static let shared = ToolsRegistry()
    private let logger = Logger(subsystem: "com.example.PerspectiveIntelligence", category: "ToolsRegistry")
    private let fileTools = FileToolsManager.shared

    private init() {
        logger.log("[tools] ToolsRegistry initialized with FileToolsManager")
    }

    // Execute a tool by name with JSONValue arguments
    func execute(name: String, arguments: JSONValue) async throws -> JSONValue {
        logger.log("[tools] Executing tool: \(name, privacy: .public)")
        
        switch name {
        case "read_file":
            guard let path = argString(arguments, key: "path") else {
                return .object(["error": .string("Missing 'path' argument")])
            }
            let maxBytes = argInt(arguments, key: "max_bytes") ?? argInt(arguments, key: "maxBytes") ?? 1024 * 1024
            do {
                let result = try fileTools.readFile(path: path, maxBytes: maxBytes)
                return .object([
                    "path": .string(result.path),
                    "content": .string(result.content),
                    "size": .number(Double(result.size)),
                    "truncated": .bool(result.truncated)
                ])
            } catch {
                return .object(["error": .string(error.localizedDescription)])
            }
            
        case "write_file":
            guard let path = argString(arguments, key: "path") else {
                return .object(["error": .string("Missing 'path' argument")])
            }
            let content = argString(arguments, key: "content") ?? ""
            do {
                let result = try fileTools.writeFile(path: path, content: content)
                return .object([
                    "path": .string(result.path),
                    "bytes_written": .number(Double(result.bytesWritten)),
                    "created": .bool(result.created)
                ])
            } catch {
                return .object(["error": .string(error.localizedDescription)])
            }
            
        case "edit_file":
            guard let path = argString(arguments, key: "path") else {
                return .object(["error": .string("Missing 'path' argument")])
            }
            let oldText = argString(arguments, key: "old_text") ?? argString(arguments, key: "oldText")
            let newText = argString(arguments, key: "new_text") ?? argString(arguments, key: "newText") ?? ""
            let lineNumber = argInt(arguments, key: "line_number") ?? argInt(arguments, key: "lineNumber")
            do {
                let result = try fileTools.editFile(path: path, oldText: oldText, newText: newText, lineNumber: lineNumber)
                return .object([
                    "path": .string(result.path),
                    "success": .bool(result.success),
                    "message": .string(result.message),
                    "changes_count": .number(Double(result.changesCount))
                ])
            } catch {
                return .object(["error": .string(error.localizedDescription)])
            }
            
        case "delete_file":
            guard let path = argString(arguments, key: "path") else {
                return .object(["error": .string("Missing 'path' argument")])
            }
            let recursive = argBool(arguments, key: "recursive") ?? false
            do {
                let result = try fileTools.deleteFile(path: path, recursive: recursive)
                return .object([
                    "path": .string(result.path),
                    "deleted": .bool(result.deleted),
                    "was_directory": .bool(result.wasDirectory)
                ])
            } catch {
                return .object(["error": .string(error.localizedDescription)])
            }
            
        case "move_file":
            guard let sourcePath = argString(arguments, key: "source_path") ?? argString(arguments, key: "sourcePath") else {
                return .object(["error": .string("Missing 'source_path' argument")])
            }
            guard let destPath = argString(arguments, key: "destination_path") ?? argString(arguments, key: "destinationPath") else {
                return .object(["error": .string("Missing 'destination_path' argument")])
            }
            do {
                let result = try fileTools.moveFile(sourcePath: sourcePath, destinationPath: destPath)
                return .object([
                    "source_path": .string(result.sourcePath),
                    "destination_path": .string(result.destinationPath),
                    "success": .bool(result.success)
                ])
            } catch {
                return .object(["error": .string(error.localizedDescription)])
            }
            
        case "copy_file":
            guard let sourcePath = argString(arguments, key: "source_path") ?? argString(arguments, key: "sourcePath") else {
                return .object(["error": .string("Missing 'source_path' argument")])
            }
            guard let destPath = argString(arguments, key: "destination_path") ?? argString(arguments, key: "destinationPath") else {
                return .object(["error": .string("Missing 'destination_path' argument")])
            }
            do {
                let result = try fileTools.copyFile(sourcePath: sourcePath, destinationPath: destPath)
                return .object([
                    "source_path": .string(result.sourcePath),
                    "destination_path": .string(result.destinationPath),
                    "success": .bool(result.success)
                ])
            } catch {
                return .object(["error": .string(error.localizedDescription)])
            }
            
        case "list_directory", "list_dir":
            guard let path = argString(arguments, key: "path") else {
                return .object(["error": .string("Missing 'path' argument")])
            }
            let recursive = argBool(arguments, key: "recursive") ?? false
            let includeHidden = argBool(arguments, key: "include_hidden") ?? argBool(arguments, key: "includeHidden") ?? false
            do {
                let result = try fileTools.listDirectory(path: path, recursive: recursive, includeHidden: includeHidden)
                let itemsArray = result.items.map { item -> JSONValue in
                    .object([
                        "name": .string(item.name),
                        "is_directory": .bool(item.isDirectory),
                        "size": .number(Double(item.size))
                    ])
                }
                return .object([
                    "path": .string(result.path),
                    "items": .array(itemsArray),
                    "count": .number(Double(result.count))
                ])
            } catch {
                return .object(["error": .string(error.localizedDescription)])
            }
            
        case "create_directory":
            guard let path = argString(arguments, key: "path") else {
                return .object(["error": .string("Missing 'path' argument")])
            }
            do {
                let result = try fileTools.createDirectory(path: path)
                return .object([
                    "path": .string(result.path),
                    "created": .bool(result.created),
                    "already_exists": .bool(result.alreadyExists)
                ])
            } catch {
                return .object(["error": .string(error.localizedDescription)])
            }
            
        case "check_path":
            guard let path = argString(arguments, key: "path") else {
                return .object(["error": .string("Missing 'path' argument")])
            }
            do {
                let result = try fileTools.checkPath(path: path)
                var obj: [String: JSONValue] = [
                    "path": .string(result.path),
                    "exists": .bool(result.exists),
                    "is_directory": .bool(result.isDirectory),
                    "is_file": .bool(result.isFile)
                ]
                if let size = result.size {
                    obj["size"] = .number(Double(size))
                }
                return .object(obj)
            } catch {
                return .object(["error": .string(error.localizedDescription)])
            }
            
        default:
            logger.warning("[tools] Unknown tool: \(name, privacy: .public)")
            return .object(["error": .string("Unknown tool: \(name)")])
        }
    }

    // Helpers
    private func argString(_ args: JSONValue, key: String) -> String? {
        if case .object(let dict) = args, case .string(let s)? = dict[key] { return s }
        return nil
    }
    
    private func argInt(_ args: JSONValue, key: String) -> Int? {
        if case .object(let dict) = args, let v = dict[key] {
            switch v {
            case .number(let d): return Int(d)
            case .string(let s): return Int(s)
            default: return nil
            }
        }
        return nil
    }
    
    private func argBool(_ args: JSONValue, key: String) -> Bool? {
        if case .object(let dict) = args, let v = dict[key] {
            switch v {
            case .bool(let b): return b
            case .string(let s): return s.lowercased() == "true" || s == "1"
            case .number(let d): return d != 0
            default: return nil
            }
        }
        return nil
    }
}

