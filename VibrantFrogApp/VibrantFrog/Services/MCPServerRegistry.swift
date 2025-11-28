//
//  MCPServerRegistry.swift
//  VibrantFrog
//
//  Registry for managing multiple MCP servers
//

import Foundation

/// Manages multiple MCP server connections
@MainActor
class MCPServerRegistry: ObservableObject {
    @Published var servers: [MCPServer] = []
    @Published var activeServer: MCPServer?

    private let defaults = UserDefaults.standard
    private let serversKey = "mcp_servers"

    init() {
        loadServers()
    }

    // MARK: - Persistence

    private func loadServers() {
        guard let data = defaults.data(forKey: serversKey),
              let decoded = try? JSONDecoder().decode([MCPServer].self, from: data) else {
            // Default: Add VibrantFrog MCP server
            servers = [
                MCPServer(
                    id: UUID(),
                    name: "VibrantFrog Photos",
                    url: "http://127.0.0.1:5050",
                    isBuiltIn: true,
                    isEnabled: true
                )
            ]
            saveServers()
            return
        }
        servers = decoded
        activeServer = servers.first { $0.isEnabled }
    }

    private func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            defaults.set(encoded, forKey: serversKey)
        }
    }

    // MARK: - Server Management

    func addServer(name: String, url: String, mcpEndpointPath: String? = nil) {
        let server = MCPServer(
            id: UUID(),
            name: name,
            url: url,
            isBuiltIn: false,
            isEnabled: true,
            mcpEndpointPath: mcpEndpointPath
        )
        servers.append(server)
        saveServers()
    }

    func removeServer(_ server: MCPServer) {
        guard !server.isBuiltIn else { return }
        servers.removeAll { $0.id == server.id }
        saveServers()
    }

    func toggleServer(_ server: MCPServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].isEnabled.toggle()
            if servers[index].isEnabled {
                activeServer = servers[index]
            }
            saveServers()
        }
    }

    func setActiveServer(_ server: MCPServer) {
        activeServer = server
    }

    func updateServer(_ server: MCPServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }

    func toggleTool(serverID: UUID, toolName: String) {
        if let index = servers.firstIndex(where: { $0.id == serverID }) {
            if servers[index].disabledTools.contains(toolName) {
                servers[index].disabledTools.removeAll { $0 == toolName }
            } else {
                servers[index].disabledTools.append(toolName)
            }
            saveServers()
        }
    }

    func updateCustomPrompt(serverID: UUID, prompt: String?) {
        if let index = servers.firstIndex(where: { $0.id == serverID }) {
            servers[index].customPrompt = prompt
            saveServers()
        }
    }

    func updateConnectionStatus(serverID: UUID, status: MCPServer.ConnectionStatus) {
        if let index = servers.firstIndex(where: { $0.id == serverID }) {
            servers[index].connectionStatus = status
        }
    }

    // MARK: - Get All Available Tools

    func getAllTools() async throws -> [RegistryMCPTool] {
        var allTools: [RegistryMCPTool] = []

        for server in servers where server.isEnabled {
            do {
                // Create temporary client for this server with custom endpoint path
                let client = MCPClientHTTP(
                    serverURL: URL(string: server.url)!,
                    mcpEndpointPath: server.mcpEndpointPath
                )
                try await client.connect()

                let toolsList = try await client.getTools()
                let tools = toolsList.compactMap { tool -> RegistryMCPTool? in
                    // Filter out disabled tools
                    guard !server.disabledTools.contains(tool.name) else { return nil }

                    return RegistryMCPTool(
                        serverID: server.id,
                        serverName: server.name,
                        name: tool.name,
                        description: tool.description ?? "",
                        inputSchema: tool.inputSchema,
                        isEnabled: !server.disabledTools.contains(tool.name)
                    )
                }
                allTools.append(contentsOf: tools)

                updateConnectionStatus(serverID: server.id, status: .connected)

            } catch {
                print("Failed to get tools from \(server.name): \(error)")
                updateConnectionStatus(serverID: server.id, status: .error)
            }
        }

        return allTools
    }

    func getToolsForServer(_ server: MCPServer) async -> [RegistryMCPTool] {
        do {
            let client = MCPClientHTTP(
                serverURL: URL(string: server.url)!,
                mcpEndpointPath: server.mcpEndpointPath
            )
            try await client.connect()

            let toolsList = try await client.getTools()
            return toolsList.map { tool in
                RegistryMCPTool(
                    serverID: server.id,
                    serverName: server.name,
                    name: tool.name,
                    description: tool.description ?? "",
                    inputSchema: tool.inputSchema,
                    isEnabled: !server.disabledTools.contains(tool.name)
                )
            }
        } catch {
            print("Failed to get tools from \(server.name): \(error)")
            return []
        }
    }

    func getAllCustomPrompts() -> String {
        return servers
            .filter { $0.isEnabled }
            .compactMap { $0.customPrompt }
            .joined(separator: "\n\n")
    }
}

// MARK: - Models

struct MCPServer: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var customPrompt: String?
    var disabledTools: [String]
    var connectionStatus: ConnectionStatus
    var mcpEndpointPath: String? // Optional custom MCP endpoint path (default: /mcp)

    static func == (lhs: MCPServer, rhs: MCPServer) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    enum ConnectionStatus: String, Codable {
        case unknown
        case connected
        case disconnected
        case error
    }

    init(id: UUID, name: String, url: String, isBuiltIn: Bool, isEnabled: Bool, customPrompt: String? = nil, disabledTools: [String] = [], mcpEndpointPath: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.customPrompt = customPrompt
        self.disabledTools = disabledTools
        self.connectionStatus = .unknown
        self.mcpEndpointPath = mcpEndpointPath
    }
}

struct RegistryMCPTool: Identifiable, Hashable {
    let id = UUID()
    let serverID: UUID
    let serverName: String
    let name: String
    let description: String
    let inputSchema: Any
    var isEnabled: Bool

    static func == (lhs: RegistryMCPTool, rhs: RegistryMCPTool) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // For Ollama tool format conversion
    func toOllamaTool() -> OllamaService.Tool? {
        var properties: [String: OllamaService.Tool.PropertySchema] = [:]
        var required: [String] = []

        if let schema = inputSchema as? [String: Any],
           let props = schema["properties"] as? [String: [String: Any]],
           let req = schema["required"] as? [String] {

            for (key, value) in props {
                if let type = value["type"] as? String,
                   let description = value["description"] as? String {
                    properties[key] = OllamaService.Tool.PropertySchema(
                        type: type,
                        description: description
                    )
                }
            }
            required = req
        }

        return OllamaService.Tool(
            function: OllamaService.Tool.ToolFunction(
                name: name,
                description: description,
                parameters: OllamaService.Tool.ToolParameters(
                    properties: properties,
                    required: required
                )
            )
        )
    }
}
