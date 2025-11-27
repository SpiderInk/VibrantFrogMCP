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
                    url: "http://127.0.0.1:5050/mcp",
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

    func addServer(name: String, url: String) {
        let server = MCPServer(
            id: UUID(),
            name: name,
            url: url,
            isBuiltIn: false,
            isEnabled: true
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

    // MARK: - Get All Available Tools

    func getAllTools() async throws -> [RegistryMCPTool] {
        var allTools: [RegistryMCPTool] = []

        for server in servers where server.isEnabled {
            do {
                // Create temporary client for this server
                let client = MCPClientHTTP(serverURL: URL(string: server.url)!)
                try await client.connect()

                let toolsList = try await client.getTools()
                let tools = toolsList.map { tool in
                    RegistryMCPTool(
                        serverID: server.id,
                        serverName: server.name,
                        name: tool.name,
                        description: tool.description ?? "",
                        inputSchema: tool.inputSchema
                    )
                }
                allTools.append(contentsOf: tools)

            } catch {
                print("Failed to get tools from \(server.name): \(error)")
            }
        }

        return allTools
    }
}

// MARK: - Models

struct MCPServer: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var isBuiltIn: Bool
    var isEnabled: Bool
}

struct RegistryMCPTool: Identifiable {
    let id = UUID()
    let serverID: UUID
    let serverName: String
    let name: String
    let description: String
    let inputSchema: Any

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
