//
//  ServerDashboardView.swift
//  Perspective Server
//
//  Main dashboard UI for server management
//

import SwiftUI

struct ServerDashboardView: View {
    @EnvironmentObject private var serverController: ServerController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var localPort: String = "11434"
    @State private var showCopiedToast: Bool = false
    @State private var copiedText: String = ""
    @State private var testResult: String = ""
    @State private var isTesting: Bool = false
    @State private var logMessages: [LogMessage] = []
    @State private var autoStart: Bool = true
    @State private var metrics: MetricsSnapshot = MetricsSnapshot(
        totalRequests: 0, totalInferenceRequests: 0,
        totalTokens: 0, requestsLast5Min: 0,
        averageTTFT: nil, lastTTFT: nil
    )
    @State private var metricsTimer: Timer? = nil
    
    // Native system colors
    private let successColor = Color.green
    private let errorColor = Color.red
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection
                    
                    // Main Status Card
                    mainStatusCard

                    // Server Stats Card
                    if serverController.isRunning {
                        serverStatsCard
                    }

                    // Remote Access Card
                    remoteAccessCard

                    // Server Controls Card
                    serverControlsCard
                    
                    // Xcode Integration Card
                    xcodeIntegrationCard
                    
                    // API Endpoints Card
                    endpointsCard
                    
                    // Quick Actions Card
                    actionsCard
                    
                    // Connection Test Card
                    testConnectionCard
                    
                    Spacer(minLength: 20)
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            // Toast overlay
            if showCopiedToast {
                VStack {
                    Spacer()
                    toastView
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 550, minHeight: 700)
        .onAppear {
            syncServerState()
            refreshMetrics()
            metricsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in
                    await refreshMetrics()
                }
            }
        }
        .onDisappear {
            metricsTimer?.invalidate()
            metricsTimer = nil
        }
        .animation(.easeInOut(duration: 0.25), value: showCopiedToast)
    }
    
    // MARK: - Toast View
    
    private var toastView: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(successColor)
                .accessibilityHidden(true)
            Text(copiedText)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(25)
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        .accessibilityLabel(copiedText)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Perspective Server")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Local AI Server powered by Apple Intelligence")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                openWindow(id: "chat")
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .accessibilityHidden(true)
                    Text("Chat")
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Open chat window")
        }
    }
    
    // MARK: - Main Status Card
    
    private var serverStatusText: String {
        if serverController.isRunning {
            return "Server Running"
        } else if serverController.errorMessage != nil {
            return "Server Error"
        } else {
            return "Server Stopped"
        }
    }
    
    private var statusIndicatorColor: Color {
        if serverController.isRunning {
            return successColor
        } else if serverController.errorMessage != nil {
            return .orange
        } else {
            return errorColor
        }
    }
    
    private var mainStatusCard: some View {
        HStack(spacing: 0) {
            // Left side - Status
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(statusIndicatorColor.opacity(0.2))
                            .frame(width: 44, height: 44)
                        
                        Circle()
                            .fill(statusIndicatorColor)
                            .frame(width: 18, height: 18)
                            .shadow(color: statusIndicatorColor.opacity(0.6), radius: 8)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(serverStatusText)
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.primary)
                        
                        if serverController.isRunning {
                            Text(verbatim: "Listening on port \(serverController.port)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if let error = serverController.errorMessage {
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(errorColor)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Click Start to begin")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if serverController.isRunning {
                    HStack(spacing: 8) {
                        Label {
                            Text(verbatim: "http://127.0.0.1:\(serverController.port)")
                        } icon: {
                            Image(systemName: "link")
                        }
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.accentColor)
                        
                        Button(action: {
                            copyToClipboard(
                                endpointDetails(path: "", includeOpenAIBaseURL: false),
                                message: "Base URL details copied"
                            )
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(copiedAccessibilityLabel(defaultLabel: "Copy base URL", copiedLabel: "Base URL copied", copiedMessage: "Base URL details copied"))
                        .accessibilityValue(copiedAccessibilityValue(copiedMessage: "Base URL details copied"))
                        .accessibilityHint("Copies the base URL details to the clipboard")
                    }

                    // Web pairing details
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Perspective Intelligence Web")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)

                        HStack(spacing: 8) {
                            Label("Pairing Code: \(serverController.pairingCode)", systemImage: "link.badge.plus")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.orange)

                            Button(action: {
                                copyToClipboard(serverController.pairingCode, message: "Pairing code copied")
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(copiedAccessibilityLabel(defaultLabel: "Copy pairing code", copiedLabel: "Pairing code copied", copiedMessage: "Pairing code copied"))
                            .accessibilityValue(copiedAccessibilityValue(copiedMessage: "Pairing code copied"))
                            .accessibilityHint("Copies the 6-digit pairing code for connecting from the web app")
                        }
                        Text("Use this code to connect from Perspective Intelligence Web. Go to Settings in the web app, choose Pairing Code, and enter these 6 digits. Your conversations stay on this Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer()

            // Right side - Big action button
            Button(action: {
                if serverController.isRunning {
                    serverController.stop()
                    addLog("Server stopped", type: .info)
                } else {
                    if let portNum = UInt16(localPort) {
                        serverController.port = portNum
                    }
                    serverController.start()
                    addLog("Server started on port \(serverController.port)", type: .success)
                }
            }) {
                VStack(spacing: 8) {
                    Image(systemName: serverController.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    Text(serverController.isRunning ? "Stop Server" : "Start Server")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(width: 120, height: 120)
                .background(serverController.isRunning ? errorColor : successColor)
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .focusable()
            .accessibilityLabel(serverController.isRunning ? "Stop server" : "Start server")
            .accessibilityHint(serverController.isRunning ? "Double tap to stop the server" : "Double tap to start the server")
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(serverController.isRunning ? successColor.opacity(0.3) : Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
    
    // MARK: - Remote Access Card

    private var remoteAccessCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Remote Access", systemImage: "network")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            Divider()

            Toggle(isOn: Binding(
                get: { serverController.relayEnabled },
                set: { serverController.setRelayEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable remote access")
                        .font(.subheadline.weight(.medium))
                    Text("Let Perspective Intelligence Web connect to this server so you can chat from any browser, anywhere. Your Mac does the AI processing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!serverController.isRunning)
            .accessibilityLabel("Enable remote access")
            .accessibilityHint(serverController.isRunning
                ? "Connects this server to Perspective Intelligence Web for remote browser access"
                : "Start the server first to enable remote access")
            .accessibilityValue(serverController.relayEnabled ? "Enabled" : "Disabled")

            if serverController.relayEnabled {
                HStack(spacing: 14) {
                    Circle()
                        .fill(relayIndicatorColor)
                        .frame(width: 12, height: 12)
                        .shadow(color: relayIndicatorColor.opacity(0.6), radius: 4)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(relayStatusText)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        Text(relayStatusDetail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Relay status: \(relayStatusText). \(relayStatusDetail)")
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private var relayIndicatorColor: Color {
        switch serverController.relayStatus {
        case .paired: return successColor
        case .waitingForPairing: return .orange
        case .connecting, .waitingForAuth: return .yellow
        case .error: return errorColor
        case .disconnected: return .gray
        }
    }

    private var relayStatusText: String {
        serverController.relayStatus.displayText
    }

    private var relayStatusDetail: String {
        switch serverController.relayStatus {
        case .disconnected:
            return "Not connected to the cloud relay."
        case .connecting, .waitingForAuth:
            return "Connecting to Perspective Intelligence Web..."
        case .waitingForPairing:
            return "Ready. Go to Perspective Intelligence Web, open Settings, choose Pairing Code, and enter: \(serverController.pairingCode)"
        case .paired:
            return "A browser is connected and chatting through this Mac. Everything's running locally."
        case .error(let msg):
            return msg
        }
    }

    // MARK: - Server Controls Card

    private var serverControlsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Server Configuration", systemImage: "gearshape.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Divider()
            
            // Port Configuration
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Port Number")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 0) {
                        TextField("Port", text: $localPort)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(width: 80)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(NSColor.textBackgroundColor))
                            .accessibilityLabel("Port number")
                            .accessibilityValue(localPort)
                        
                        // Stepper buttons
                        VStack(spacing: 0) {
                            Button(action: {
                                if let port = UInt16(localPort), port < 65535 {
                                    localPort = String(port + 1)
                                }
                            }) {
                                Image(systemName: "chevron.up")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, height: 20)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Increase port")
                            
                            Divider()
                            
                            Button(action: {
                                if let port = UInt16(localPort), port > 1 {
                                    localPort = String(port - 1)
                                }
                            }) {
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, height: 20)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Decrease port")
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        portPresetButton("11434", label: "Default")
                        portPresetButton("11435", label: "Alt 1")
                        portPresetButton("8080", label: "Alt 2")
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Actions")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Button(action: {
                            if let portNum = UInt16(localPort) {
                                serverController.port = portNum
                                if serverController.isRunning {
                                    serverController.restart()
                                    addLog("Server restarted on port \(portNum)", type: .info)
                                } else {
                                    serverController.start()
                                    addLog("Server started on port \(portNum)", type: .success)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: serverController.isRunning ? "arrow.clockwise" : "play.fill")
                                    .accessibilityHidden(true)
                                Text(serverController.isRunning ? "Restart" : "Start")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(serverController.isRunning ? "Restart server with new port" : "Start server")
                    }
                }
            }
            
            // Model info
            HStack(spacing: 12) {
                Image(systemName: "cube.fill")
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model: apple.local:latest")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("Apple Intelligence on-device model")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
    
    private func portPresetButton(_ port: String, label: String) -> some View {
        Button(action: {
            localPort = port
        }) {
            VStack(spacing: 2) {
                Text(port)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundColor(localPort == port ? .white : .secondary)
            .frame(width: 60, height: 44)
            .background(localPort == port ? Color.accentColor : Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(localPort == port ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), port \(port)")
        .accessibilityAddTraits(localPort == port ? .isSelected : [])
    }
    
    // MARK: - Xcode Integration Card
    
    private var xcodeIntegrationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Xcode 26 Integration", systemImage: "hammer.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("To use with Xcode 26 Intelligence Mode:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                instructionRow(number: 1, text: "Open Xcode > Settings > Intelligence")
                instructionRow(number: 2, text: "Click Add a Model Provider > Locally Hosted")
                instructionRow(number: 3, text: "Enter port: \(localPort)")
                instructionRow(number: 4, text: "Select apple.local:latest from the model list")
                
                HStack(spacing: 12) {
                    infoBox(title: "Port", value: localPort, icon: "network")
                    infoBox(title: "Model", value: "apple.local:latest", icon: "cube")
                    infoBox(title: "Protocol", value: "Ollama API", icon: "arrow.left.arrow.right")
                }
                .padding(.top, 8)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
    
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
    
    private func infoBox(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
    
    // MARK: - Endpoints Card
    
    private var endpointsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("API Endpoints", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                
                Button(action: {
                    copyToClipboard(
                        endpointDetails(path: "/v1", includeOpenAIBaseURL: true),
                        message: "OpenAI setup details copied"
                    )
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .accessibilityHidden(true)
                        Text("Copy URL")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copiedAccessibilityLabel(defaultLabel: "Copy OpenAI base URL", copiedLabel: "OpenAI base URL copied", copiedMessage: "OpenAI setup details copied"))
                .accessibilityValue(copiedAccessibilityValue(copiedMessage: "OpenAI setup details copied"))
                .accessibilityHint("Copies the OpenAI base URL details to the clipboard")
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                endpointRow(method: "GET", path: "/api/tags", description: "List models (Xcode/Ollama)")
                endpointRow(method: "POST", path: "/api/chat", description: "Chat (Ollama format)")
                endpointRow(method: "GET", path: "/v1/models", description: "List models (OpenAI)")
                endpointRow(method: "POST", path: "/v1/chat/completions", description: "Chat (OpenAI)")
                endpointRow(method: "POST", path: "/v1/completions", description: "Completions")
                endpointRow(method: "GET", path: "/debug/health", description: "Health check")
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
    
    private func endpointRow(method: String, path: String, description: String) -> some View {
        HStack(spacing: 12) {
            Text(method)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(method == "GET" ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                .cornerRadius(4)
                .frame(width: 50)
            
            Text(path)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 170, alignment: .leading)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: {
                copyToClipboard(
                    endpointDetails(path: path),
                    message: "Endpoint details copied"
                )
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copiedAccessibilityLabel(defaultLabel: "Copy endpoint URL", copiedLabel: "Endpoint copied", copiedMessage: "Endpoint details copied"))
            .accessibilityValue(copiedAccessibilityValue(copiedMessage: "Endpoint details copied"))
            .accessibilityHint("Copies the endpoint details to the clipboard")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(method) \(path), \(description)")
    }
    
    // MARK: - Actions Card
    
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Quick Actions", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Divider()
            
            HStack(spacing: 12) {
                actionButton(
                    title: "Copy cURL",
                    subtitle: "Test command",
                    icon: "terminal",
                    accessibilityLabel: copiedAccessibilityLabel(defaultLabel: "Copy cURL, Test command", copiedLabel: "cURL command copied", copiedMessage: "cURL command copied"),
                    accessibilityValue: copiedAccessibilityValue(copiedMessage: "cURL command copied"),
                    action: {
                        let cmd = "curl http://127.0.0.1:\(serverController.port)/api/tags"
                        copyToClipboard(cmd, message: "cURL command copied")
                    }
                )
                
                actionButton(
                    title: "Settings",
                    subtitle: "Preferences",
                    icon: "gearshape",
                    action: {
                        if #available(macOS 14.0, *) {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        } else {
                            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                        }
                    }
                )
                
                actionButton(
                    title: "Chat",
                    subtitle: "Test AI",
                    icon: "bubble.left.and.bubble.right",
                    action: {
                        openWindow(id: "chat")
                    }
                )
                
                actionButton(
                    title: "Docs",
                    subtitle: "README",
                    icon: "book",
                    action: {
                        if let url = URL(string: "https://github.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
    
    private func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? "\(title), \(subtitle)")
        .accessibilityValue(accessibilityValue ?? "")
    }
    
    // MARK: - Test Connection Card
    
    private var testConnectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Connection Test", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Divider()
            
            HStack(spacing: 16) {
                Button(action: testConnection) {
                    HStack(spacing: 10) {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "play.fill")
                                .accessibilityHidden(true)
                        }
                        Text(isTesting ? "Testing..." : "Run Test")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTesting || !serverController.isRunning)
                .accessibilityLabel(isTesting ? "Testing connection" : "Run connection test")
                
                if !serverController.isRunning {
                    Text("Start the server to test")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if !testResult.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: testResult.contains("Success") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(testResult.contains("Success") ? successColor : .orange)
                        .accessibilityHidden(true)
                    
                    Text(testResult)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(testResult.contains("Success") ? successColor : .orange)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(10)
                .accessibilityLabel("Test result: \(testResult)")
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
    
    // MARK: - Server Stats Card

    private var serverStatsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Server Stats", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()

                Text("Updates every 2s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 12) {
                statBox(
                    title: "Requests",
                    value: "\(metrics.totalRequests)",
                    subtitle: "\(metrics.requestsLast5Min) in last 5 min",
                    icon: "arrow.up.arrow.down"
                )

                statBox(
                    title: "Tokens",
                    value: formatNumber(metrics.totalTokens),
                    subtitle: "generated",
                    icon: "textformat.abc"
                )

                statBox(
                    title: "Avg TTFT",
                    value: formatTTFT(metrics.averageTTFT),
                    subtitle: "time to first token",
                    icon: "clock"
                )

                statBox(
                    title: "Last TTFT",
                    value: formatTTFT(metrics.lastTTFT),
                    subtitle: "most recent",
                    icon: "clock.arrow.circlepath"
                )
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Server statistics")
    }

    private func statBox(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value), \(subtitle)")
    }

    private func formatTTFT(_ value: Double?) -> String {
        guard let v = value, v >= 0 else { return "--" }
        if v < 1 {
            return String(format: "%.0fms", v * 1000)
        } else {
            return String(format: "%.1fs", v)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }

    @MainActor
    private func refreshMetrics() {
        Task {
            let snap = await ServerMetrics.shared.snapshot
            metrics = snap
        }
    }

    // MARK: - Helper Methods

    private func syncServerState() {
        Task {
            let running = await LocalHTTPServer.shared.getIsRunning()
            let port = await LocalHTTPServer.shared.getPort()
            await MainActor.run {
                serverController.isRunning = running
                serverController.port = port
                localPort = String(port)
            }
        }
    }
    
    private func copyToClipboard(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedText = message
        showCopiedToast = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedToast = false
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = ""
        
        Task {
            let url = URL(string: "http://127.0.0.1:\(serverController.port)/api/tags")!
            do {
                let request = URLRequest(url: url)
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let models = json["models"] as? [[String: Any]] {
                            let modelNames = models.compactMap { $0["name"] as? String }
                            await MainActor.run {
                                if modelNames.isEmpty {
                                    testResult = "Success! Server responded. No models listed."
                                } else {
                                    testResult = "Success! Models found:\n• " + modelNames.joined(separator: "\n• ")
                                }
                                isTesting = false
                                addLog("Connection test passed", type: .success)
                            }
                        } else {
                            await MainActor.run {
                                testResult = "Success! Server responded (status 200)"
                                isTesting = false
                            }
                        }
                    } else {
                        await MainActor.run {
                            testResult = "Server returned status \(httpResponse.statusCode)"
                            isTesting = false
                            addLog("Connection test failed: status \(httpResponse.statusCode)", type: .error)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = "Connection failed:\n\(error.localizedDescription)"
                    isTesting = false
                    addLog("Connection test failed: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }

    // Bearer token removed — security is handled by loopback binding + CORS + Host validation

    private func isCopied(_ copiedMessage: String) -> Bool {
        showCopiedToast && copiedText == copiedMessage
    }

    private func copiedAccessibilityLabel(defaultLabel: String, copiedLabel: String, copiedMessage: String) -> String {
        isCopied(copiedMessage) ? copiedLabel : defaultLabel
    }

    private func copiedAccessibilityValue(copiedMessage: String) -> String {
        isCopied(copiedMessage) ? "Copied to clipboard" : ""
    }

    private func endpointDetails(path: String, includeOpenAIBaseURL: Bool = false) -> String {
        let baseURL = "http://127.0.0.1:\(serverController.port)"
        let fullURL = "\(baseURL)\(path)"

        var lines = ["URL: \(fullURL)"]
        if includeOpenAIBaseURL {
            lines.append("OpenAI Base URL: \(fullURL)")
        }

        return lines.joined(separator: "\n")
    }
    
    private func addLog(_ message: String, type: LogType) {
        let log = LogMessage(message: message, type: type, timestamp: Date())
        logMessages.insert(log, at: 0)
        if logMessages.count > 50 {
            logMessages.removeLast()
        }
    }
}

// MARK: - Supporting Types

struct LogMessage: Identifiable {
    let id = UUID()
    let message: String
    let type: LogType
    let timestamp: Date
}

enum LogType {
    case info, success, error
}

#Preview {
    ServerDashboardView()
        .environmentObject(ServerController())
}
