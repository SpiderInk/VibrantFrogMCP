# VibrantFrog Architecture

This document describes the technical architecture of VibrantFrog, a macOS AI chat application with MCP integration.

## Overview

VibrantFrog is built using **SwiftUI** with an **MVVM** (Model-View-ViewModel) architecture pattern. The app is designed to be modular, testable, and maintainable.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     User Interface                      │
│                    (SwiftUI Views)                      │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────────────────────┐
│                   View Models                           │
│           (@Published, @StateObject)                    │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────────────────────┐
│                  Service Layer                          │
│  ┌──────────────┬──────────────┬─────────────────┐      │
│  │ Ollama       │ MCP Client   │ Conversation    │      │
│  │ Service      │ HTTP         │ Store           │      │
│  └──────────────┴──────────────┴─────────────────┘      │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────────────────────┐
│              External Systems                           │
│  ┌──────────────┬──────────────┬─────────────────┐      │
│  │ Ollama API   │ MCP Servers  │ UserDefaults    │      │
│  │ (localhost)  │ (HTTP/stdio) │ (Persistence)   │      │
│  └──────────────┴──────────────┴─────────────────┘      │
└─────────────────────────────────────────────────────────┘
```

## Directory Structure

```
VibrantFrog/
├── VibrantFrogApp.swift        # App entry point
├── ContentView.swift            # Main navigation container
│
├── Models/                      # Data models
│   ├── Conversation.swift       # Chat conversation + messages
│   ├── Photo.swift              # Photo library model
│   └── PromptTemplate.swift     # System prompt templates
│
├── Views/                       # SwiftUI views
│   ├── AIChatView.swift         # Main chat interface + ViewModel
│   ├── ConversationHistoryView.swift  # Past conversations
│   ├── PromptTemplatesView.swift      # Template management
│   ├── MCPManagementView.swift        # MCP server config
│   ├── DirectToolCallView.swift       # Tool testing UI
│   ├── IndexingView.swift             # Photo indexing
│   ├── SettingsView.swift             # App settings
│   ├── PhotoGridView.swift            # Photo gallery
│   ├── PhotoSearchView.swift          # Photo search interface
│   └── DynamicToolFormView.swift      # Dynamic tool parameter form
│
├── Services/                    # Business logic layer
│   ├── OllamaService.swift      # Ollama API client
│   ├── MCPClientHTTP.swift      # MCP protocol (HTTP)
│   ├── MCPClient.swift          # MCP protocol (stdio)
│   ├── MCPServerRegistry.swift  # Server management
│   ├── ConversationStore.swift  # Conversation persistence
│   ├── PromptTemplateStore.swift # Template persistence
│   ├── PhotoLibraryService.swift # Photos framework integration
│   ├── LLMService.swift         # LLM abstraction layer
│   ├── EmbeddingStore.swift     # Vector embeddings
│   └── LibLlama.swift           # llama.cpp bridge (legacy)
│
└── Assets.xcassets/             # Images, icons, colors
```

## Core Components

### 1. Views Layer

#### AIChatView
The primary chat interface.

**Responsibilities:**
- Display chat messages with user/assistant/tool roles
- Handle user input and send to Ollama
- Manage conversation history
- Execute MCP tool calls
- Display tool results and responses

**Key Features:**
- Model selection dropdown (persisted per tab)
- MCP server selection
- Prompt template selection
- Photo attachment support
- Real-time message streaming (planned)

**State Management:**
```swift
@StateObject private var ollamaService = OllamaService()
@StateObject private var conversationStore: ConversationStore
@EnvironmentObject var mcpClient: MCPClientHTTP

@State private var conversationHistory: [OllamaService.ChatMessage] = []
@State private var currentPromptTemplate: PromptTemplate?
@State private var currentMCPServer: MCPServer?
```

#### MCPManagementView
MCP server configuration interface.

**Features:**
- Add/edit/delete MCP servers
- Test connections
- View available tools
- Configure custom endpoint paths

### 2. Services Layer

#### OllamaService
Handles all communication with the Ollama API.

**Key Methods:**
```swift
class OllamaService: ObservableObject {
    @Published var availableModels: [Model] = []
    @Published var selectedModel: String = "mistral-nemo:latest"

    /// Fetch available models from Ollama
    func checkAvailability() async

    /// Send chat message with optional tool support
    func chat(messages: [ChatMessage], tools: [Tool]?) async throws -> ChatMessage

    /// Generate text completion
    func complete(prompt: String) async throws -> String
}
```

**Tool Calling Flow:**
1. Receive user message
2. Add to conversation history
3. Call `chat()` with available MCP tools
4. If response contains `tool_calls`:
   - Execute each tool via MCPClient
   - Add tool results to conversation
   - Call `chat()` again for final response
5. Display final response

**Custom Configuration:**
- Extended timeouts (120s request, 300s resource)
- Temperature: 0.3 (optimized for tool calling)
- Non-streaming mode (streaming planned)

#### MCPClientHTTP
Implements the Model Context Protocol over HTTP.

**Protocol Methods:**
```swift
class MCPClientHTTP: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var serverURL: String
    @Published var mcpEndpointPath: String = "/mcp"

    /// Initialize connection to MCP server
    func connect() async throws

    /// Fetch available tools
    func getTools() async throws -> [MCPTool]

    /// Execute a tool
    func callTool(name: String, parameters: [String: Any]) async throws -> String
}
```

**Request Flow:**
```
1. initialize → Handshake with server
2. tools/list → Discover available tools
3. tools/call → Execute specific tool
```

**Error Handling:**
- Connection timeouts
- Invalid JSON responses
- Tool execution errors
- Server unavailability

#### ConversationStore
Manages conversation persistence using UserDefaults.

**Features:**
- Save/load conversations
- Multi-conversation support
- Photo attachment persistence (UUIDs)
- Search and filtering

**Data Model:**
```swift
struct Conversation: Codable, Identifiable {
    let id: UUID
    var title: String
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date

    struct Message: Codable {
        let role: String  // "user", "assistant", "tool"
        let content: String
        var photoUUIDs: [String]?
        let timestamp: Date
    }
}
```

#### PromptTemplateStore
Manages system prompt templates.

**Template Variables:**
- `{{TOOLS}}` - Replaced with formatted tool descriptions
- `{{MCP_SERVER_NAME}}` - Replaced with current server name

**Default Templates:**
- **AWS Helper** - Optimized for AWS MCP server
- **Photo Search** - For local photo indexing
- **General Assistant** - Basic conversational template

### 3. Models Layer

#### Conversation
Represents a chat conversation with messages.

**Key Properties:**
```swift
struct Conversation {
    let id: UUID
    var title: String
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date
}
```

#### PromptTemplate
System prompt template with variables.

**Structure:**
```swift
struct PromptTemplate: Codable, Identifiable {
    let id: UUID
    var name: String
    var content: String
    var isDefault: Bool

    func render(withTools: [String], mcpServerName: String?) -> String {
        // Replace {{TOOLS}} and {{MCP_SERVER_NAME}}
    }
}
```

#### Photo
Represents a photo from the library.

**Integration:**
- Uses Photos framework for access
- Stores thumbnails in-memory
- Embeds photo data for AI analysis

## Data Flow

### Chat Message Flow

```
User Types Message
       ↓
AIChatView captures input
       ↓
Add to conversationHistory
       ↓
Render system prompt with template
       ↓
OllamaService.chat(messages, tools)
       ↓
┌──────────────────────────┐
│  Ollama API              │
│  Returns ChatMessage     │
│  with tool_calls?        │
└──────────────────────────┘
       ↓
   Has tool_calls?
    ↙         ↘
  Yes          No
   ↓            ↓
Execute     Display
tools      response
   ↓
MCPClientHTTP.callTool()
   ↓
Add tool results to history
   ↓
OllamaService.chat() again
   ↓
Display final response
```

### Model Priming Flow (Cold Start Fix)

```
App Startup
     ↓
OllamaService.checkAvailability()
     ↓
Load saved model
     ↓
Toggle model selection to activate Picker binding
     ↓
Auto-connect to MCP server
     ↓
Fetch tools from MCP
     ↓
Regenerate system message with tool descriptions
     ↓
🔥 PRIME MODEL with warmup request
     ↓
Send meta-question: "Are you ready to help?"
     ↓
Model processes request with tools
     ↓
Discard warmup exchange (not added to history)
     ↓
✅ First user request now uses tools correctly
```

## Key Design Decisions

### 1. Why MVVM?
- **Separation of concerns** - Views don't contain business logic
- **Testability** - ViewModels can be tested independently
- **SwiftUI integration** - `@Published` properties drive UI updates
- **Maintainability** - Clear boundaries between layers

### 2. Why ObservableObject for Services?
Services like `OllamaService` use `ObservableObject` because:
- State needs to be shared across multiple views
- Changes should trigger UI updates
- Single source of truth for model selection, availability, etc.

### 3. Why UserDefaults for Persistence?
- **Simplicity** - No need for Core Data for current scale
- **Performance** - Fast enough for conversation history
- **Migration path** - Can move to Core Data/SQLite later if needed

### 4. Why Extended Timeouts?
LLM responses, especially with tool calling, can take 30-60+ seconds:
- Request timeout: 120s (2 minutes)
- Resource timeout: 300s (5 minutes)
- Prevents premature cancellation of valid requests

### 5. Why Model Priming?
Without priming, the first request after app startup shows 0 tool calls even though:
- Model is correctly selected
- Tools are in system prompt
- Everything appears configured

**Root Cause:** The LLM needs to "see" a tool-capable conversation before it reliably uses tools.

**Solution:** Send invisible warmup request after startup to prime the model.

## Concurrency Model

### Async/Await Pattern

All network operations use Swift's structured concurrency:

```swift
// Service methods are async
func chat(messages: [ChatMessage], tools: [Tool]?) async throws -> ChatMessage

// Called from views with Task
Task {
    do {
        let response = try await ollamaService.chat(
            messages: conversationHistory,
            tools: ollamaTools
        )
        // Update UI on main thread
        await MainActor.run {
            self.messages.append(response)
        }
    } catch {
        print("❌ Error: \(error)")
    }
}
```

### Main Actor Isolation

UI updates must run on the main thread:

```swift
@MainActor
class AIChatViewModel: ObservableObject {
    @Published var messages: [Message] = []

    func sendMessage() async {
        // Can safely update @Published properties
        self.messages.append(newMessage)
    }
}
```

## Performance Considerations

### 1. Tool Result Truncation
Large tool results (10,000+ chars) slow down LLM processing:
```swift
let maxToolResultLength = 5000
if result.count > maxToolResultLength {
    truncatedResult = String(result.prefix(maxToolResultLength))
        + "\n...[truncated]"
}
```

### 2. Lazy Loading
- Photo thumbnails loaded on-demand
- Conversation history loaded only when requested
- Models fetched once at startup

### 3. Caching
- Available models cached after first fetch
- MCP tools cached until server changes
- Templates cached in PromptTemplateStore

## Security Considerations

### 1. Local-First Architecture
- All processing happens locally
- No data sent to external servers (except configured MCP servers)
- Ollama runs on localhost:11434

### 2. MCP Server Trust
- Users explicitly configure MCP servers
- HTTPS enforced for remote servers
- Tool execution results are sandboxed

### 3. Photo Library Access
- Requires explicit user permission
- Only accesses photos user selects
- Thumbnails stored in-memory only

## Testing Strategy

### Unit Tests
- Service layer logic
- Model serialization/deserialization
- Template rendering

### Integration Tests
- Ollama API communication
- MCP protocol compliance
- Conversation persistence

### Manual Testing
- UI interactions
- Tool calling workflows
- Error handling
- Performance under load

## Future Enhancements

### Planned Architecture Changes

1. **Streaming Responses**
   - Add SSE (Server-Sent Events) support
   - Update OllamaService for streaming
   - Modify ChatView for real-time updates

2. **Core Data Migration**
   - Move from UserDefaults to Core Data
   - Better query performance
   - Support for larger conversation histories

3. **Plugin System**
   - Dynamic MCP server plugins
   - User-installable tool extensions
   - Sandboxed execution environment

4. **Cross-Platform Support**
   - Extract business logic to shared module
   - Platform-specific UI layers (iOS, Linux)
   - Unified Swift package

## Debugging

### Logging Strategy

VibrantFrog uses emoji-prefixed logging for easy filtering:

```swift
print("🔄 Loading...")      // Process/action
print("✅ Success")          // Success
print("❌ Error: \(error)")  // Error
print("⚠️ Warning")          // Warning
print("🔥 Special operation") // Important/special
print("🤖 AI operation")     // LLM/AI related
print("🔧 Tool execution")   // MCP tool calling
```

### Console.app Filtering

Filter by emoji to track specific operations:
- Search: `🤖` for AI chat operations
- Search: `🔧` for tool calling
- Search: `❌` for errors

### Common Issues

1. **Tool calls: 0**
   - Check model supports function calling
   - Verify MCP server is connected
   - Ensure system prompt includes `{{TOOLS}}`

2. **Timeout errors**
   - Check Ollama is running
   - Verify model is downloaded
   - Monitor resource usage (RAM, CPU)

3. **Model not persisting**
   - Verify UserDefaults key is correct
   - Check model exists in availableModels
   - Look for binding toggle in logs

---

**Last Updated:** 2025-12-05
**Version:** 1.0
**Author:** SpiderInk / Tony Piazza
