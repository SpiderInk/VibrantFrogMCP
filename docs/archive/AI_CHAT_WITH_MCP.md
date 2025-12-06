# AI Chat with MCP Tools - VibrantFrog

## What is This?

This is a **real AI chat interface** that uses **Ollama LLM** with **MCP (Model Context Protocol)** tool calling to search and manage your photos.

### Architecture

```
User: "Show me beach photos"
    ↓
Ollama LLM (gemma3:4b or llava:7b)
    ↓
    Decides: Need to call search_photos tool
    ↓
MCP Server (Python)
    ↓
ChromaDB Vector Search
    ↓
Results returned to LLM
    ↓
LLM: "I found 12 beach photos for you:"
    ↓
Displayed in Chat UI with thumbnails
```

## Components

### 1. OllamaService.swift
- Connects to Ollama API (`http://127.0.0.1:11434`)
- Supports tool calling (function calling)
- Manages conversation with LLM
- Converts MCP tools to Ollama tool format

### 2. AIChatView.swift
- SwiftUI chat interface
- Message history (user, assistant, system, tool)
- Real-time conversation
- Tool execution display

### 3. MCPServerRegistry.swift
- Manages multiple MCP servers
- Persists server list in UserDefaults
- Allows users to add/remove MCP servers
- Default: VibrantFrog Photos server at `http://127.0.0.1:5050/mcp`

### 4. MCPClientHTTP.swift (Updated)
- Now accepts custom server URLs
- Connects to any MCP server
- Supports Streamable HTTP transport

## How It Works

### Flow:

1. **User types message:** "Show me beach photos"

2. **App sends to Ollama** with available MCP tools:
   ```json
   {
     "model": "gemma3:4b",
     "messages": [
       {"role": "user", "content": "Show me beach photos"}
     ],
     "tools": [
       {
         "type": "function",
         "function": {
           "name": "search_photos",
           "description": "Search photos by query",
           "parameters": {
             "type": "object",
             "properties": {
               "query": {
                 "type": "string",
                 "description": "Search query"
               },
               "n_results": {
                 "type": "integer",
                 "description": "Number of results"
               }
             },
             "required": ["query"]
           }
         }
       }
     ]
   }
   ```

3. **Ollama decides** to call tool:
   ```json
   {
     "message": {
       "role": "assistant",
       "content": "",
       "tool_calls": [
         {
           "function": {
             "name": "search_photos",
             "arguments": {
               "query": "beach",
               "n_results": 10
             }
           }
         }
       ]
     }
   }
   ```

4. **App executes MCP tool** via HTTP:
   ```http
   POST http://127.0.0.1:5050/mcp
   Content-Type: application/json

   {
     "jsonrpc": "2.0",
     "id": 1,
     "method": "tools/call",
     "params": {
       "name": "search_photos",
       "arguments": {
         "query": "beach",
         "n_results": 10
       }
     }
   }
   ```

5. **MCP server returns results:**
   ```json
   {
     "result": {
       "content": [
         {
           "type": "text",
           "text": "1. beach_sunset.jpg\n   UUID: ABC-123\n   Relevance: 0.95\n..."
         }
       ]
     }
   }
   ```

6. **App sends tool result back to Ollama:**
   ```json
   {
     "messages": [
       {"role": "user", "content": "Show me beach photos"},
       {
         "role": "assistant",
         "tool_calls": [...]
       },
       {
         "role": "tool",
         "content": "1. beach_sunset.jpg\nUUID: ABC-123..."
       }
     ]
   }
   ```

7. **Ollama generates natural response:**
   ```
   "I found 12 beautiful beach photos for you! Here are the results..."
   ```

8. **App displays** response + photo thumbnails in chat

## Setup

### 1. Start Ollama

```bash
# Install Ollama if needed
brew install ollama

# Start Ollama service
ollama serve

# Pull a model (choose one)
ollama pull gemma3:4b    # Fast, good for chat
ollama pull llava:7b     # Vision model (for image analysis)
```

### 2. Start MCP Server

```bash
cd /Users/tpiazza/git/VibrantFrogMCP
./restart_http_server.sh
```

Verify server is running:
```bash
curl http://127.0.0.1:5050/mcp
```

### 3. Run VibrantFrog App

```bash
cd VibrantFrogApp
open VibrantFrog.xcodeproj
```

Press Cmd+R to run the app.

### 4. Try It Out

1. Open **AI Chat** tab (brain icon)
2. Wait for "Ollama available" and "MCP Connected" indicators
3. Type: "Show me beach photos"
4. Watch the magic happen!

## Adding More MCP Servers

### In the App:

1. Go to **Settings** tab
2. Click **"Add MCP Server"**
3. Enter:
   - Name: "My Custom MCP"
   - URL: "http://127.0.0.1:8080/mcp"
4. Click **Add**
5. Server tools will be available in AI Chat

### Example: Adding Weather MCP

```bash
# Clone MCP weather server
git clone https://github.com/modelcontextprotocol/servers
cd servers/weather
npm install
npm start  # Runs on http://127.0.0.1:8080/mcp
```

In VibrantFrog:
- Add server with URL `http://127.0.0.1:8080/mcp`
- Now you can ask: "Show me beach photos and what's the weather like today?"

## Tool Calling Examples

### Search Photos
**User:** "Find photos of sunsets"

**LLM calls:**
```
search_photos(query="sunset", n_results=10)
```

### Create Album
**User:** "Create an album called 'Summer 2024' from beach photos"

**LLM calls:**
```
search_photos(query="beach", n_results=50)
create_album_from_search(album_name="Summer 2024", query="beach")
```

### List Albums
**User:** "What albums do I have?"

**LLM calls:**
```
list_albums()
```

## Current Tabs

### 1. AI Chat (Main)
- Real Ollama LLM with MCP tools
- Natural conversation
- Automatic tool calling
- Photo thumbnails

### 2. Simple Chat
- Direct MCP tool calls (no LLM)
- Keyword-based intent detection
- Faster but less conversational

### 3. MCP Server
- Test MCP connection
- View available tools
- Manual tool execution

### 4. Search
- Direct photo search UI
- No chat interface

### 5. Indexing
- Index photos with LLaVA descriptions
- View indexing progress

### 6. Settings
- Manage MCP servers
- Configure Ollama model
- App preferences

## Differences from Simple Chat

| Feature | AI Chat | Simple Chat |
|---------|---------|-------------|
| LLM | Ollama (real AI) | None (keyword matching) |
| Understanding | Natural language | Pattern matching |
| Responses | Conversational | Template-based |
| Tool Calling | Automatic | Manual intent detection |
| Cost | Free (local) | Free |
| Speed | ~2-3 seconds | Instant |

## Troubleshooting

### "Ollama not available"
```bash
# Check if Ollama is running
pgrep ollama

# If not, start it
ollama serve

# Check available models
ollama list

# Pull a model if needed
ollama pull gemma3:4b
```

### "MCP Disconnected"
```bash
# Check if server is running
lsof -i :5050

# Restart server
cd /Users/tpiazza/git/VibrantFrogMCP
./restart_http_server.sh

# Test connection
curl http://127.0.0.1:5050/mcp
```

### LLM not calling tools
- Make sure MCP server has tools listed
- Check tool schema has proper descriptions
- Try simpler query: "search for beach"
- Check console for errors

### Slow responses
- gemma3:4b is faster than llava:7b
- First response may be slow (model loading)
- Subsequent responses are faster

## Next Steps

### Phase 1: Photo Thumbnails ✅
- Parse UUIDs from search results
- Load thumbnails from PhotoKit
- Display in chat

### Phase 2: Multiple MCP Servers ✅
- Server registry
- Add/remove servers
- Aggregate tools from all servers

### Phase 3: Advanced Features
- Conversation history persistence
- Photo detail modal
- Batch operations
- Smart suggestions

### Phase 4: Vision Features
- Use LLaVA to analyze photos in chat
- Ask questions about specific photos
- Generate captions

## Code Structure

```
VibrantFrogApp/
├── Services/
│   ├── OllamaService.swift        # Ollama API client
│   ├── MCPClientHTTP.swift        # MCP client (updated)
│   ├── MCPServerRegistry.swift    # Multi-server support
│   └── PhotoLibraryService.swift  # PhotoKit integration
├── Views/
│   ├── AIChatView.swift           # NEW: AI chat interface
│   ├── ChatView.swift             # Simple chat (kept for comparison)
│   ├── MCPTestView.swift          # MCP debugging
│   └── ContentView.swift          # Main navigation
└── Models/
    └── (Chat message models in AIChatView.swift)
```

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Ollama installed and running
- Python 3.x (for MCP server)
- ChromaDB indexed photos

## Resources

- [Ollama](https://ollama.ai)
- [MCP Specification](https://spec.modelcontextprotocol.io)
- [VibrantFrog MCP Server](../vibrant_frog_mcp.py)

---

**You now have a real AI assistant for your photos!** 🎉
