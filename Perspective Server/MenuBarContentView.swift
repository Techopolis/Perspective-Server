//
//  MenuBarContentView.swift
//  Perspective Server
//
//  Created by GitHub Copilot on 9/14/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var serverController: ServerController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ServerStatusView()
                .environmentObject(serverController)
            Divider()
            Button("Open Dashboard") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "dashboard")
            }
            Button("Open Chat Window") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "chat")
            }
            Divider()
            Button("Check for Updates...") {
                NSApp.sendAction(#selector(AppDelegate.checkForUpdates), to: nil, from: nil)
            }
            Divider()
            Button("Quit Perspective Server") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
        .id(serverController.isRunning)
    }
}

#Preview {
    MenuBarContentView()
        .environmentObject(ServerController())
}
