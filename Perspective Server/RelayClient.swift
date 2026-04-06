//
//  RelayClient.swift
//  Perspective Server
//
//  WebSocket relay client that connects to the Perspective Intelligence Web
//  backend, allowing remote browser users to chat with the local AI server.
//

import Foundation
import OSLog

/// Connection status for the relay WebSocket.
enum RelayStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case waitingForAuth
    case waitingForPairing
    case paired(userId: String)
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .waitingForAuth: return "Authenticating..."
        case .waitingForPairing: return "Waiting for pairing"
        case .paired: return "Paired"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isConnected: Bool {
        switch self {
        case .waitingForPairing, .paired: return true
        default: return false
        }
    }
}

actor RelayClient {
    static let shared = RelayClient()

    private let logger = Logger(subsystem: "com.example.PerspectiveServer", category: "RelayClient")
    private let relayURL = URL(string: "wss://perspective-intelligence-web-cciod.ondigitalocean.app/api/relay/connect")!

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    private(set) var status: RelayStatus = .disconnected
    private var isEnabled: Bool = false
    private var reconnectDelay: TimeInterval = 2
    private let maxReconnectDelay: TimeInterval = 60
    private let relayTokenKey = "com.perspective.relayToken"

    /// Callback invoked on the MainActor when status changes.
    private var onStatusChange: (@Sendable (RelayStatus) -> Void)?

    private init() {}

    // MARK: - Public API

    func setStatusCallback(_ callback: @escaping @Sendable (RelayStatus) -> Void) {
        onStatusChange = callback
    }

    func connect() async {
        guard !isEnabled else {
            logger.log("RelayClient.connect() skipped — already enabled")
            AppLog.debug("Connect skipped because relay is already enabled", source: "relay")
            return
        }
        isEnabled = true
        reconnectDelay = 2
        await startConnection()
    }

    func disconnect() async {
        isEnabled = false
        cancelAll()
        updateStatus(.disconnected)
    }

    // MARK: - Connection Lifecycle

    private func startConnection() async {
        cancelAll()
        updateStatus(.connecting)
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: relayURL)
        webSocketTask = task
        task.resume()

        // Start receiving messages
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
    }

    private func cancelAll() {
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func scheduleReconnect() {
        guard isEnabled else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
        logger.log("Scheduling reconnect in \(delay, privacy: .public)s")
        AppLog.warning("Relay reconnect scheduled in \(Int(delay))s", source: "relay")
        updateStatus(.disconnected)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            guard !Task.isCancelled else { return }
            await self.startConnection()
        }
    }

    // MARK: - Message Loop

    private func receiveLoop() async {
        guard let ws = webSocketTask else {
            logger.error("RelayClient: receiveLoop — no webSocketTask")
            return
        }
        updateStatus(.waitingForAuth)

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                await handleMessage(message)
            } catch {
                guard isEnabled else { return }
                logger.error("WebSocket receive error: \(String(describing: error), privacy: .public)")
                scheduleReconnect()
                return
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            logger.warning("Received non-JSON or missing type field")
            return
        }

        switch type {
        case "welcome":
            logger.log("Received welcome from relay")
            await sendAuth()

        case "auth_ok":
            logger.log("Auth accepted, waiting for user to pair")
            reconnectDelay = 2
            updateStatus(.waitingForPairing)
            startPingTimer()

        case "paired":
            let userId = json["userId"] as? String ?? "unknown"
            logger.log("Paired with user: \(userId, privacy: .public)")
            updateStatus(.paired(userId: userId))

        case "relay_token":
            if let token = json["relayToken"] as? String {
                UserDefaults.standard.set(token, forKey: relayTokenKey)
                logger.log("Saved relay token for automatic reconnection")
            }

        case "chat_request":
            guard let requestId = json["requestId"] as? String,
                  let payload = json["payload"] as? [String: Any] else {
                logger.warning("Invalid chat_request: missing requestId or payload")
                return
            }
            // Serialize payload to Data immediately to avoid Sendable issues
            guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
                logger.warning("Failed to serialize chat_request payload")
                return
            }
            Task { [weak self] in
                guard let self else { return }
                await self.handleChatRequest(requestId: requestId, payloadData: payloadData)
            }

        case "pong":
            break

        case "error":
            let msg = json["message"] as? String ?? "Unknown relay error"
            logger.error("Relay error: \(msg, privacy: .public)")
            AppLog.error("Relay error: \(msg)", source: "relay")
            // If the relay token was rejected, clear it so next reconnect uses pairing code
            if msg.contains("relay token") {
                UserDefaults.standard.removeObject(forKey: relayTokenKey)
                logger.log("Cleared invalid relay token")
                AppLog.warning("Cleared invalid relay token after auth failure", source: "relay")
            }
            updateStatus(.error(msg))

        default:
            logger.log("Unhandled relay message type: \(type, privacy: .public)")
        }
    }

    // MARK: - Auth

    private func sendAuth() async {
        // Try relay token first for automatic reconnection
        if let relayToken = UserDefaults.standard.string(forKey: relayTokenKey), !relayToken.isEmpty {
            let authMessage: [String: Any] = ["type": "auth", "relayToken": relayToken]
            await sendJSON(authMessage)
            logger.log("Sent auth with relay token")
            return
        }

        // Fall back to pairing code for initial pairing
        let code = await LocalHTTPServer.shared.pairingCode
        guard !code.isEmpty else {
            logger.error("No pairing code available, cannot authenticate")
            AppLog.error("Relay auth failed: no pairing code available", source: "relay")
            updateStatus(.error("No pairing code"))
            return
        }

        let authMessage: [String: Any] = ["type": "auth", "code": code]
        await sendJSON(authMessage)
        logger.log("Sent auth with pairing code")
    }

    // MARK: - Chat Request Handling

    private func handleChatRequest(requestId: String, payloadData: Data) async {
        let port = await LocalHTTPServer.shared.getPort()
        let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Ensure streaming is enabled
        if var payloadJSON = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
            payloadJSON["stream"] = true
            request.httpBody = try? JSONSerialization.data(withJSONObject: payloadJSON)
        } else {
            request.httpBody = payloadData
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                logger.error("Local server returned status \(statusCode, privacy: .public)")
                await sendChatError(requestId: requestId, error: "Local server error (status \(statusCode))")
                return
            }

            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }

                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))

                if jsonString == "[DONE]" {
                    await sendChatChunk(requestId: requestId, content: "", done: true)
                    break
                }

                guard let chunkData = jsonString.data(using: .utf8),
                      let chunkJSON = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any],
                      let choices = chunkJSON["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let delta = firstChoice["delta"] as? [String: Any] else {
                    continue
                }

                if let content = delta["content"] as? String, !content.isEmpty {
                    await sendChatChunk(requestId: requestId, content: content, done: false)
                }

                if let finishReason = firstChoice["finish_reason"] as? String, finishReason == "stop" {
                    await sendChatChunk(requestId: requestId, content: "", done: true)
                    break
                }
            }
        } catch {
            logger.error("Error streaming from local server: \(String(describing: error), privacy: .public)")
            await sendChatError(requestId: requestId, error: "Streaming error: \(error.localizedDescription)")
        }
    }

    // MARK: - Send Messages

    private func sendChatChunk(requestId: String, content: String, done: Bool) async {
        var message: [String: Any] = [
            "type": "chat_chunk",
            "requestId": requestId,
            "content": content
        ]
        if done {
            message["done"] = true
        }
        await sendJSON(message)
    }

    private func sendChatError(requestId: String, error: String) async {
        let message: [String: Any] = [
            "type": "chat_error",
            "requestId": requestId,
            "error": error
        ]
        await sendJSON(message)
    }

    private func sendJSON(_ json: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        do {
            try await webSocketTask?.send(.string(text))
        } catch {
            logger.error("Failed to send WebSocket message: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Ping

    private func startPingTimer() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.sendJSON(["type": "ping"])
            }
        }
    }

    // MARK: - Status

    private func updateStatus(_ newStatus: RelayStatus) {
        status = newStatus
        let callback = onStatusChange
        Task { @MainActor in
            callback?(newStatus)
        }
    }
}
