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
    @StateObject private var promptStore = PromptTemplateStore()
    @StateObject private var mcpRegistry = MCPServerRegistry()
    @EnvironmentObject var mcpClient: MCPClientHTTP
    @EnvironmentObject var conversationStore: ConversationStore
    @State private var inputText: String = ""
    @State private var isProcessing: Bool = false
    @State private var selectedPromptTemplate: PromptTemplate?
    @State private var selectedMCPServer: MCPServer?

    // Observe ollamaService directly to get UI updates
    private var ollamaService: OllamaService {
        viewModel.ollamaService
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                // First row - Title and actions
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Chat")
                            .font(.title2)
                            .fontWeight(.semibold)

                        if let conversation = conversationStore.currentConversation {
                            Text(conversation.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // New conversation button
                    Button(action: {
                        viewModel.startNewConversation(store: conversationStore)
                    }) {
                        Label("New", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }

                // Second row - Selectors
                HStack(spacing: 12) {
                    // Prompt Template selector
                    Menu {
                        ForEach(promptStore.templates) { template in
                            Button(action: {
                                selectedPromptTemplate = template
                                viewModel.setPromptTemplate(template)
                            }) {
                                VStack(alignment: .leading) {
                                    Text(template.name)
                                    Text(template.lastEdited.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            if let prompt = selectedPromptTemplate {
                                Text(prompt.name)
                            } else {
                                Text("Select Prompt")
                            }
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                    }
                    .frame(width: 180)

                    // MCP Server selector
                    Menu {
                        ForEach(mcpRegistry.servers.filter { $0.isEnabled }) { server in
                            Button(action: {
                                selectedMCPServer = server
                                viewModel.setMCPServer(server)
                            }) {
                                Text(server.name)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "network")
                            if let server = selectedMCPServer {
                                Text(server.name)
                            } else {
                                Text("Select MCP Server")
                            }
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                    }
                    .frame(width: 180)

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

                    Spacer()

                    // MCP Connection Status
                    Circle()
                        .fill(mcpClient.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(mcpClient.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            }
            .padding()

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageView(message: message)
                                .id("\(message.id)-\(message.photoThumbnails?.count ?? 0)")
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
                    .id(viewModel.thumbnailsVersion)  // Force entire stack to rebuild when thumbnails change
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
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
            viewModel.setup(mcpClient: mcpClient, photoService: photoService, conversationStore: conversationStore)

            // Load saved selections and restore UI state (only if not already set)
            if selectedPromptTemplate == nil,
               let savedPromptID = viewModel.getSavedPromptTemplateID(),
               let template = promptStore.templates.first(where: { $0.id == savedPromptID }) {
                selectedPromptTemplate = template
                viewModel.setPromptTemplate(template)
            }

            if selectedMCPServer == nil,
               let savedServerID = viewModel.getSavedMCPServerID(),
               let server = mcpRegistry.servers.first(where: { $0.id == savedServerID }) {
                selectedMCPServer = server
                viewModel.setMCPServer(server)
            }

            // Reload thumbnails when view appears (in case they were lost on tab switch)
            viewModel.reloadThumbnailsIfNeeded()

            // Request photo library access if needed
            if !photoService.isAuthorized {
                photoService.requestAuthorization()
            }

            Task {
                await viewModel.ollamaService.checkAvailability()

                // NOW load the saved model AFTER Ollama is ready and models are fetched
                viewModel.loadSavedModel()

                // Auto-connect to MCP server if not already connected
                if !mcpClient.isConnected {
                    do {
                        try await mcpClient.connect()
                        print("✅ AIChatView: Auto-connected to MCP server")

                        // CRITICAL FIX: After MCP connects, regenerate system message with tools
                        // This ensures the first chat request includes tool descriptions in the system prompt
                        await viewModel.refreshToolsAndRegenerateSystemMessage(mcpClient: mcpClient)
                    } catch {
                        print("❌ AIChatView: Failed to connect to MCP server: \(error)")
                    }
                }
            }
        }
        .onChange(of: viewModel.ollamaService.selectedModel) { oldValue, newValue in
            print("🔄 Model changed to: \(newValue), setup complete: \(viewModel.isSetupComplete)")
            // Save model selection when it changes (only if setup is complete)
            if viewModel.isSetupComplete {
                UserDefaults.standard.set(newValue, forKey: "selectedOllamaModel")
                print("💾 Saved model selection: \(newValue)")
            } else {
                print("⏳ Not saving yet - setup not complete")
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
    @Published var thumbnailsVersion: Int = 0  // Increment this to force view refresh

    private var mcpClient: MCPClientHTTP?
    private var photoService: PhotoLibraryService?
    private var conversationStore: ConversationStore?
    private var conversationHistory: [OllamaService.ChatMessage] = []
    private var cancellables = Set<AnyCancellable>()
    private var isSetup = false

    // Prompt template and MCP server selection
    private var currentPromptTemplate: PromptTemplate?
    private var currentMCPServer: MCPServer?
    private var currentMCPClient: MCPClientHTTP?  // MCP client for selected server
    private var availableTools: [String] = []

    // Persistence keys
    private let selectedPromptTemplateKey = "selectedPromptTemplateID"
    private let selectedMCPServerKey = "selectedMCPServerID"
    private let selectedModelKey = "selectedOllamaModel"

    // Public property to check if setup is complete
    var isSetupComplete: Bool {
        return isSetup
    }

    init() {
        // Forward changes from ollamaService to this ViewModel
        ollamaService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    func setup(mcpClient: MCPClientHTTP, photoService: PhotoLibraryService, conversationStore: ConversationStore) {
        // Only setup once
        if isSetup {
            print("⚠️ AIChatViewModel: setup() called but already set up, skipping")
            return
        }

        self.mcpClient = mcpClient
        self.photoService = photoService
        self.conversationStore = conversationStore

        // Load current conversation or create new one
        if let currentConv = conversationStore.currentConversation {
            print("🔄 AIChatViewModel: Loading existing conversation on setup")
            loadConversation(currentConv)
        } else {
            startNewConversation(store: conversationStore)
        }

        // Mark setup as complete AFTER services are assigned but BEFORE model is loaded
        // This ensures onChange handlers know we're ready, but model loading happens after Ollama is available
        isSetup = true
        print("✅ AIChatViewModel: Setup complete, ready to load model")
    }

    func loadSavedModel() {
        // Load saved model - should be called AFTER Ollama availability check completes
        if let savedModel = UserDefaults.standard.string(forKey: selectedModelKey) {
            // Verify the saved model is actually in the available models list
            let modelExists = ollamaService.availableModels.contains { $0.name == savedModel }

            if modelExists {
                print("📥 Loading saved model: \(savedModel) (verified in available models)")

                // CRITICAL FIX: We need to FORCE the Picker binding to update by toggling the value
                // Just setting the value doesn't activate the model in Ollama - we need to trigger
                // the binding change handler by setting to a different value first, then back
                Task { @MainActor in
                    // Find a different model to temporarily switch to
                    if let tempModel = ollamaService.availableModels.first(where: { $0.name != savedModel }) {
                        print("🔄 Activating model by toggling: \(savedModel) -> \(tempModel.name) -> \(savedModel)")

                        // Temporarily switch to different model
                        ollamaService.selectedModel = tempModel.name

                        // Small delay to ensure the change is processed
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

                        // Now switch to the actual saved model - this triggers the Picker properly
                        ollamaService.selectedModel = savedModel

                        print("✅ Model activated: \(savedModel)")
                    } else {
                        // Only one model available, just set it directly
                        print("ℹ️ Only one model available, setting directly: \(savedModel)")
                        ollamaService.selectedModel = savedModel
                    }
                }
            } else {
                print("⚠️ Saved model '\(savedModel)' not found in available models")
                print("📋 Available models: \(ollamaService.availableModels.map { $0.name }.joined(separator: ", "))")

                // Fall back to first available model or keep default
                if let firstModel = ollamaService.availableModels.first {
                    print("🔄 Falling back to first available model: \(firstModel.name)")
                    ollamaService.selectedModel = firstModel.name
                }
            }
        } else {
            print("ℹ️ No saved model found, using default: \(ollamaService.selectedModel)")

            // Even with default model, we need to trigger the binding
            Task { @MainActor in
                let defaultModel = ollamaService.selectedModel
                if let tempModel = ollamaService.availableModels.first(where: { $0.name != defaultModel }) {
                    print("🔄 Activating default model by toggling: \(defaultModel) -> \(tempModel.name) -> \(defaultModel)")
                    ollamaService.selectedModel = tempModel.name
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    ollamaService.selectedModel = defaultModel
                    print("✅ Default model activated: \(defaultModel)")
                }
            }
        }
    }

    // Keep this for backwards compatibility with other code that might call it
    func loadSavedSelections() {
        // This is now just for non-model selections
        // Model is loaded separately via loadSavedModel() after Ollama is ready
        print("ℹ️ loadSavedSelections() called (model loading now happens separately)")
    }

    func getSavedPromptTemplateID() -> UUID? {
        guard let uuidString = UserDefaults.standard.string(forKey: selectedPromptTemplateKey),
              let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        return uuid
    }

    func getSavedMCPServerID() -> UUID? {
        guard let uuidString = UserDefaults.standard.string(forKey: selectedMCPServerKey),
              let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        return uuid
    }

    func startNewConversation(store: ConversationStore) {
        _ = store.createNewConversation(model: ollamaService.selectedModel)
        conversationHistory = []
        messages = []
        setupSystemMessage()
    }

    func loadConversation(_ conversation: Conversation) {
        // Convert stored messages to display format (without thumbnails initially)
        messages = conversation.messages.compactMap { msg -> AIChatMessage? in
            guard let role = AIChatMessage.MessageRole(from: msg.role) else { return nil }
            return AIChatMessage(
                role: role,
                content: msg.content,
                timestamp: msg.timestamp,
                toolName: msg.toolName,
                photoThumbnails: nil
            )
        }

        // Rebuild conversation history for Ollama
        conversationHistory = conversation.messages.map { msg in
            OllamaService.ChatMessage(role: msg.role, content: msg.content)
        }

        // Set model
        ollamaService.selectedModel = conversation.selectedModel

        // If no system message, add one
        if conversationHistory.isEmpty || conversationHistory.first?.role != "system" {
            setupSystemMessage()
        }

        // Load thumbnails asynchronously for messages that have photoUUIDs
        print("🔄 Loading conversation with \(conversation.messages.count) messages")
        Task {
            for (index, msg) in conversation.messages.enumerated() {
                if let uuids = msg.photoUUIDs, !uuids.isEmpty {
                    print("📸 Message \(index) has \(uuids.count) photo UUIDs: \(uuids.prefix(3))...")

                    guard let photoService = photoService else {
                        print("⚠️ PhotoService not available")
                        continue
                    }

                    let thumbnails = await photoService.loadThumbnailsByUUIDs(uuids)
                    print("✅ Loaded \(thumbnails.count) thumbnails for message \(index)")

                    await MainActor.run {
                        guard index < messages.count else {
                            print("⚠️ Index \(index) out of bounds (messages.count = \(messages.count))")
                            return
                        }

                        // Create a new message with thumbnails to trigger SwiftUI update
                        var updatedMessage = messages[index]
                        updatedMessage.photoThumbnails = uuids.map { uuid in
                            PhotoThumbnail(uuid: uuid, image: thumbnails[uuid], description: nil)
                        }

                        // Force SwiftUI to detect the change by replacing the entire array
                        var newMessages = messages
                        newMessages[index] = updatedMessage

                        // Explicitly notify SwiftUI of the change
                        objectWillChange.send()
                        messages = newMessages
                        thumbnailsVersion += 1  // Force view refresh

                        print("✅ Updated message \(index) with \(updatedMessage.photoThumbnails?.count ?? 0) thumbnails")
                    }
                }
            }
            print("🔄 Finished loading all thumbnails")
        }
    }

    func reloadThumbnailsIfNeeded() {
        print("🔄 reloadThumbnailsIfNeeded() called")

        guard let conversationStore = conversationStore,
              let currentConv = conversationStore.currentConversation else {
            print("⚠️ No current conversation to reload thumbnails for")
            return
        }

        guard let photoService = photoService else {
            print("⚠️ PhotoService not available for thumbnail reload")
            return
        }

        print("📋 Current conversation has \(currentConv.messages.count) messages")
        print("📋 Display messages array has \(messages.count) items")

        // Check if any messages have photoUUIDs but missing thumbnails
        Task {
            for (index, msg) in currentConv.messages.enumerated() {
                if let uuids = msg.photoUUIDs, !uuids.isEmpty {
                    print("📸 Message \(index) has \(uuids.count) photo UUIDs")

                    // Check if this message already has thumbnails loaded
                    guard index < messages.count else {
                        print("⚠️ Message index \(index) out of bounds, messages.count = \(messages.count)")
                        continue
                    }

                    let currentThumbnails = messages[index].photoThumbnails
                    let hasLoadedThumbnails = currentThumbnails?.allSatisfy { $0.image != nil } ?? false

                    print("📸 Message \(index): has \(currentThumbnails?.count ?? 0) thumbnails, all loaded: \(hasLoadedThumbnails)")

                    if !hasLoadedThumbnails {
                        print("📸 Loading thumbnails for message \(index) with \(uuids.count) photo UUIDs")

                        let thumbnails = await photoService.loadThumbnailsByUUIDs(uuids)
                        print("✅ Loaded \(thumbnails.count) thumbnails for message \(index)")

                        await MainActor.run {
                            guard index < messages.count else {
                                print("⚠️ Index out of bounds after loading")
                                return
                            }

                            print("🔍 Before update - message[\(index)].id = \(messages[index].id)")
                            print("🔍 Before update - photoThumbnails count = \(messages[index].photoThumbnails?.count ?? 0)")

                            var updatedMessage = messages[index]
                            updatedMessage.photoThumbnails = uuids.map { uuid in
                                PhotoThumbnail(uuid: uuid, image: thumbnails[uuid], description: nil)
                            }

                            print("🔍 After creating updated message - photoThumbnails count = \(updatedMessage.photoThumbnails?.count ?? 0)")
                            print("🔍 Thumbnail images loaded: \(updatedMessage.photoThumbnails?.filter { $0.image != nil }.count ?? 0)/\(updatedMessage.photoThumbnails?.count ?? 0)")

                            // Force SwiftUI to detect the change by replacing the entire array
                            var newMessages = messages
                            newMessages[index] = updatedMessage

                            // Explicitly notify SwiftUI of the change
                            objectWillChange.send()
                            messages = newMessages
                            thumbnailsVersion += 1  // Force view refresh

                            print("✅ Updated message \(index) with \(updatedMessage.photoThumbnails?.count ?? 0) thumbnails (images: \(updatedMessage.photoThumbnails?.filter { $0.image != nil }.count ?? 0))")
                            print("🔍 After messages array replacement - messages[\(index)].photoThumbnails count = \(messages[index].photoThumbnails?.count ?? 0)")
                        }
                    } else {
                        print("ℹ️ Message \(index) already has all thumbnails loaded, skipping")
                    }
                }
            }
            print("🔄 Finished reloading thumbnails")
        }
    }

    func setPromptTemplate(_ template: PromptTemplate) {
        currentPromptTemplate = template
        // Save selection to UserDefaults
        UserDefaults.standard.set(template.id.uuidString, forKey: selectedPromptTemplateKey)
        // Regenerate system message with new template
        regenerateSystemMessage()
    }

    func setMCPServer(_ server: MCPServer) {
        currentMCPServer = server
        // Save selection to UserDefaults
        UserDefaults.standard.set(server.id.uuidString, forKey: selectedMCPServerKey)

        // Create MCP client for this server
        Task {
            do {
                print("🔌 Connecting to MCP server: \(server.name) at \(server.url)")
                print("🔌 MCP endpoint path: \(server.mcpEndpointPath ?? "default(/mcp)")")
                let client = MCPClientHTTP(
                    serverURL: URL(string: server.url)!,
                    mcpEndpointPath: server.mcpEndpointPath
                )
                try await client.connect()
                let tools = try await client.getTools()
                await MainActor.run {
                    self.currentMCPClient = client
                    self.availableTools = tools.map { tool in
                        let params = tool.inputSchema.properties?.keys.joined(separator: ", ") ?? ""
                        return "- \(tool.name)(\(params))"
                    }
                    print("✅ Successfully connected to \(server.name) with \(tools.count) tools")
                    // Regenerate system message with new tools
                    regenerateSystemMessage()
                }
            } catch {
                print("❌ Failed to connect to \(server.name): \(error)")
                await MainActor.run {
                    // Clear the selected server's client on failure
                    self.currentMCPClient = nil
                    self.availableTools = []

                    // Add error message to chat
                    self.messages.append(AIChatMessage(
                        role: .system,
                        content: "⚠️ Failed to connect to MCP server '\(server.name)': \(error.localizedDescription)",
                        timestamp: Date()
                    ))
                }
            }
        }
    }

    func refreshToolsAndRegenerateSystemMessage(mcpClient: MCPClientHTTP) async {
        // Fetch tools from the MCP client and update availableTools
        do {
            let tools = try await mcpClient.getTools()
            await MainActor.run {
                self.availableTools = tools.map { tool in
                    let params = tool.inputSchema.properties?.keys.joined(separator: ", ") ?? ""
                    return "- \(tool.name)(\(params))"
                }
                print("🔄 Refreshed tools: \(self.availableTools.count) tools available")
                print("🔄 Tools list:")
                self.availableTools.forEach { print("  \($0)") }

                // Now regenerate system message with the updated tools
                regenerateSystemMessage()
                print("✅ System message regenerated with tools")
            }

            // CRITICAL: Prime the model with a warmup request to activate tool calling
            // This prevents the "cold start" issue where first request gets 0 tool calls
            await primeModelForToolCalling(mcpClient: mcpClient)

        } catch {
            print("❌ Failed to refresh tools: \(error)")
        }
    }

    /// Sends a warmup request to prime the model for tool calling
    /// This ensures the first real user request will successfully use tools
    private func primeModelForToolCalling(mcpClient: MCPClientHTTP) async {
        print("🔥 Priming model for tool calling...")

        do {
            // Get the Ollama-formatted tools
            let ollamaTools = try await mcpClient.getTools().map { tool in
                OllamaService.Tool(
                    function: OllamaService.Tool.ToolFunction(
                        name: tool.name,
                        description: tool.description,
                        parameters: OllamaService.Tool.ToolParameters(
                            properties: tool.inputSchema.properties?.mapValues { prop in
                                OllamaService.Tool.PropertySchema(
                                    type: prop.type,
                                    description: prop.description ?? ""
                                )
                            } ?? [:],
                            required: tool.inputSchema.required ?? []
                        )
                    )
                )
            }

            // Create a simple warmup conversation that won't confuse the model
            // We use a meta-question that helps the model understand its tool-calling role
            let warmupMessage = OllamaService.ChatMessage(
                role: "user",
                content: "I may ask you questions that require using the available tools. Are you ready to help?"
            )

            // Make the warmup request with tools
            let warmupHistory = conversationHistory + [warmupMessage]
            let response = try await ollamaService.chat(
                messages: warmupHistory,
                tools: ollamaTools
            )

            print("🔥 Warmup complete - model primed for tool use")
            print("🔥 Warmup response tool calls: \(response.tool_calls?.count ?? 0)")

            // Don't add the warmup exchange to the conversation history
            // This keeps the user's chat clean and prevents confusion

        } catch {
            print("⚠️ Warmup request failed (non-critical): \(error)")
            // Non-critical - if warmup fails, user can still chat normally
        }
    }

    private func regenerateSystemMessage() {
        // Remove old system message
        if !conversationHistory.isEmpty && conversationHistory.first?.role == "system" {
            conversationHistory.removeFirst()
        }

        // Generate new system message using template
        let systemContent: String
        if let template = currentPromptTemplate {
            systemContent = template.render(
                withTools: availableTools,
                mcpServerName: currentMCPServer?.name
            )
        } else {
            // Fallback to default
            systemContent = createDefaultSystemPrompt()
        }

        print("📝 Regenerated system message (length: \(systemContent.count) chars, tools count: \(availableTools.count))")

        conversationHistory.insert(OllamaService.ChatMessage(
            role: "system",
            content: systemContent
        ), at: 0)
    }

    private func setupSystemMessage() {
        // Add system instruction for tool use
        if conversationHistory.isEmpty || conversationHistory.first?.role != "system" {
            let systemContent = currentPromptTemplate?.render(
                withTools: availableTools,
                mcpServerName: currentMCPServer?.name
            ) ?? createDefaultSystemPrompt()

            conversationHistory.insert(OllamaService.ChatMessage(
                role: "system",
                content: systemContent
            ), at: 0)
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

    private func createDefaultSystemPrompt() -> String {
        return """
        You are a helpful AI assistant with access to tools via function calling.

        ABSOLUTELY CRITICAL - YOU MUST FOLLOW THESE RULES:
        1. When users ask about photos, YOU MUST USE FUNCTION CALLING to invoke the tools
        2. DO NOT write JSON or describe function calls - USE THE ACTUAL FUNCTION CALLING MECHANISM
        3. DO NOT output text like {"name":"search_photos",...} - that is WRONG
        4. DO NOT explain what you will do - JUST DO IT by calling the function
        5. NEVER say "I will search" or "Let me find" - CALL THE FUNCTION IMMEDIATELY

        You have these tools available:
        \(availableTools.joined(separator: "\n"))

        EXAMPLE OF CORRECT BEHAVIOR:
        User: "Show me beach photos"
        Assistant: [CALLS search_photos function with query="beach", n_results=10]
        [After getting results]
        Assistant: "I found 10 beach photos for you!"

        EXAMPLE OF WRONG BEHAVIOR:
        User: "Show me beach photos"
        Assistant: {"name":"search_photos","parameters":{"query":"beach"}} <- THIS IS WRONG!

        Remember: USE FUNCTION CALLING, not text descriptions of function calls.
        """
    }

    private func saveCurrentConversation() {
        guard let store = conversationStore, var current = store.currentConversation else { return }

        // Convert display messages back to storable format
        current.messages = messages.compactMap { msg -> ConversationMessage? in
            let roleString = msg.role.toString()
            return ConversationMessage(
                role: roleString,
                content: msg.content,
                photoUUIDs: msg.photoThumbnails?.map { $0.uuid },
                toolName: msg.toolName
            )
        }

        current.selectedModel = ollamaService.selectedModel
        store.updateCurrentConversation(current)
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
            print("🔧 Using MCP client: \(currentMCPClient != nil ? "Custom(\(currentMCPServer?.name ?? "unknown"))" : "Default")")
            for tool in tools {
                print("  - \(tool.function.name): \(tool.function.description)")
                print("    Parameters: \(tool.function.parameters.properties.keys.joined(separator: ", "))")
            }

            // Call Ollama with tools
            print("🤖 ========================================")
            print("🤖 Calling Ollama:")
            print("🤖   Model: \(ollamaService.selectedModel)")
            print("🤖   MCP Server: \(currentMCPServer?.name ?? "Default")")
            print("🤖   Prompt Template: \(currentPromptTemplate?.name ?? "Default")")
            print("🤖   Tools: \(tools.count)")
            print("🤖   User query: \(text)")
            print("🤖 ========================================")
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
                print("🔧 Executing tool calls...")
                let toolResults = try await executeToolCalls(toolCalls)
                print("✅ Tool execution complete, got \(toolResults.count) results")

                // Add tool results to conversation
                conversationHistory.append(response)

                // Add tool results as tool messages
                // IMPORTANT: Truncate very large tool results to prevent timeout
                let maxToolResultLength = 5000  // Max characters per tool result
                for (index, result) in toolResults.enumerated() {
                    let truncatedResult: String
                    if result.count > maxToolResultLength {
                        truncatedResult = String(result.prefix(maxToolResultLength)) + "\n...[truncated, result was \(result.count) chars]"
                        print("📝 Adding tool result \(index + 1): \(result.count) chars (truncated to \(maxToolResultLength))")
                    } else {
                        truncatedResult = result
                        print("📝 Adding tool result \(index + 1): \(result.count) chars")
                    }

                    conversationHistory.append(OllamaService.ChatMessage(
                        role: "tool",
                        content: truncatedResult
                    ))
                }

                // Get final response from LLM
                print("🤖 Requesting final summary from LLM...")
                print("🤖 Total conversation messages: \(conversationHistory.count)")
                let totalChars = conversationHistory.reduce(0) { $0 + $1.content.count }
                print("🤖 Total conversation size: \(totalChars) characters")

                let finalResponse = try await ollamaService.chat(
                    messages: conversationHistory,
                    tools: nil
                )
                print("✅ Got final response: \(String(finalResponse.content.prefix(100)))...")

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
            print("❌ Error in sendMessage: \(error)")
            print("❌ Error details: \(String(describing: error))")
            messages.append(AIChatMessage(
                role: .system,
                content: "Error: \(error.localizedDescription)",
                timestamp: Date()
            ))
        }

        // Save conversation after every message
        saveCurrentConversation()
    }

    private func getMCPTools() async throws -> [OllamaService.Tool] {
        // Use selected MCP server's client if available, otherwise fall back to default
        let clientToUse: MCPClientHTTP? = currentMCPClient ?? mcpClient

        guard let client = clientToUse, client.isConnected else {
            return []
        }

        // Get tools from MCP server
        let toolsList = try await client.listTools()

        // Convert MCP tools to Ollama tool format
        return toolsList.tools.compactMap { tool in
            // Extract parameter schema
            var properties: [String: OllamaService.Tool.PropertySchema] = [:]
            var required: [String] = []

            // Extract from typed InputSchema struct
            if let props = tool.inputSchema.properties {
                for (key, prop) in props {
                    properties[key] = OllamaService.Tool.PropertySchema(
                        type: prop.type,
                        description: prop.description ?? ""
                    )
                }
            }

            if let req = tool.inputSchema.required {
                required = req
            }

            // Enhance description with parameter examples for common tools
            var enhancedDescription = tool.description
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
        // Use selected MCP server's client if available, otherwise fall back to default
        let clientToUse: MCPClientHTTP? = currentMCPClient ?? mcpClient

        guard let mcpClient = clientToUse else {
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

    /// Load thumbnails using MCP's get_photo tool
    private func loadThumbnailsViaMCP(uuids: [String], mcpClient: MCPClientHTTP) async -> [String: NSImage] {
        var thumbnails: [String: NSImage] = [:]

        // Load thumbnails in parallel for better performance
        // Use Data instead of NSImage to satisfy Sendable requirements
        await withTaskGroup(of: (String, Data?).self) { group in
            for uuid in uuids {
                group.addTask {
                    do {
                        print("📸 Fetching photo via MCP for UUID: \(uuid)")
                        let result = try await mcpClient.callTool(
                            name: "get_photo",
                            arguments: ["uuid": uuid]
                        )

                        // Extract image data from result
                        // The MCP server returns image data as base64 or file path
                        for content in result.content {
                            if content.type == "image" {
                                // Handle base64 image data
                                if let imageData = content.data,
                                   let data = Data(base64Encoded: imageData) {
                                    print("✅ Loaded thumbnail data via MCP for \(uuid)")
                                    return (uuid, data)
                                }
                            } else if content.type == "text", let text = content.text {
                                // Handle file path response
                                if text.hasPrefix("/") || text.hasPrefix("file://") {
                                    let filePath = text.replacingOccurrences(of: "file://", with: "")
                                    if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                                        print("✅ Loaded thumbnail data from path via MCP for \(uuid)")
                                        return (uuid, data)
                                    }
                                }
                            }
                        }

                        print("⚠️ No valid image data from MCP for \(uuid)")
                        return (uuid, nil)
                    } catch {
                        print("❌ Failed to load photo via MCP for \(uuid): \(error)")
                        return (uuid, nil)
                    }
                }
            }

            for await (uuid, imageData) in group {
                if let imageData = imageData,
                   let image = NSImage(data: imageData) {
                    thumbnails[uuid] = image
                }
            }
        }

        print("✅ Loaded \(thumbnails.count)/\(uuids.count) thumbnails via MCP")
        return thumbnails
    }

    private func parseUUIDs(from text: String) -> [String] {
        var uuids: [String] = []
        var seenUUIDs = Set<String>()
        let lines = text.split(separator: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse from "Link: photos://asset?uuid=XXX" format
            if trimmed.starts(with: "Link:") && trimmed.contains("photos://asset?uuid=") {
                if let uuidRange = trimmed.range(of: "uuid=") {
                    let uuid = String(trimmed[uuidRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !uuid.isEmpty && uuid.contains("-") && uuid.count > 20 && !seenUUIDs.contains(uuid) {
                        uuids.append(uuid)
                        seenUUIDs.insert(uuid)
                        print("  ✅ Parsed UUID from Link: \(uuid)")
                    }
                }
            }
        }

        // If no UUIDs found from links, try UUID: format as fallback
        if uuids.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("UUID:") {
                    if let uuidPart = trimmed.split(separator: ":").last {
                        let uuid = String(uuidPart).trimmingCharacters(in: .whitespaces)
                        if !uuid.isEmpty && uuid.contains("-") && uuid.count > 20 && !seenUUIDs.contains(uuid) {
                            uuids.append(uuid)
                            seenUUIDs.insert(uuid)
                            print("  ✅ Parsed UUID: \(uuid)")
                        }
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

        init?(from string: String) {
            switch string {
            case "user": self = .user
            case "assistant": self = .assistant
            case "system": self = .system
            case "tool": self = .tool
            default: return nil
            }
        }

        func toString() -> String {
            switch self {
            case .user: return "user"
            case .assistant: return "assistant"
            case .system: return "system"
            case .tool: return "tool"
            }
        }
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
                    let _ = print("🎨 MessageView: Rendering \(thumbnails.count) thumbnails for message")
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
                                    // No image - show link button
                                    Button(action: {
                                        openPhoto(uuid: thumb.uuid)
                                    }) {
                                        VStack(spacing: 8) {
                                            Image(systemName: "photo.fill")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.blue)
                                            Text("Open in Photos")
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                        }
                                        .frame(height: 150)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
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
