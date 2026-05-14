//
//  SettingsView.swift
//  afm-server
//
//  Created by GitHub Copilot on 9/14/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    let embeddedInDashboard: Bool

    init(embeddedInDashboard: Bool = false) {
        self.embeddedInDashboard = embeddedInDashboard
    }

    @AppStorage("systemPrompt") private var systemPrompt: String = "You are a helpful assistant. Keep responses concise and relevant."
    @AppStorage("includeSystemPrompt") private var includeSystemPrompt: Bool = false
    @AppStorage("debugLogging") private var debugLogging: Bool = false
    @AppStorage("includeHistory") private var includeHistory: Bool = true
    @AppStorage("enableBetaUpdates") private var enableBetaUpdates: Bool = false
    @State private var currentBearerToken: String = ""
    @State private var customBearerToken: String = ""
    @State private var tokenStatusMessage: String = ""
    @State private var tokenStatusIsError: Bool = false
    @State private var isSavingToken: Bool = false

    var body: some View {
        Group {
            if embeddedInDashboard {
                dashboardEmbeddedContent
            } else {
                formContent
                    .padding()
                    .frame(minWidth: 460, minHeight: 440)
            }
        }
    }

    private var formContent: some View {
        Form {
            Toggle("Include System Prompt", isOn: $includeSystemPrompt)
                .accessibilityLabel("Include system prompt")
                .accessibilityHint("Turn off to send chats without the system instruction")
            Toggle("Enable Debug Logging", isOn: $debugLogging)
                .accessibilityLabel("Enable debug logging")
                .accessibilityHint("Print requests and responses to the console for troubleshooting")
            Toggle("Include Conversation History", isOn: $includeHistory)
                .accessibilityLabel("Include conversation history")
                .accessibilityHint("Turn off to send only the latest user message")
            Toggle("Receive Beta Updates", isOn: $enableBetaUpdates)
                .accessibilityLabel("Receive beta updates")
                .accessibilityHint("Get early access to new features before stable release")

            Section(header: Text("System Prompt")) {
                TextEditor(text: $systemPrompt)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    .accessibilityLabel("System prompt")
                    .accessibilityHint("Text used as the assistant's system instruction")
                HStack {
                    Spacer()
                    Button("Reset to Default") {
                        systemPrompt = "You are a helpful assistant. Keep responses concise and relevant."
                        includeSystemPrompt = true
                    }
                }
            }

            Section(header: Text("API Bearer Token")) {
                apiBearerTokenControls
            }

            Text("The system prompt (if enabled) is sent with each chat to guide the assistant's behavior.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var dashboardEmbeddedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                card(title: "General", systemImage: "switch.2") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Include System Prompt", isOn: $includeSystemPrompt)
                        Toggle("Enable Debug Logging", isOn: $debugLogging)
                        Toggle("Include Conversation History", isOn: $includeHistory)
                        Toggle("Receive Beta Updates", isOn: $enableBetaUpdates)
                    }
                }

                card(title: "System Prompt", systemImage: "text.quote") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $systemPrompt)
                            .frame(minHeight: 120)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                            .accessibilityLabel("System prompt")
                        HStack {
                            Spacer()
                            Button("Reset to Default") {
                                systemPrompt = "You are a helpful assistant. Keep responses concise and relevant."
                                includeSystemPrompt = true
                            }
                        }
                        Text("The system prompt (if enabled) is sent with each chat to guide the assistant's behavior.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                card(title: "API Bearer Token", systemImage: "key.horizontal") {
                    apiBearerTokenControls
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var apiBearerTokenControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Requests to local API endpoints must include this token in the Authorization header.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Current token")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(currentBearerToken.isEmpty ? "No token saved yet." : currentBearerToken)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(currentBearerToken.isEmpty ? .secondary : .primary)
            }

            SecureField("Custom bearer token", text: $customBearerToken)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Custom bearer token")
                .accessibilityHint("Enter a bearer token with more than 4 characters")

            Text("Use any token more than 4 characters. Leading and trailing spaces are ignored.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Save Token") {
                    saveCustomBearerToken()
                }
                .disabled(isSavingToken || LocalHTTPServer.authTokenValidationMessage(for: customBearerToken) != nil)

                Button("Generate Token") {
                    rotateBearerToken()
                }
                .disabled(isSavingToken)

                Button("Copy Token") {
                    copyBearerToken()
                }
                .disabled(currentBearerToken.isEmpty)
            }

            if !tokenStatusMessage.isEmpty {
                Text(tokenStatusMessage)
                    .font(.caption)
                    .foregroundStyle(tokenStatusIsError ? .red : .green)
            }
        }
        .task {
            await loadBearerToken()
        }
    }

    private func card<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Divider()
            content()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private func saveCustomBearerToken() {
        let token = LocalHTTPServer.normalizedAuthToken(customBearerToken)
        if let validationMessage = LocalHTTPServer.authTokenValidationMessage(for: token) {
            tokenStatusMessage = validationMessage
            tokenStatusIsError = true
            return
        }

        isSavingToken = true
        Task {
            do {
                try await LocalHTTPServer.shared.setAuthToken(token)
                await MainActor.run {
                    currentBearerToken = token
                    customBearerToken = ""
                    tokenStatusMessage = "Bearer token saved."
                    tokenStatusIsError = false
                    isSavingToken = false
                }
            } catch {
                await MainActor.run {
                    tokenStatusMessage = error.localizedDescription
                    tokenStatusIsError = true
                    isSavingToken = false
                }
            }
        }
    }

    private func rotateBearerToken() {
        isSavingToken = true
        Task {
            do {
                let token = try await LocalHTTPServer.shared.rotateAuthToken()
                await MainActor.run {
                    currentBearerToken = token
                    customBearerToken = ""
                    tokenStatusMessage = "Generated a new bearer token."
                    tokenStatusIsError = false
                    isSavingToken = false
                }
            } catch {
                await MainActor.run {
                    tokenStatusMessage = error.localizedDescription
                    tokenStatusIsError = true
                    isSavingToken = false
                }
            }
        }
    }

    @MainActor
    private func loadBearerToken() async {
        currentBearerToken = await LocalHTTPServer.shared.getAuthToken() ?? ""
    }

    private func copyBearerToken() {
        guard !currentBearerToken.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentBearerToken, forType: .string)
        tokenStatusMessage = "Bearer token copied."
        tokenStatusIsError = false
        #endif
    }
}

#Preview {
    SettingsView()
}
