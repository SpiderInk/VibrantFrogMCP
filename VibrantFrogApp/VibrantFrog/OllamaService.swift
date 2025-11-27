//
//  OllamaService.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import Foundation

/// Service for interacting with Ollama API with MCP tool calling support
@MainActor
class OllamaService: ObservableObject {
    @Published var isAvailable: Bool = false
    @Published var availableModels: [OllamaModel] = []
    @Published var selectedModel: String = "gemma3:4b"

    private let baseURL = URL(string: "http://127.0.0.1:11434")!
    private let session = URLSession.shared

    struct OllamaModel: Codable, Identifiable {
        let name: String
        let size: Int64
        let modified: String

        var id: String { name }
    }

    struct ListModelsResponse: Codable {
        let models: [ModelInfo]

        struct ModelInfo: Codable {
            let name: String
            let size: Int64
            let modified_at: String
        }
    }

    init() {
        Task {
            await checkAvailability()
        }
    }

    // MARK: - Availability Check

    func checkAvailability() async {
        do {
            let url = baseURL.appendingPathComponent("api/tags")
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isAvailable = false
                return
            }

            let listResponse = try JSONDecoder().decode(ListModelsResponse.self, from: data)
            availableModels = listResponse.models.map { model in
                OllamaModel(
                    name: model.name,
                    size: model.size,
                    modified: model.modified_at
                )
            }
            isAvailable = true

        } catch {
            print("Ollama not available: \(error)")
            isAvailable = false
        }
    }

    // MARK: - Chat with Tool Calling

    struct ChatMessage: Codable {
        let role: String
        let content: String
        var tool_calls: [ToolCall]?

        struct ToolCall: Codable {
            let function: Function

            struct Function: Codable {
                let name: String
                let arguments: [String: AnyCodable]
            }
        }
    }

    struct Tool: Codable {
        let type: String = "function"
        let function: ToolFunction

        struct ToolFunction: Codable {
            let name: String
            let description: String
            let parameters: ToolParameters
        }

        struct ToolParameters: Codable {
            let type: String = "object"
            let properties: [String: PropertySchema]
            let required: [String]
        }

        struct PropertySchema: Codable {
            let type: String
            let description: String
        }
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let tools: [Tool]?
        let stream: Bool = false
    }

    struct ChatResponse: Codable {
        let message: ChatMessage
        let done: Bool
    }

    /// Chat with Ollama and handle tool calls
    func chat(
        messages: [ChatMessage],
        tools: [Tool]? = nil
    ) async throws -> ChatMessage {
        let url = baseURL.appendingPathComponent("api/chat")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let chatRequest = ChatRequest(
            model: selectedModel,
            messages: messages,
            tools: tools
        )

        request.httpBody = try JSONEncoder().encode(chatRequest)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.message
    }

    /// Generate text completion (simple, no tools)
    func generate(prompt: String) async throws -> String {
        let message = try await chat(messages: [
            ChatMessage(role: "user", content: prompt)
        ])
        return message.content
    }
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case notAvailable
    case requestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Ollama is not running. Please start Ollama first."
        case .requestFailed:
            return "Failed to communicate with Ollama"
        case .invalidResponse:
            return "Invalid response from Ollama"
        }
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
