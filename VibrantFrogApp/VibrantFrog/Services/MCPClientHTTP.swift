//
//  MCPClientHTTP.swift
//  VibrantFrog
//
//  HTTP-based MCP Client using Streamable HTTP transport (MCP 2025-03-26)
//  Connects to Python MCP server over HTTP
//

import Foundation
import Combine

@MainActor
class MCPClientHTTP: ObservableObject {
    @Published var isConnected = false
    @Published var availableTools: [MCPTool] = []
    @Published var serverInfo: String = "Not connected"
    @Published var errorMessage: String?

    private var process: Process?
    private var session: URLSession
    private var nextRequestId = 1
    private let serverURL: URL
    private let mcpEndpoint: URL
    private let pythonPath: String
    private let serverScriptPath: String
    private var sessionId: String?

    convenience init() {
        self.init(serverURL: URL(string: "http://127.0.0.1:5050")!)
    }

    init(
        serverURL: URL,
        pythonPath: String = "/usr/bin/python3",
        serverScriptPath: String = "/Users/tpiazza/git/VibrantFrogMCP/vibrant_frog_mcp.py",
        mcpEndpointPath: String? = nil
    ) {
        self.serverURL = serverURL
        // Use custom endpoint path if provided, otherwise default to /mcp
        if let customPath = mcpEndpointPath {
            // If the custom path is empty, use the base URL directly
            if customPath.isEmpty {
                self.mcpEndpoint = serverURL
            } else {
                self.mcpEndpoint = serverURL.appendingPathComponent(customPath)
            }
        } else {
            self.mcpEndpoint = serverURL.appendingPathComponent("mcp")
        }
        self.pythonPath = pythonPath
        self.serverScriptPath = serverScriptPath

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connection Management

    func connect() async throws {
        print("🌐 MCPClientHTTP: Attempting to connect to \(serverURL)")
        print("🌐 MCPClientHTTP: MCP endpoint will be \(mcpEndpoint)")

        // Determine if this is a remote server (https:// or not localhost)
        let isRemoteServer = serverURL.scheme == "https" ||
                            (!(serverURL.host()?.contains("localhost") ?? false) &&
                             !(serverURL.host()?.contains("127.0.0.1") ?? false))

        if isRemoteServer {
            print("🌐 MCPClientHTTP: Detected remote server, skipping local Python server startup")
        } else {
            // Check if server is already running
            let serverAlreadyRunning = await checkServerAlive()
            print("🌐 MCPClientHTTP: Server alive check result: \(serverAlreadyRunning)")

            if !serverAlreadyRunning {
                print("🌐 MCPClientHTTP: Server not detected, attempting to start local Python server")
                // Start Python MCP server in HTTP mode
                try startHTTPServer()

                // Wait for server to start
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            } else {
                print("🌐 MCPClientHTTP: Server already running, connecting to existing instance")
            }
        }

        // Initialize MCP session
        print("🌐 MCPClientHTTP: Sending initialize request")
        try await initialize()
        print("🌐 MCPClientHTTP: Initialize successful, loading tools")

        // Load available tools
        try await loadTools()
        print("🌐 MCPClientHTTP: Tools loaded successfully")

        await MainActor.run {
            self.isConnected = true
            self.errorMessage = nil
        }
    }

    private func checkServerAlive() async -> Bool {
        // Try a simple HTTP request to see if server is responding
        var request = URLRequest(url: serverURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200 || httpResponse.statusCode == 404
            }
            return false
        } catch {
            return false
        }
    }

    private func startHTTPServer() throws {
        guard process == nil else {
            throw MCPClientError.alreadyConnected
        }

        process = Process()
        process?.executableURL = URL(fileURLWithPath: pythonPath)
        process?.arguments = [serverScriptPath, "--transport", "http"]
        process?.standardOutput = Pipe()
        process?.standardError = Pipe()

        try process?.run()
    }

    func disconnect() {
        process?.terminate()
        process = nil
        sessionId = nil
        isConnected = false
        availableTools = []
        serverInfo = "Not connected"
    }

    // MARK: - MCP Protocol Methods

    private func initialize() async throws {
        let params = InitializeParams(
            protocolVersion: "2024-11-05",
            capabilities: InitializeParams.ClientCapabilities(
                roots: InitializeParams.RootsCapability(listChanged: true),
                sampling: nil
            ),
            clientInfo: InitializeParams.ClientInfo(
                name: "VibrantFrog",
                version: "1.0.0"
            )
        )

        let result: InitializeResult = try await sendRequest(method: "initialize", params: params)

        await MainActor.run {
            self.serverInfo = "\(result.serverInfo.name) v\(result.serverInfo.version)"
        }
    }

    func loadTools() async throws {
        let result: ToolsListResult = try await sendRequest(method: "tools/list", params: EmptyParams())

        await MainActor.run {
            self.availableTools = result.tools
        }
    }

    func getTools() async throws -> [MCPTool] {
        let result: ToolsListResult = try await sendRequest(method: "tools/list", params: EmptyParams())
        return result.tools
    }

    func listTools() async throws -> ToolsListResult {
        return try await sendRequest(method: "tools/list", params: EmptyParams())
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> ToolCallResult {
        let params = ToolCallParams(
            name: name,
            arguments: arguments.mapValues { AnyCodable($0) }
        )

        return try await sendRequest(method: "tools/call", params: params)
    }

    // MARK: - Low-Level Communication (Streamable HTTP)

    private func sendRequest<P: Encodable, R: Decodable>(method: String, params: P) async throws -> R {
        let id = nextRequestId
        nextRequestId += 1

        let request = MCPRequest(id: id, method: method, params: params)
        let requestData = try JSONEncoder().encode(request)

        print("📤 MCPClientHTTP: Sending \(method) request to \(mcpEndpoint)")
        if let requestJSON = String(data: requestData, encoding: .utf8) {
            print("📤 Request body: \(requestJSON)")
        }

        // Create HTTP POST request to /mcp endpoint
        var urlRequest = URLRequest(url: mcpEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = requestData

        // Add session ID if we have one
        if let sessionId = sessionId {
            urlRequest.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
            print("📤 Using session ID: \(sessionId)")
        }

        // Send the request
        do {
            let (responseData, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ MCPClientHTTP: Invalid response type")
                throw MCPClientError.invalidResponse
            }

            print("📥 MCPClientHTTP: Received response with status \(httpResponse.statusCode)")
            if let responseJSON = String(data: responseData, encoding: .utf8) {
                print("📥 Response body: \(responseJSON)")
            }

            // Check for session ID in response (on initialize)
            if method == "initialize", let newSessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
                print("✅ Received new session ID: \(newSessionId)")
                await MainActor.run {
                    self.sessionId = newSessionId
                }
            }

            guard httpResponse.statusCode == 200 else {
                print("❌ MCPClientHTTP: HTTP error \(httpResponse.statusCode)")
                throw MCPClientError.serverError(
                    code: httpResponse.statusCode,
                    message: "HTTP \(httpResponse.statusCode)"
                )
            }

            // Parse JSON response
            let mcpResponse = try JSONDecoder().decode(MCPResponse<R>.self, from: responseData)

            if let error = mcpResponse.error {
                print("❌ MCPClientHTTP: MCP error \(error.code): \(error.message)")
                throw MCPClientError.serverError(code: error.code, message: error.message)
            }

            guard let result = mcpResponse.result else {
                print("❌ MCPClientHTTP: No result in response")
                throw MCPClientError.invalidResponse
            }

            print("✅ MCPClientHTTP: Successfully parsed response for \(method)")
            return result

        } catch let error as MCPClientError {
            throw error
        } catch {
            print("❌ MCPClientHTTP: Network error: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Helper for sending notifications (no response expected)

    private func sendNotification<P: Encodable>(method: String, params: P) async throws {
        let notification = NotificationMessage(method: method, params: AnyCodable(params))
        let requestData = try JSONEncoder().encode(notification)

        var urlRequest = URLRequest(url: mcpEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = requestData

        if let sessionId = sessionId {
            urlRequest.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        let (_, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPClientError.invalidResponse
        }

        // Notifications should return 202 Accepted
        guard httpResponse.statusCode == 202 || httpResponse.statusCode == 200 else {
            throw MCPClientError.serverError(
                code: httpResponse.statusCode,
                message: "HTTP \(httpResponse.statusCode)"
            )
        }
    }

    private struct NotificationMessage: Encodable {
        let jsonrpc = "2.0"
        let method: String
        let params: AnyCodable?
    }
}
