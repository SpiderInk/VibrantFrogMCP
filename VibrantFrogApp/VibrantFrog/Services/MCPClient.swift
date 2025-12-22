//
//  MCPClient.swift
//  VibrantFrog
//
//  MCP Client that communicates with Python MCP server via subprocess
//  Based on MCP protocol 2024-11-05
//

import Foundation
import Combine

// MARK: - MCP Protocol Structures

struct MCPRequest<T: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: T?

    init(id: Int, method: String, params: T? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

struct MCPResponse<T: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int?
    let result: T?
    let error: MCPError?

    struct MCPError: Decodable {
        let code: Int
        let message: String
        let data: AnyCodable?
    }
}

// MARK: - MCP Message Types

struct InitializeParams: Codable {
    let protocolVersion: String
    let capabilities: ClientCapabilities
    let clientInfo: ClientInfo

    struct ClientCapabilities: Codable {
        let roots: RootsCapability?
        let sampling: SamplingCapability?
    }

    struct RootsCapability: Codable {
        let listChanged: Bool
    }

    struct SamplingCapability: Codable {}

    struct ClientInfo: Codable {
        let name: String
        let version: String
    }
}

struct InitializeResult: Codable {
    let protocolVersion: String
    let capabilities: ServerCapabilities
    let serverInfo: ServerInfo

    struct ServerCapabilities: Codable {
        let tools: ToolsCapability?
    }

    struct ToolsCapability: Codable {}

    struct ServerInfo: Codable {
        let name: String
        let version: String
    }
}

struct EmptyParams: Codable {}

struct ToolsListResult: Codable {
    let tools: [MCPTool]
}

struct MCPTool: Codable, Identifiable {
    let name: String
    let description: String
    let inputSchema: InputSchema

    var id: String { name }

    struct InputSchema: Codable {
        let type: String
        let properties: [String: Property]?
        let required: [String]?

        struct Property: Codable {
            let type: String
            let description: String?
        }
    }
}

struct ToolCallParams: Codable {
    let name: String
    let arguments: [String: AnyCodable]
}

struct ToolCallResult: Codable {
    let content: [Content]
    let isError: Bool?

    struct Content: Codable {
        let type: String
        let text: String?
        let data: String?
        let mimeType: String?
    }
}

// Helper for encoding/decoding Any values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - MCP Client

@MainActor
class MCPClient: ObservableObject {
    @Published var isConnected = false
    @Published var availableTools: [MCPTool] = []
    @Published var serverInfo: String = "Not connected"
    @Published var errorMessage: String?

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var nextRequestId = 1
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]

    private let pythonPath: String
    private let serverScriptPath: String?  // Optional: path to MCP server script

    init(pythonPath: String = "/usr/bin/python3",
         serverScriptPath: String? = nil) {
        self.pythonPath = pythonPath
        self.serverScriptPath = serverScriptPath
    }

    // MARK: - Connection Management

    func connect() async throws {
        guard process == nil else {
            throw MCPClientError.alreadyConnected
        }

        // Start Python MCP server process
        guard let scriptPath = serverScriptPath else {
            throw MCPClientError.processStartFailed
        }

        process = Process()
        inputPipe = Pipe()
        outputPipe = Pipe()

        process?.executableURL = URL(fileURLWithPath: pythonPath)
        process?.arguments = [scriptPath]
        process?.standardInput = inputPipe
        process?.standardOutput = outputPipe
        process?.standardError = Pipe() // Capture stderr separately

        // Start reading output
        startReadingOutput()

        do {
            try process?.run()

            // Initialize MCP session
            try await initialize()

            // Load available tools
            try await loadTools()

            await MainActor.run {
                self.isConnected = true
                self.errorMessage = nil
            }
        } catch {
            disconnect()
            throw error
        }
    }

    func disconnect() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        pendingRequests.removeAll()
        isConnected = false
    }

    private func startReadingOutput() {
        guard let outputPipe = outputPipe else { return }

        Task {
            let handle = outputPipe.fileHandleForReading

            for try await line in handle.bytes.lines {
                guard let data = line.data(using: .utf8) else { continue }
                handleResponse(data)
            }
        }
    }

    private func handleResponse(_ data: Data) {
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let id = json?["id"] as? Int else { return }

            if let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: data)
            }
        } catch {
            print("Failed to parse response: \(error)")
        }
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

        // Send initialized notification
        try await sendNotification(method: "notifications/initialized", params: EmptyParams() as EmptyParams?)
    }

    func loadTools() async throws {
        let result: ToolsListResult = try await sendRequest(method: "tools/list", params: EmptyParams())

        await MainActor.run {
            self.availableTools = result.tools
        }
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> ToolCallResult {
        let params = ToolCallParams(
            name: name,
            arguments: arguments.mapValues { AnyCodable($0) }
        )

        return try await sendRequest(method: "tools/call", params: params)
    }

    // MARK: - Low-Level Communication

    private struct NotificationMessage: Encodable {
        let jsonrpc = "2.0"
        let method: String
        let params: AnyCodable?
    }

    private func sendRequest<P: Encodable, R: Decodable>(method: String, params: P) async throws -> R {
        let id = nextRequestId
        nextRequestId += 1

        let request = MCPRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation

            guard let inputPipe = inputPipe else {
                continuation.resume(throwing: MCPClientError.notConnected)
                return
            }

            // Send request (JSON-RPC over stdio)
            var messageData = data
            messageData.append(contentsOf: "\n".utf8)

            inputPipe.fileHandleForWriting.write(messageData)
        }

        let response = try JSONDecoder().decode(MCPResponse<R>.self, from: responseData)

        if let error = response.error {
            throw MCPClientError.serverError(code: error.code, message: error.message)
        }

        guard let result = response.result else {
            throw MCPClientError.invalidResponse
        }

        return result
    }

    private func sendNotification<P: Encodable>(method: String, params: P? = nil) async throws {
        let notification = NotificationMessage(
            method: method,
            params: params.map { AnyCodable($0) }
        )
        let data = try JSONEncoder().encode(notification)

        guard let inputPipe = inputPipe else {
            throw MCPClientError.notConnected
        }

        var messageData = data
        messageData.append(contentsOf: "\n".utf8)

        inputPipe.fileHandleForWriting.write(messageData)
    }
}

// MARK: - Errors

enum MCPClientError: LocalizedError {
    case notConnected
    case alreadyConnected
    case serverError(code: Int, message: String)
    case invalidResponse
    case processStartFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MCP server"
        case .alreadyConnected:
            return "Already connected to MCP server"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .processStartFailed:
            return "Failed to start MCP server process"
        }
    }
}
