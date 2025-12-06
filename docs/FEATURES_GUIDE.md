# VibrantFrog Complete Features Guide

This guide documents all features and capabilities of VibrantFrog, including those not covered in the README or release checklist.

## Table of Contents

1. [Prompt Template System](#prompt-template-system)
2. [Photo Library Integration](#photo-library-integration)
3. [Conversation Management](#conversation-management)
4. [MCP Server Types](#mcp-server-types)
5. [Model Selection & Persistence](#model-selection--persistence)
6. [Tool Calling Workflow](#tool-calling-workflow)
7. [Direct Tool Testing](#direct-tool-testing)
8. [Photo Indexing & Search](#photo-indexing--search)
9. [Settings & Configuration](#settings--configuration)
10. [Data Storage & Persistence](#data-storage--persistence)
11. [Logging & Debugging](#logging--debugging)
12. [Advanced Features](#advanced-features)

---

## 1. Prompt Template System

### Overview
VibrantFrog uses a sophisticated template system for system prompts with variable substitution.

### Available Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{{DATE}}` | Current date | `2025-12-06` |
| `{{TIME}}` | Current time | `14:30:00` |
| `{{DATETIME}}` | Date and time | `2025-12-06 14:30:00` |
| `{{DAY}}` | Day of week | `Friday` |
| `{{YEAR}}` | Current year | `2025` |
| `{{TOOLS}}` | Available MCP tools (auto-populated) | List of tool signatures |
| `{{MCP_SERVER}}` | Active MCP server name | `AWS Knowledge Base` |

### File Location
`VibrantFrogApp/VibrantFrog/Models/PromptTemplate.swift`

### Template Structure

```swift
struct PromptTemplate {
    let id: UUID
    var name: String
    var content: String
    var lastEdited: Date
    var isBuiltIn: Bool
}
```

### Built-in Templates

1. **AWS Helper**
   - Optimized for AWS MCP server
   - Includes AWS-specific instructions
   - Pre-configured with tool guidance

2. **Photo Search**
   - Designed for local photo indexing
   - Emphasizes visual search capabilities

3. **General Assistant**
   - Basic conversational template
   - No specialized domain knowledge

### Creating Custom Templates

**Via UI:**
1. Go to "Prompts" tab
2. Click "Add Template"
3. Name your template
4. Write content with variables
5. Save

**Template Example:**
```
You are a helpful AI assistant with access to these tools:

{{TOOLS}}

Connected to: {{MCP_SERVER}}

Current date: {{DATE}}

Use the available tools when needed to answer questions accurately.
Be concise and professional in your responses.
```

### Template Rendering

Templates are rendered when:
- Chat session starts
- MCP server changes
- Template selection changes
- Tools are refreshed

**Code Reference:**
`PromptTemplate.swift:26` - `render(withTools:mcpServerName:)` method

---

## 2. Photo Library Integration

### Overview
VibrantFrog can access, index, and search your macOS Photos library using AI-generated descriptions.

### File Location
`VibrantFrogApp/VibrantFrog/Services/PhotoLibraryService.swift`

### Features

#### Authorization
- Uses PhotoKit framework
- Requests `.readWrite` permission
- Handles all authorization states:
  - `.notDetermined` - First time
  - `.authorized` - Full access
  - `.limited` - Partial access
  - `.denied` - Rejected (opens System Settings)
  - `.restricted` - Device restrictions

#### Photo Access
```swift
// Fetch all photos
func fetchPhotos() async throws -> [Photo]

// Get specific photo by ID
func getPhoto(withID: String) async -> Photo?

// Load thumbnail
func loadThumbnail(for: PHAsset) async -> NSImage?
```

#### Photo Attachment in Chat
- Attach photos to chat messages
- Photos included in conversation context
- Thumbnails displayed inline
- Full-size image sent to LLM for analysis

**UI Location:** AI Chat view - attachment button

---

## 3. Conversation Management

### Overview
Full conversation history with persistence, search, and multi-conversation support.

### File Locations
- **Model:** `Models/Conversation.swift`
- **Service:** `Services/ConversationStore.swift`
- **View:** `Views/ConversationHistoryView.swift`

### Data Structure

```swift
struct Conversation {
    let id: UUID
    var title: String
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date

    struct Message {
        let role: String  // "user", "assistant", "tool", "system"
        let content: String
        var photoUUIDs: [String]?
        let timestamp: Date
    }
}
```

### Features

#### Auto-Save
- Conversations saved automatically after each message
- Uses UserDefaults for persistence
- JSON encoding/decoding

#### Multi-Conversation Support
- Create new conversations
- Switch between conversations
- Delete conversations
- Search across all conversations

#### Message Types

1. **User Messages** (`role: "user"`)
   - User's input
   - Can include photo attachments

2. **Assistant Messages** (`role: "assistant"`)
   - AI responses
   - Final synthesized answers

3. **Tool Messages** (`role: "tool"`)
   - Results from MCP tool execution
   - JSON or formatted text

4. **System Messages** (`role: "system"`)
   - Rendered prompt templates
   - Not displayed to user

#### Photo Attachments

Photos are stored as UUIDs referencing the Photos library:

```swift
struct Message {
    var photoUUIDs: [String]?  // Array of photo identifiers
}
```

**Loading Process:**
1. Message contains photo UUIDs
2. PhotoLibraryService fetches thumbnails
3. Thumbnails displayed in chat UI
4. Full image sent to LLM when needed

---

## 4. MCP Server Types

### Overview
VibrantFrog supports two MCP transport protocols.

### HTTP Transport (Implemented)

**File:** `Services/MCPClientHTTP.swift`

**Configuration:**
```swift
class MCPClientHTTP {
    var serverURL: String           // Base URL
    var mcpEndpointPath: String     // Endpoint path (default: "/mcp")
}
```

**Example Servers:**
- AWS Knowledge Base: `https://knowledge-mcp.global.api.aws` + `/mcp`
- Custom HTTP servers

**Protocol Methods:**
1. `POST /mcp` with `method: "initialize"` - Handshake
2. `POST /mcp` with `method: "tools/list"` - Get tools
3. `POST /mcp` with `method: "tools/call"` - Execute tool

**JSON-RPC Format:**
```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "search_aws_docs",
    "arguments": {
      "query": "Lambda functions"
    }
  },
  "id": 1
}
```

### Stdio Transport (Partial)

**File:** `Services/MCPClient.swift`

**Status:** Base implementation exists, not fully integrated

**Use Case:** Local MCP servers running as subprocess
- Python MCP servers
- Node.js MCP servers
- Custom executables

**Planned Enhancement:** Full stdio support in future release

### MCP Server Registry

**File:** `Services/MCPServerRegistry.swift`

Manages configured MCP servers:

```swift
struct MCPServer: Codable {
    let id: UUID
    var name: String
    var serverURL: String
    var mcpEndpointPath: String
    var transport: TransportType  // .http or .stdio
}
```

Persistence via UserDefaults key: `"MCPServers"`

---

## 5. Model Selection & Persistence

### Overview
Automatic model discovery from Ollama with per-tab persistence.

### File Location
`Services/OllamaService.swift`

### Model Discovery

**On App Launch:**
1. Connect to Ollama (`http://localhost:11434`)
2. Fetch available models (`GET /api/tags`)
3. Populate dropdown with models

**Model Structure:**
```swift
struct Model: Codable {
    let name: String
    let size: Int
    let modifiedAt: Date
}
```

### Model Persistence

**Per-Tab Storage:**
Each tab (AI Chat, Tool Calling) has its own model selection:

```swift
// UserDefaults keys
"SelectedModel_AIChat"      // For AI Chat tab
"SelectedModel_ToolCalling" // For Tool Calling tab
```

**Loading Behavior:**
1. App launches
2. Ollama availability checked
3. Models fetched
4. Saved model loaded for each tab
5. **Model priming happens** (see below)

### Model Priming (Cold Start Fix)

**Problem:** First request after app startup showed 0 tool calls

**Solution:** Warmup request sent after startup

**Code Location:** `Views/AIChatView.swift:650` - `primeModelForToolCalling()`

**Process:**
1. MCP server connects
2. Tools are fetched
3. System message regenerated
4. **Warmup request sent:** "Are you ready to help?"
5. Model processes request with tools
6. Warmup exchange discarded (not in history)
7. First user request now uses tools correctly

**Logging:**
```
🔥 Priming model for tool calling...
🔥 Warmup complete - model primed for tool use
🔥 Warmup response tool calls: X
```

---

## 6. Tool Calling Workflow

### Overview
Complete flow from user question to tool execution to final answer.

### File Location
`Views/AIChatView.swift` - `sendMessage()` method (line ~700)

### Step-by-Step Flow

```
1. User types message
   ↓
2. Add to conversation history (role: "user")
   ↓
3. Render system message with template
   ↓
4. Convert MCP tools to Ollama format
   ↓
5. Call OllamaService.chat(messages, tools)
   ↓
6. Ollama returns ChatMessage
   ↓
7. Check: response.tool_calls?
   ↓
   ├─ NO → Display response, done
   │
   └─ YES → Execute tools
        ↓
        8. For each tool call:
           - Extract tool name
           - Extract arguments
           - Call MCPClientHTTP.callTool()
           - Collect result
        ↓
        9. Add tool results to history (role: "tool")
        ↓
        10. **Truncate large results** (max 5000 chars)
        ↓
        11. Call OllamaService.chat() again
        ↓
        12. Display final synthesized response
```

### Tool Result Truncation

**Why:** Large tool results (10,000+ characters) cause:
- Slow LLM processing
- Timeout errors
- Memory issues

**Solution:**
```swift
let maxToolResultLength = 5000
if result.count > maxToolResultLength {
    truncatedResult = String(result.prefix(maxToolResultLength))
        + "\n...[truncated, result was \(result.count) chars]"
}
```

**Code Location:** `AIChatView.swift:620`

### Ollama Tool Format

MCP tools are converted to Ollama's format:

```swift
struct Tool {
    let type: String = "function"
    let function: ToolFunction

    struct ToolFunction {
        let name: String
        let description: String
        let parameters: ToolParameters
    }

    struct ToolParameters {
        let type: String = "object"
        let properties: [String: PropertySchema]
        let required: [String]
    }
}
```

**Code Location:** `OllamaService.swift:136`

---

## 7. Direct Tool Testing

### Overview
Developer interface for testing MCP tools directly without chat.

### File Location
`Views/DirectToolCallView.swift`

### Features

#### Tool Discovery
- Lists all available tools from connected MCP server
- Shows tool descriptions
- Displays parameter schemas

#### Dynamic Form Generation
- **File:** `Views/DynamicToolFormView.swift`
- Automatically creates input fields based on tool schema
- Supports:
  - String parameters
  - Number parameters
  - Boolean parameters
  - Required vs optional fields

#### Direct Execution
- Call tools without going through chat
- See raw tool results
- Test tool functionality
- Debug tool parameters

### Use Cases

1. **Testing MCP Servers**
   - Verify tools are accessible
   - Check parameter validation
   - See raw responses

2. **Development**
   - Test custom MCP servers
   - Debug tool implementations
   - Validate tool schemas

3. **Exploration**
   - Discover what tools do
   - Understand parameter requirements
   - See example outputs

---

## 8. Photo Indexing & Search

### Overview
AI-powered photo indexing with embedding-based semantic search.

### File Locations
- **Indexing View:** `Views/IndexingView.swift`
- **Search View:** `Views/PhotoSearchView.swift`
- **Embedding Store:** `Services/EmbeddingStore.swift`
- **LLM Service:** `Services/LLMService.swift`

### Indexing Process

#### 1. Photo Description Generation

Uses local LLM to describe photos:

```swift
func generateDescription(for photo: PHAsset) async -> String {
    // Load image
    // Send to LLM with prompt: "Describe this image in detail"
    // Return description
}
```

#### 2. Embedding Generation

Converts descriptions to vector embeddings:

```swift
func generateEmbedding(for text: String) async -> [Float] {
    // Use embedding model (384 dimensions)
    // Return vector representation
}
```

#### 3. Storage

**SQLite Database:**
```sql
CREATE TABLE photo_embeddings (
    photo_id TEXT PRIMARY KEY,
    description TEXT,
    embedding BLOB,  -- 384-dimensional vector
    indexed_at TIMESTAMP
);
```

**Location:** `~/Library/Application Support/VibrantFrog/embeddings.sqlite`

### Search Process

#### 1. Query Embedding
User query converted to same embedding space:
```swift
let queryEmbedding = await generateEmbedding(for: "sunset beach")
```

#### 2. Similarity Search
Cosine similarity against all photo embeddings:
```swift
func search(query: String, limit: Int) -> [SearchResult] {
    // Calculate cosine similarity
    // Return top N matches
    // Include similarity score
}
```

#### 3. Results Display
- Photo thumbnails
- Similarity scores
- AI descriptions
- Click to view full size

### Supported Features

- **Semantic Search:** "beach sunset" finds photos even if not tagged
- **Batch Indexing:** Process entire library
- **Incremental Updates:** Index only new photos
- **Fast Retrieval:** SQLite + vector indexing

---

## 9. Settings & Configuration

### File Location
`Views/SettingsView.swift`

### Available Settings

#### Ollama Configuration
- **Base URL:** Default `http://localhost:11434`
- **Timeout:** Request timeout (default: 120s)
- **Custom parameters:** Temperature, top-p, etc.

#### MCP Settings
- **Default Server:** Auto-connect on startup
- **Endpoint Paths:** Custom paths for servers
- **Transport Type:** HTTP vs stdio

#### Photo Library
- **Authorization Status:** View current permission
- **Indexing Options:** Auto-index, batch size
- **Storage Location:** Database path

#### UI Preferences
- **Theme:** Light/Dark/Auto (future)
- **Font Size:** Chat text size (future)
- **Notifications:** Enable/disable (future)

### Persistence

All settings stored in UserDefaults:
```swift
UserDefaults.standard.string(forKey: "OllamaBaseURL")
UserDefaults.standard.string(forKey: "DefaultMCPServer")
UserDefaults.standard.integer(forKey: "RequestTimeout")
```

---

## 10. Data Storage & Persistence

### Overview
VibrantFrog stores data in multiple locations.

### Storage Locations

#### 1. UserDefaults
**Path:** `~/Library/Preferences/com.spiderink.vibrantfrog.plist`

**Stored Data:**
- Model selections per tab
- MCP server configurations
- Prompt templates
- Conversations
- App settings

#### 2. Application Support
**Path:** `~/Library/Application Support/VibrantFrog/`

**Contents:**
- `embeddings.sqlite` - Photo embeddings database
- `conversations/` - Conversation backups (future)
- `logs/` - Debug logs (future)

#### 3. Temporary Files
**Path:** `~/Library/Caches/VibrantFrog/`

**Contents:**
- Photo thumbnails (in-memory, not persisted)
- Download cache (future)

### Data Models

#### Conversations
```swift
// Stored as JSON array in UserDefaults
let conversations: [Conversation]
UserDefaults.standard.set(encoded, forKey: "Conversations")
```

#### MCP Servers
```swift
// Stored as JSON array in UserDefaults
let servers: [MCPServer]
UserDefaults.standard.set(encoded, forKey: "MCPServers")
```

#### Prompt Templates
```swift
// Stored as JSON array in UserDefaults
let templates: [PromptTemplate]
UserDefaults.standard.set(encoded, forKey: "PromptTemplates")
```

### Backup & Export

**Manual Backup:**
```bash
# UserDefaults
defaults export com.spiderink.vibrantfrog ~/vibrantfrog-backup.plist

# Application Support
cp -r ~/Library/Application\ Support/VibrantFrog ~/vibrantfrog-appdata-backup
```

**Restore:**
```bash
# UserDefaults
defaults import com.spiderink.vibrantfrog ~/vibrantfrog-backup.plist

# Application Support
cp -r ~/vibrantfrog-appdata-backup ~/Library/Application\ Support/VibrantFrog
```

---

## 11. Logging & Debugging

### Logging Strategy

VibrantFrog uses emoji-prefixed logging for easy filtering:

| Emoji | Category | Example |
|-------|----------|---------|
| 🔄 | Process/Action | `🔄 Loading model...` |
| ✅ | Success | `✅ Model loaded successfully` |
| ❌ | Error | `❌ Failed to load model: error` |
| ⚠️ | Warning | `⚠️ Model not found, using default` |
| 🔥 | Special/Critical | `🔥 Priming model for tool calling` |
| 🤖 | AI/LLM | `🤖 Calling Ollama with 5 tools` |
| 🔧 | Tool Calling | `🔧 Executing tool: search_aws_docs` |
| 📸 | Photo Library | `📸 Requesting photo authorization` |
| 🚀 | Network | `🚀 Making request to Ollama` |

### Viewing Logs

**Xcode Console:**
- Run app in Xcode
- View console output
- Filter by emoji: `🤖` for AI operations

**Console.app:**
1. Open Console.app
2. Filter: "VibrantFrog" or process name
3. Search by emoji category
4. Export logs for debugging

### Debug Mode

Enable verbose logging (future feature):
```swift
UserDefaults.standard.set(true, forKey: "DebugMode")
```

### Common Log Patterns

**App Startup:**
```
🔄 Loading saved model...
✅ Model loaded: mistral-nemo:latest
🔄 Refreshed tools: 5 tools available
🔥 Priming model for tool calling...
🔥 Warmup complete - model primed for tool use
```

**Chat Request:**
```
🤖 Calling Ollama:
🤖   Model: mistral-nemo:latest
🤖   MCP Server: AWS Knowledge Base
🤖   Tools: 5
🚀 Making request to Ollama...
🤖 Tool calls: 1
🔧 Executing tool: search_aws_docs
✅ Tool result: 1234 chars
🤖 Requesting final summary...
✅ Chat complete
```

**Errors:**
```
❌ Failed to connect to MCP server: timeout
❌ Ollama not available: connection refused
❌ Tool execution failed: invalid parameters
```

---

## 12. Advanced Features

### Custom URLSession Configuration

**File:** `OllamaService.swift:33`

Extended timeouts for LLM responses:
```swift
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 120   // 2 minutes
config.timeoutIntervalForResource = 300  // 5 minutes
```

**Why:** LLM responses with tool calling can take 30-60+ seconds

### Async/Await Patterns

All network operations use Swift structured concurrency:
```swift
Task {
    do {
        let response = try await ollamaService.chat(
            messages: conversationHistory,
            tools: ollamaTools
        )
        await MainActor.run {
            self.messages.append(response)
        }
    } catch {
        print("❌ Error: \(error)")
    }
}
```

### Main Actor Isolation

UI updates guaranteed on main thread:
```swift
@MainActor
class AIChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    // All methods run on main thread
}
```

### Photo Thumbnail Caching

**In-Memory Cache:**
```swift
private var thumbnailCache: [String: NSImage] = [:]

func getThumbnail(for photoID: String) -> NSImage? {
    if let cached = thumbnailCache[photoID] {
        return cached
    }
    // Load and cache
}
```

**Benefits:**
- Faster display
- Reduces Photos framework calls
- Lower memory than full images

### Conversation Size Management

**Large Conversations:**
- Monitor total token count (future)
- Implement sliding window (future)
- Truncate old messages (future)

**Current:** Tool results truncated to 5000 chars

---

## Feature Comparison Matrix

| Feature | Status | File Location |
|---------|--------|---------------|
| AI Chat | ✅ Implemented | `Views/AIChatView.swift` |
| MCP HTTP | ✅ Implemented | `Services/MCPClientHTTP.swift` |
| MCP Stdio | ⏳ Partial | `Services/MCPClient.swift` |
| Tool Calling | ✅ Implemented | `AIChatView.swift:700` |
| Model Priming | ✅ Implemented | `AIChatView.swift:650` |
| Conversations | ✅ Implemented | `Services/ConversationStore.swift` |
| Photo Attachments | ✅ Implemented | Photo integration |
| Photo Indexing | ✅ Implemented | `Views/IndexingView.swift` |
| Photo Search | ✅ Implemented | `Views/PhotoSearchView.swift` |
| Prompt Templates | ✅ Implemented | `Models/PromptTemplate.swift` |
| Direct Tool Testing | ✅ Implemented | `Views/DirectToolCallView.swift` |
| Streaming | ❌ Not implemented | Future |
| Custom Parameters | ❌ Not implemented | Future |
| Export Conversations | ❌ Not implemented | Future |
| Multi-platform | ❌ macOS only | Future |

---

## Quick Reference

### Important Code Locations

```
Model Priming:      AIChatView.swift:650
Tool Calling:       AIChatView.swift:700
Tool Truncation:    AIChatView.swift:620
System Message:     AIChatView.swift:643
MCP HTTP Client:    MCPClientHTTP.swift
Ollama Service:     OllamaService.swift
Template System:    PromptTemplate.swift:26
Photo Service:      PhotoLibraryService.swift
Embedding Store:    EmbeddingStore.swift
Conversation Store: ConversationStore.swift
```

### UserDefaults Keys

```swift
"SelectedModel_AIChat"          // Current model for AI Chat tab
"MCPServers"                    // Array of configured servers
"PromptTemplates"               // Array of prompt templates
"Conversations"                 // Array of saved conversations
"OllamaBaseURL"                 // Ollama service URL
"DefaultMCPServer"              // Auto-connect server ID
```

### File Paths

```
Embeddings DB:    ~/Library/Application Support/VibrantFrog/embeddings.sqlite
UserDefaults:     ~/Library/Preferences/com.spiderink.vibrantfrog.plist
Cache:            ~/Library/Caches/VibrantFrog/
```

---

This guide covers all major features and implementation details not included in the README or release checklist. Refer to specific file locations for code references.
