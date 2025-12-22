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
    private let baseServerURL: URL  // Base URL for server check (without endpoint path)
    private let mcpEndpoint: URL    // Complete MCP endpoint URL (as provided by user)
    private let pythonPath: String
    private let serverScriptPath: String?  // Optional: path to MCP server script (if running locally)
    private var sessionId: String?

    convenience init() {
        // Default server with complete path including /mcp endpoint
        self.init(serverURL: URL(string: "http://127.0.0.1:5050/mcp")!)
    }

    init(
        serverURL: URL,
        pythonPath: String = "/usr/bin/python3",
        serverScriptPath: String? = nil
    ) {
        // Use the complete URL as provided by the user - DO NOT append /mcp
        self.mcpEndpoint = serverURL

        // Extract base URL (scheme + host + port) for server health checks
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        self.baseServerURL = components?.url ?? serverURL

        self.pythonPath = pythonPath
        self.serverScriptPath = serverScriptPath

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connection Management

    func connect() async throws {
        print("🔌 MCPClientHTTP: Starting connection process...")
        print("🔌 MCPClientHTTP: Base server URL: \(baseServerURL)")
        print("🔌 MCPClientHTTP: MCP endpoint: \(mcpEndpoint)")

        // Check if server is already running
        print("🔌 MCPClientHTTP: Checking if server is alive...")
        let serverAlreadyRunning = await checkServerAlive()
        print("🔌 MCPClientHTTP: Server alive check result: \(serverAlreadyRunning)")

        if !serverAlreadyRunning {
            print("🔌 MCPClientHTTP: Starting Python MCP server...")
            print("🔌 MCPClientHTTP: Python path: \(pythonPath)")
            print("🔌 MCPClientHTTP: Script path: \(serverScriptPath ?? "not configured")")

            // Start Python MCP server in HTTP mode
            try startHTTPServer()
            print("🔌 MCPClientHTTP: Server process started, waiting 2 seconds...")

            // Wait for server to start
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            print("🔌 MCPClientHTTP: Wait complete")
        } else {
            print("🌐 MCPClientHTTP: Server already running, connecting to existing instance")
        }

        // Initialize MCP session
        print("🔌 MCPClientHTTP: Initializing MCP session...")
        try await initialize()
        print("✅ MCPClientHTTP: Session initialized")

        // Load available tools
        print("🔌 MCPClientHTTP: Loading available tools...")
        try await loadTools()
        print("✅ MCPClientHTTP: Tools loaded: \(availableTools.count) tools")

        await MainActor.run {
            self.isConnected = true
            self.errorMessage = nil
        }

        print("✅ MCPClientHTTP: Connection complete!")
    }

    private func checkServerAlive() async -> Bool {
        // Try a simple HTTP request to see if server is responding
        // Use base URL for health check
        var request = URLRequest(url: baseServerURL)
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

        guard let scriptPath = serverScriptPath else {
            // No script path configured - this is OK for remote servers
            // Just skip starting the local server
            print("ℹ️  No local MCP server script configured - connecting to remote server")
            return
        }

        process = Process()
        process?.executableURL = URL(fileURLWithPath: pythonPath)
        process?.arguments = [scriptPath, "--transport", "http"]
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

        // Create HTTP POST request to /mcp endpoint
        var urlRequest = URLRequest(url: mcpEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = requestData

        // Add session ID if we have one
        if let sessionId = sessionId {
            urlRequest.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        // Send the request
        let (responseData, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPClientError.invalidResponse
        }

        // Check for session ID in response (on initialize)
        if method == "initialize", let newSessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            await MainActor.run {
                self.sessionId = newSessionId
            }
        }

        guard httpResponse.statusCode == 200 else {
            throw MCPClientError.serverError(
                code: httpResponse.statusCode,
                message: "HTTP \(httpResponse.statusCode)"
            )
        }

        // Parse JSON response
        let mcpResponse = try JSONDecoder().decode(MCPResponse<R>.self, from: responseData)

        if let error = mcpResponse.error {
            throw MCPClientError.serverError(code: error.code, message: error.message)
        }

        guard let result = mcpResponse.result else {
            throw MCPClientError.invalidResponse
        }

        return result
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
