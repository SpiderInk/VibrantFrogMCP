//
//  AIChatView.swift
//  VibrantFrog
//
//  Real LLM chat with MCP tool calling
//

import SwiftUI
import Photos
import Combine

struct AIChatView: View {
    @StateObject private var viewModel = AIChatViewModel()
    @StateObject private var photoService = PhotoLibraryService()
    @EnvironmentObject var mcpClient: MCPClientHTTP
    @State private var inputText: String = ""
    @State private var isProcessing: Bool = false

    // Observe ollamaService directly to get UI updates
    private var ollamaService: OllamaService {
        viewModel.ollamaService
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Chat")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                // Model selector
                if viewModel.ollamaService.isAvailable {
                    Picker("Model", selection: $viewModel.ollamaService.selectedModel) {
                        ForEach(viewModel.ollamaService.availableModels) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                    .frame(width: 200)
                } else {
                    Text("Ollama not available")
                        .foregroundStyle(.red)
                }

                // MCP Connection Status
                Circle()
                    .fill(mcpClient.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(mcpClient.isConnected ? "MCP Connected" : "MCP Disconnected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !mcpClient.isConnected {
                    Button("Connect MCP") {
                        Task {
                            try? await mcpClient.connect()
                        }
                    }
                }
            }
            .padding()

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }

                        if isProcessing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 12) {
                TextField("Ask about your photos...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(isProcessing || !viewModel.ollamaService.isAvailable)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.isEmpty || isProcessing ? .secondary : Color.blue)
                }
                .disabled(inputText.isEmpty || isProcessing || !viewModel.ollamaService.isAvailable)
                .buttonStyle(.plain)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            viewModel.setup(mcpClient: mcpClient, photoService: photoService)
            Task {
                await viewModel.ollamaService.checkAvailability()

                // Auto-connect to MCP server if not already connected
                if !mcpClient.isConnected {
                    do {
                        try await mcpClient.connect()
                        print("✅ AIChatView: Auto-connected to MCP server")
                    } catch {
                        print("❌ AIChatView: Failed to connect to MCP server: \(error)")
                    }
                }
            }
        }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        let userMessage = inputText
        inputText = ""
        isProcessing = true

        Task {
            await viewModel.sendMessage(userMessage)
            isProcessing = false
        }
    }
}

// MARK: - View Model

@MainActor
class AIChatViewModel: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var ollamaService = OllamaService()

    private var mcpClient: MCPClientHTTP?
    private var photoService: PhotoLibraryService?
    private var conversationHistory: [OllamaService.ChatMessage] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Forward changes from ollamaService to this ViewModel
        ollamaService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    func setup(mcpClient: MCPClientHTTP, photoService: PhotoLibraryService) {
        self.mcpClient = mcpClient
        self.photoService = photoService

        // Add system instruction for tool use
        if conversationHistory.isEmpty {
            conversationHistory.append(OllamaService.ChatMessage(
                role: "system",
                content: """
                You are a helpful AI assistant with access to photo management tools.

                CRITICAL RULES:
                1. When users ask about photos, you MUST call the tools directly - do NOT explain or describe what tools to use
                2. NEVER write code or pseudocode - you have real function calling capability
                3. DO NOT say "I will use tool X" or "You should call function Y" - just call it
                4. DO NOT output markdown code blocks or example function calls - use actual tool calling

                Available tools:
                - search_photos: Find photos by query
                - create_album_from_search: Create albums from search results
                - list_albums: List existing albums

                When a user asks "Show me beach photos", you MUST immediately call search_photos(query="beach"), not describe it.
                After calling tools and getting results, provide a friendly natural language response summarizing what you found.
                """
            ))
        }

        // Add welcome message
        if messages.isEmpty {
            messages.append(AIChatMessage(
                role: .system,
                content: """
                Welcome to VibrantFrog AI Chat!

                I'm an AI assistant powered by \(ollamaService.selectedModel) with access to your photo library through MCP tools.

                Try asking:
                • "Show me beach photos"
                • "Find photos from last summer"
                • "Create an album from sunset photos"
                """,
                timestamp: Date()
            ))
        }
    }

    func sendMessage(_ text: String) async {
        // Add user message
        let userMsg = AIChatMessage(role: .user, content: text, timestamp: Date())
        messages.append(userMsg)

        // Add to conversation history
        conversationHistory.append(OllamaService.ChatMessage(
            role: "user",
            content: text
        ))

        do {
            // Define available MCP tools
            let tools = try await getMCPTools()
            print("🔧 AIChatViewModel: Fetched \(tools.count) MCP tools")
            for tool in tools {
                print("  - \(tool.function.name): \(tool.function.description)")
                print("    Parameters: \(tool.function.parameters.properties.keys.joined(separator: ", "))")
            }

            // Call Ollama with tools
            print("🤖 AIChatViewModel: Calling Ollama with \(tools.isEmpty ? "NO" : "\(tools.count)") tools")
            let response = try await ollamaService.chat(
                messages: conversationHistory,
                tools: tools.isEmpty ? nil : tools
            )
            print("🤖 AIChatViewModel: Got response from Ollama")
            print("🤖 Response content: \(response.content)")
            print("🤖 Tool calls: \(response.tool_calls?.count ?? 0)")

            // Check if LLM wants to call tools
            if let toolCalls = response.tool_calls, !toolCalls.isEmpty {
                print("✅ AIChatViewModel: LLM wants to call \(toolCalls.count) tools!")
                // Execute MCP tools
                let toolResults = try await executeToolCalls(toolCalls)

                // Add tool results to conversation
                conversationHistory.append(response)

                // Add tool results as system message
                for result in toolResults {
                    conversationHistory.append(OllamaService.ChatMessage(
                        role: "tool",
                        content: result
                    ))
                }

                // Get final response from LLM
                let finalResponse = try await ollamaService.chat(
                    messages: conversationHistory,
                    tools: nil
                )

                // Add assistant's final response
                conversationHistory.append(finalResponse)
                messages.append(AIChatMessage(
                    role: .assistant,
                    content: finalResponse.content,
                    timestamp: Date()
                ))

            } else {
                // No tool calls, just add response
                conversationHistory.append(response)
                messages.append(AIChatMessage(
                    role: .assistant,
                    content: response.content,
                    timestamp: Date()
                ))
            }

        } catch {
            messages.append(AIChatMessage(
                role: .system,
                content: "Error: \(error.localizedDescription)",
                timestamp: Date()
            ))
        }
    }

    private func getMCPTools() async throws -> [OllamaService.Tool] {
        guard let mcpClient = mcpClient, mcpClient.isConnected else {
            return []
        }

        // Get tools from MCP server
        let toolsList = try await mcpClient.listTools()

        // Convert MCP tools to Ollama tool format
        return toolsList.tools.compactMap { tool in
            // Extract parameter schema
            var properties: [String: OllamaService.Tool.PropertySchema] = [:]
            var required: [String] = []

            if let inputSchema = tool.inputSchema as? [String: Any],
               let props = inputSchema["properties"] as? [String: [String: Any]],
               let req = inputSchema["required"] as? [String] {

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

            // Enhance description with parameter examples for common tools
            var enhancedDescription = tool.description ?? "MCP tool"
            if tool.name == "search_photos" {
                enhancedDescription += ". Example: search_photos(query=\"beach\", n_results=10). IMPORTANT: Use 'query' not 'q'."
            }

            return OllamaService.Tool(
                function: OllamaService.Tool.ToolFunction(
                    name: tool.name,
                    description: enhancedDescription,
                    parameters: OllamaService.Tool.ToolParameters(
                        properties: properties,
                        required: required
                    )
                )
            )
        }
    }

    private func executeToolCalls(_ toolCalls: [OllamaService.ChatMessage.ToolCall]) async throws -> [String] {
        guard let mcpClient = mcpClient else {
            throw AIChatError.mcpNotAvailable
        }

        var results: [String] = []

        for toolCall in toolCalls {
            let toolName = toolCall.function.name
            var args = toolCall.function.arguments.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = pair.value.value
            }

            // Fix type conversions: Ollama sometimes returns integers as strings
            // Convert n_results from string to int if needed
            if let nResultsStr = args["n_results"] as? String,
               let nResultsInt = Int(nResultsStr) {
                args["n_results"] = nResultsInt
            }

            print("🔧 Calling MCP tool: \(toolName) with args: \(args)")

            let result = try await mcpClient.callTool(name: toolName, arguments: args)

            // Extract text content from result
            let textContent = result.content
                .filter { $0.type == "text" }
                .compactMap { $0.text }
                .joined(separator: "\n")

            results.append(textContent)

            // If this was a search_photos call, parse UUIDs and load thumbnails
            if toolName == "search_photos" {
                print("🔍 Parsing UUIDs from search_photos result...")
                print("📄 Result text preview (first 500 chars): \(String(textContent.prefix(500)))")
                let uuids = parseUUIDs(from: textContent)
                print("🔍 Found \(uuids.count) UUIDs: \(uuids)")
                if !uuids.isEmpty, let photoService = photoService {
                    print("📸 Loading \(uuids.count) thumbnails...")
                    let thumbnails = await photoService.loadThumbnailsByUUIDs(uuids)

                    // Create photo thumbnail objects
                    var photoThumbs: [PhotoThumbnail] = []
                    for uuid in uuids {
                        photoThumbs.append(PhotoThumbnail(
                            uuid: uuid,
                            image: thumbnails[uuid],
                            description: extractDescription(for: uuid, from: textContent)
                        ))
                    }

                    // Add tool result message with thumbnails
                    messages.append(AIChatMessage(
                        role: .tool,
                        content: "Called \(toolName)\n\n\(textContent)",
                        timestamp: Date(),
                        toolName: toolName,
                        photoThumbnails: photoThumbs
                    ))
                } else {
                    // No UUIDs or no photo service, add message without thumbnails
                    messages.append(AIChatMessage(
                        role: .tool,
                        content: "Called \(toolName)\n\n\(textContent)",
                        timestamp: Date(),
                        toolName: toolName
                    ))
                }
            } else {
                // Not a search_photos call, add regular tool message
                messages.append(AIChatMessage(
                    role: .tool,
                    content: "Called \(toolName)\n\n\(textContent)",
                    timestamp: Date(),
                    toolName: toolName
                ))
            }
        }

        return results
    }

    private func parseUUIDs(from text: String) -> [String] {
        var uuids: [String] = []
        let lines = text.split(separator: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Handle both "UUID:" and "   UUID:" formats
            if trimmed.contains("UUID:") {
                // Split on "UUID:" and take the part after it
                if let uuidPart = trimmed.split(separator: ":").last {
                    let uuid = String(uuidPart).trimmingCharacters(in: .whitespaces)
                    // Validate it looks like a UUID (has dashes and is reasonable length)
                    if !uuid.isEmpty && uuid.contains("-") && uuid.count > 20 {
                        uuids.append(uuid)
                        print("  ✅ Parsed UUID: \(uuid)")
                    }
                }
            }
        }

        return uuids
    }

    private func extractDescription(for uuid: String, from text: String) -> String? {
        // Parse description from MCP result text
        // Format: UUID: xxx\nDescription: yyy\nRelevance: zzz
        let lines = text.split(separator: "\n")
        var foundUUID = false

        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.starts(with: "UUID:") && line.contains(uuid) {
                foundUUID = true
            } else if foundUUID && line.starts(with: "Description:") {
                return String(line.dropFirst(12).trimmingCharacters(in: .whitespaces))
            } else if foundUUID && line.starts(with: "Relevance:") {
                break  // End of this photo's info
            }
        }

        return nil
    }
}

// MARK: - Message Model

struct AIChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date
    var toolName: String?
    var photoThumbnails: [PhotoThumbnail]?

    enum MessageRole {
        case user
        case assistant
        case system
        case tool
    }

    static func == (lhs: AIChatMessage, rhs: AIChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

struct PhotoThumbnail: Identifiable {
    let id = UUID()
    let uuid: String
    var image: NSImage?
    let description: String?
}

// MARK: - Message View

struct MessageView: View {
    let message: AIChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(avatarColor)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: avatarIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Role label
                Text(roleLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                // Content
                Text(message.content)
                    .textSelection(.enabled)

                // Photo thumbnails grid
                if let thumbnails = message.photoThumbnails, !thumbnails.isEmpty {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150, maximum: 200))
                    ], spacing: 12) {
                        ForEach(thumbnails) { thumb in
                            VStack(alignment: .leading, spacing: 4) {
                                if let image = thumb.image {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 150)
                                        .clipped()
                                        .cornerRadius(8)
                                        .onTapGesture {
                                            openPhoto(uuid: thumb.uuid)
                                        }
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 150)
                                        .cornerRadius(8)
                                        .overlay(
                                            ProgressView()
                                        )
                                }

                                if let desc = thumb.description {
                                    Text(desc)
                                        .font(.caption2)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
    }

    private func openPhoto(uuid: String) {
        let url = URL(string: "photos://asset?uuid=\(uuid)")!
        NSWorkspace.shared.open(url)
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "AI Assistant"
        case .system: return "System"
        case .tool: return message.toolName.map { "Tool: \($0)" } ?? "Tool"
        }
    }

    private var avatarIcon: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "brain"
        case .system: return "info.circle.fill"
        case .tool: return "wrench.fill"
        }
    }

    private var avatarColor: Color {
        switch message.role {
        case .user: return .blue
        case .assistant: return .purple
        case .system: return .gray
        case .tool: return .orange
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return Color.blue.opacity(0.1)
        case .assistant: return Color.purple.opacity(0.1)
        case .system: return Color.gray.opacity(0.1)
        case .tool: return Color.orange.opacity(0.1)
        }
    }
}

// MARK: - Errors

enum AIChatError: LocalizedError {
    case mcpNotAvailable
    case toolExecutionFailed

    var errorDescription: String? {
        switch self {
        case .mcpNotAvailable:
            return "MCP server is not connected"
        case .toolExecutionFailed:
            return "Failed to execute MCP tool"
        }
    }
}

#Preview {
    AIChatView()
        .environmentObject(MCPClientHTTP())
}
