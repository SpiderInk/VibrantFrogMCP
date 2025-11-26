//
//  MCPTestView.swift
//  VibrantFrog
//
//  MCP Connection Test View
//

import SwiftUI

struct MCPTestView: View {
    @EnvironmentObject var mcpClient: MCPClientHTTP
    @State private var testOutput: String = "Ready to test MCP connection\nWill launch Python server via HTTP/SSE on port 5050"
    @State private var isTesting: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // Connection Status
            GroupBox("MCP Server Status") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Circle()
                            .fill(mcpClient.isConnected ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        Text(mcpClient.isConnected ? "Connected" : "Disconnected")
                            .fontWeight(.medium)
                        Spacer()
                    }

                    if mcpClient.isConnected {
                        Text("Server: \(mcpClient.serverInfo)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Available Tools: \(mcpClient.availableTools.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = mcpClient.errorMessage {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 8)
            }

            // Tools List
            if !mcpClient.availableTools.isEmpty {
                GroupBox("Available Tools") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(mcpClient.availableTools) { tool in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tool.name)
                                        .font(.headline)
                                    Text(tool.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 200)
                }
            }

            // Test Output
            GroupBox("Test Output") {
                ScrollView {
                    Text(testOutput)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 200)
                .padding(8)
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 16) {
                Button {
                    testConnection()
                } label: {
                    Label("Connect to MCP Server", systemImage: "network")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(mcpClient.isConnected || isTesting)

                Button {
                    disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!mcpClient.isConnected || isTesting)

                Button {
                    testSearchTool()
                } label: {
                    Label("Test Search", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!mcpClient.isConnected || isTesting)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Actions

    private func testConnection() {
        isTesting = true
        testOutput = "Connecting to Python MCP server...\n"

        Task {
            do {
                try await mcpClient.connect()

                await MainActor.run {
                    testOutput += "✅ Connected successfully!\n"
                    testOutput += "Server: \(mcpClient.serverInfo)\n"
                    testOutput += "Tools loaded: \(mcpClient.availableTools.count)\n\n"

                    testOutput += "Available tools:\n"
                    for tool in mcpClient.availableTools {
                        testOutput += "  - \(tool.name): \(tool.description)\n"
                    }

                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testOutput += "❌ Connection failed: \(error.localizedDescription)\n"
                    isTesting = false
                }
            }
        }
    }

    private func disconnect() {
        mcpClient.disconnect()
        testOutput += "\nDisconnected from MCP server.\n"
    }

    private func testSearchTool() {
        isTesting = true
        testOutput += "\nTesting search_photos tool...\n"

        Task {
            do {
                let result = try await mcpClient.callTool(
                    name: "search_photos",
                    arguments: ["query": "sunset", "limit": 5]
                )

                await MainActor.run {
                    testOutput += "✅ Tool executed successfully!\n"
                    testOutput += "\nResults:\n"
                    for content in result.content {
                        if let text = content.text {
                            testOutput += text + "\n"
                        }
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testOutput += "❌ Tool execution failed: \(error.localizedDescription)\n"
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    MCPTestView()
        .environmentObject(MCPClientHTTP())
        .frame(width: 600, height: 600)
}
