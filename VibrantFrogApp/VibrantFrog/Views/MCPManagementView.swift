//
//  MCPManagementView.swift
//  VibrantFrog
//
//  Comprehensive MCP server management UI
//

import SwiftUI

struct MCPManagementView: View {
    @StateObject private var registry = MCPServerRegistry()
    @State private var selectedServer: MCPServer?
    @State private var showingAddServer = false
    @State private var tools: [RegistryMCPTool] = []
    @State private var isLoadingTools = false

    var body: some View {
        HSplitView {
            // Left sidebar: Server list
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("MCP Servers")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingAddServer = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                // Server list
                List(selection: $selectedServer) {
                    ForEach(registry.servers) { server in
                        ServerRow(server: server, registry: registry)
                            .tag(server)
                            .contextMenu {
                                if !server.isBuiltIn {
                                    Button(role: .destructive, action: {
                                        registry.removeServer(server)
                                        if selectedServer?.id == server.id {
                                            selectedServer = nil
                                        }
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200, maxWidth: 300)

            // Right panel: Server details
            if let server = selectedServer {
                ServerDetailView(
                    server: Binding(
                        get: { server },
                        set: { newServer in
                            registry.updateServer(newServer)
                            selectedServer = newServer
                        }
                    ),
                    registry: registry
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "network")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a server to view details")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .sheet(isPresented: $showingAddServer) {
            AddServerSheet(registry: registry)
        }
        .onAppear {
            if let first = registry.servers.first {
                selectedServer = first
            }
        }
    }
}

struct ServerRow: View {
    let server: MCPServer
    @ObservedObject var registry: MCPServerRegistry

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.body)
                Text(server.url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { server.isEnabled },
                set: { _ in registry.toggleServer(server) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch server.connectionStatus {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        case .unknown: return .orange
        }
    }
}

struct ServerDetailView: View {
    @Binding var server: MCPServer
    @ObservedObject var registry: MCPServerRegistry
    @State private var tools: [RegistryMCPTool] = []
    @State private var isLoadingTools = false
    @State private var editingPrompt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Server info section
                GroupBox("Server Information") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Name") {
                            TextField("Server name", text: $server.name)
                                .textFieldStyle(.roundedBorder)
                                .disabled(server.isBuiltIn)
                        }

                        LabeledContent("URL") {
                            TextField("Server URL", text: $server.url)
                                .textFieldStyle(.roundedBorder)
                                .disabled(server.isBuiltIn)
                        }

                        LabeledContent("Status") {
                            HStack {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 8, height: 8)
                                Text(statusText)
                                    .font(.caption)

                                Spacer()

                                Button("Test Connection") {
                                    testConnection()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding()
                }

                // Custom prompt section
                GroupBox("Custom System Prompt") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add custom instructions for tools from this server")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if editingPrompt {
                            TextEditor(text: Binding(
                                get: { server.customPrompt ?? "" },
                                set: { server.customPrompt = $0.isEmpty ? nil : $0 }
                            ))
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 100)
                            .border(Color.secondary.opacity(0.2))

                            HStack {
                                Button("Cancel") {
                                    editingPrompt = false
                                }
                                Spacer()
                                Button("Save") {
                                    registry.updateCustomPrompt(serverID: server.id, prompt: server.customPrompt)
                                    editingPrompt = false
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            if let prompt = server.customPrompt, !prompt.isEmpty {
                                Text(prompt)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(4)
                            } else {
                                Text("No custom prompt set")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }

                            Button(server.customPrompt == nil ? "Add Prompt" : "Edit Prompt") {
                                editingPrompt = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }

                // Tools section
                GroupBox("Available Tools") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if isLoadingTools {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }

                            Button("Refresh") {
                                loadTools()
                            }
                            .buttonStyle(.bordered)
                        }

                        if tools.isEmpty && !isLoadingTools {
                            Text("No tools available. Click Refresh to load.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            ForEach(tools) { tool in
                                ToolRow(tool: tool, server: server, registry: registry)
                            }
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
        .onAppear {
            loadTools()
        }
    }

    private var statusColor: Color {
        switch server.connectionStatus {
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        case .unknown: return .orange
        }
    }

    private var statusText: String {
        switch server.connectionStatus {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }

    private func testConnection() {
        isLoadingTools = true
        Task {
            let fetchedTools = await registry.getToolsForServer(server)
            await MainActor.run {
                tools = fetchedTools
                isLoadingTools = false
            }
        }
    }

    private func loadTools() {
        isLoadingTools = true
        Task {
            let fetchedTools = await registry.getToolsForServer(server)
            await MainActor.run {
                tools = fetchedTools
                isLoadingTools = false
            }
        }
    }
}

struct ToolRow: View {
    let tool: RegistryMCPTool
    let server: MCPServer
    @ObservedObject var registry: MCPServerRegistry
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(showDetails ? nil : 1)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { tool.isEnabled },
                    set: { _ in registry.toggleTool(serverID: server.id, toolName: tool.name) }
                ))
                .labelsHidden()

                Button(action: { showDetails.toggle() }) {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showDetails {
                Divider()
                Text("Input Schema:")
                    .font(.caption)
                    .fontWeight(.semibold)

                if let schema = tool.inputSchema as? [String: Any],
                   let properties = schema["properties"] as? [String: Any] {
                    ForEach(Array(properties.keys.sorted()), id: \.self) { key in
                        if let propDict = properties[key] as? [String: Any],
                           let type = propDict["type"] as? String,
                           let desc = propDict["description"] as? String {
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(key): \(type)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .font(.system(.caption, design: .monospaced))
                                    Text(desc)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(tool.isEnabled ? Color.clear : Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
}

struct AddServerSheet: View {
    @ObservedObject var registry: MCPServerRegistry
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var url = "http://127.0.0.1:5050/mcp"

    var body: some View {
        VStack(spacing: 20) {
            Text("Add MCP Server")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Name") {
                    TextField("Server name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("URL") {
                    TextField("http://127.0.0.1:5050/mcp", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    registry.addServer(name: name, url: url)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || url.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

#Preview {
    MCPManagementView()
}
