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
    @Published var selectedModel: String = "llama3.2:latest"

    // Models that support tool calling (function calling)
    // llama3.2 is generally better at actually calling tools vs mistral
    let toolSupportedModels = ["mistral", "llama3.1", "llama3.2", "qwen2.5", "mistral-nemo:latest"]

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
            let model: String
            let size: Int64
            let modified_at: String
            let digest: String
        }
    }

    init() {
        Task {
            await checkAvailability()
        }
    }

    // MARK: - Availability Check

    func checkAvailability() async {
        print("🔍 OllamaService: Starting availability check...")
        do {
            let url = baseURL.appendingPathComponent("api/tags")
            print("🔍 OllamaService: Requesting \(url.absoluteString)")

            let (data, response) = try await session.data(from: url)
            print("🔍 OllamaService: Got response, data size: \(data.count) bytes")

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ OllamaService: Response is not HTTPURLResponse")
                isAvailable = false
                return
            }

            print("🔍 OllamaService: HTTP status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                print("❌ OllamaService: HTTP status not 200")
                isAvailable = false
                return
            }

            print("🔍 OllamaService: Attempting to decode JSON...")
            let listResponse = try JSONDecoder().decode(ListModelsResponse.self, from: data)
            print("✅ OllamaService: Successfully decoded, found \(listResponse.models.count) models")

            availableModels = listResponse.models.map { model in
                OllamaModel(
                    name: model.name,
                    size: model.size,
                    modified: model.modified_at
                )
            }

            print("✅ OllamaService: Available models: \(availableModels.map { $0.name }.joined(separator: ", "))")

            // Explicitly update on main actor
            await MainActor.run {
                self.isAvailable = true
                print("✅ OllamaService: Ollama is AVAILABLE (isAvailable set to true)")
            }

        } catch {
            print("❌ OllamaService: Ollama not available - Error: \(error)")
            if let urlError = error as? URLError {
                print("❌ OllamaService: URLError code: \(urlError.code.rawValue), description: \(urlError.localizedDescription)")
            }
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
        let temperature: Double = 0.3  // Moderate temperature for better tool calling
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

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Ollama: Invalid HTTP response")
            throw OllamaError.requestFailed
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Ollama HTTP \(httpResponse.statusCode): \(errorText)")
            throw OllamaError.requestFailed
        }

        do {
            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            return chatResponse.message
        } catch {
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode"
            print("❌ Ollama JSON decode error: \(error)")
            print("📄 Response: \(responseText)")
            throw OllamaError.invalidResponse
        }
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

// Note: AnyCodable is defined in MCPClient.swift to avoid duplication
