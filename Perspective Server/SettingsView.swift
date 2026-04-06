//
//  SettingsView.swift
//  Perspective Server
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

    @State private var clients: [ApprovedClient] = []
    @State private var newClientName: String = ""
    @State private var newClientOrigins: String = "localhost"

    var body: some View {
        Group {
            if embeddedInDashboard {
                dashboardEmbeddedContent
            } else {
                formContent
                    .padding()
                    .frame(minWidth: 560, minHeight: 420)
            }
        }
        .task {
            await loadClients()
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

            Section(header: Text("API Access Control")) {
                Text("Approved applications must use a bearer token and can only call from allowed origins.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if clients.isEmpty {
                    Text("No approved clients configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(clients) { client in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(client.name)
                                    .font(.subheadline.weight(.semibold))
                                if client.isSystemClient {
                                    Text("System")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(6)
                                }
                                Spacer()
                                Toggle("Enabled", isOn: Binding(
                                    get: { client.isEnabled },
                                    set: { enabled in
                                        Task {
                                            await AccessControlManager.shared.setClientEnabled(id: client.id, enabled: enabled)
                                            await loadClients()
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }

                            Text("Origins: \(client.allowedOriginHosts.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Text("Token: \(client.token)")
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)

                            HStack(spacing: 10) {
                                Button("Copy Token") {
                                    copyText(client.token)
                                }
                                .buttonStyle(.bordered)

                                Button("Rotate Token") {
                                    Task {
                                        _ = await AccessControlManager.shared.rotateToken(id: client.id)
                                        await loadClients()
                                    }
                                }
                                .buttonStyle(.bordered)

                                if !client.isSystemClient {
                                    Button("Delete") {
                                        Task {
                                            await AccessControlManager.shared.deleteClient(id: client.id)
                                            await loadClients()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Approved Client")
                        .font(.subheadline.weight(.semibold))

                    TextField("Client name", text: $newClientName)
                    TextField("Allowed origins (comma-separated hosts)", text: $newClientOrigins)

                    Button("Create Token") {
                        Task {
                            let name = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            let origins = newClientOrigins
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            _ = await AccessControlManager.shared.createClient(name: name, allowedOriginHosts: origins)
                            newClientName = ""
                            await loadClients()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newClientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
                            .font(.body)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
                        HStack {
                            Spacer()
                            Button("Reset to Default") {
                                systemPrompt = "You are a helpful assistant. Keep responses concise and relevant."
                                includeSystemPrompt = true
                            }
                            .buttonStyle(.bordered)
                        }
                        Text("The system prompt (if enabled) is sent with each chat to guide assistant behavior.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                card(title: "API Access Control", systemImage: "lock.shield") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Approved applications must use a bearer token and can only call from allowed origins.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if clients.isEmpty {
                            Text("No approved clients configured.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(clients) { client in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(client.name)
                                            .font(.subheadline.weight(.semibold))
                                        if client.isSystemClient {
                                            Text("System")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.15))
                                                .cornerRadius(6)
                                        }
                                        Spacer()
                                        Toggle("Enabled", isOn: Binding(
                                            get: { client.isEnabled },
                                            set: { enabled in
                                                Task {
                                                    await AccessControlManager.shared.setClientEnabled(id: client.id, enabled: enabled)
                                                    await loadClients()
                                                }
                                            }
                                        ))
                                        .labelsHidden()
                                    }

                                    Text("Origins: \(client.allowedOriginHosts.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                    Text("Token: \(client.token)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)

                                    HStack(spacing: 10) {
                                        Button("Copy Token") {
                                            copyText(client.token)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Rotate Token") {
                                            Task {
                                                _ = await AccessControlManager.shared.rotateToken(id: client.id)
                                                await loadClients()
                                            }
                                        }
                                        .buttonStyle(.bordered)

                                        if !client.isSystemClient {
                                            Button("Delete") {
                                                Task {
                                                    await AccessControlManager.shared.deleteClient(id: client.id)
                                                    await loadClients()
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                )
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add Approved Client")
                                .font(.subheadline.weight(.semibold))
                            TextField("Client name", text: $newClientName)
                            TextField("Allowed origins (comma-separated hosts)", text: $newClientOrigins)
                            Button("Create Token") {
                                Task {
                                    let name = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !name.isEmpty else { return }
                                    let origins = newClientOrigins
                                        .split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                    _ = await AccessControlManager.shared.createClient(name: name, allowedOriginHosts: origins)
                                    newClientName = ""
                                    await loadClients()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newClientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
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

    @MainActor
    private func loadClients() async {
        clients = await AccessControlManager.shared.listClients()
    }

    private func copyText(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

#Preview {
    SettingsView()
}
