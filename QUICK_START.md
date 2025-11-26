# VibrantFrog MCP - Quick Start Guide

## What We Fixed

Your MCP server and Swift app now use the **correct Streamable HTTP transport** as specified in MCP 2025-03-26.

### Before → After

- ❌ **Before:** SSE transport with `/messages` endpoint (deprecated)
- ✅ **After:** Streamable HTTP with `/mcp` endpoint (current spec)

---

## Quick Test (5 minutes)

### Terminal 1: Start MCP Server

```bash
cd /Users/tpiazza/git/VibrantFrogMCP
python3 vibrant_frog_mcp.py --transport http
```

**You should see:**
```
Starting MCP server in Streamable HTTP mode on 127.0.0.1:5050...
INFO:     Uvicorn running on http://127.0.0.1:5050
```

### Terminal 2: Test the Connection

```bash
cd /Users/tpiazza/git/VibrantFrogMCP
python3 test_mcp_http.py
```

**You should see:**
```
✅ Session ID received: <uuid>
✅ Found 10 tools
✅ Tool executed successfully
```

### Xcode: Test Swift App

1. Open `VibrantFrogApp/VibrantFrog.xcodeproj`
2. Run the app
3. Navigate to MCP Test view
4. Click "Connect to MCP Server"
5. Should connect and show tools list

---

## Key Files Changed

1. **`vibrant_frog_mcp.py`** (lines 527-690)
   - Now uses `/mcp` endpoint with Streamable HTTP

2. **`VibrantFrogApp/.../MCPClientHTTP.swift`** (completely rewritten)
   - Simple HTTP POST client
   - No more SSE complexity

3. **`test_mcp_http.py`** (new)
   - Python test script

4. **`MCP_HTTP_FIXES.md`** (new)
   - Detailed documentation

---

## MCP Endpoint Summary

### Single Endpoint: `/mcp`

**Initialize:**
```bash
curl -X POST http://localhost:5050/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": {"name": "test", "version": "1.0"}
    }
  }'
```

**List Tools:**
```bash
curl -X POST http://localhost:5050/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: <session-id-from-initialize>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }'
```

**Search Photos:**
```bash
curl -X POST http://localhost:5050/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: <session-id>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "search_photos",
      "arguments": {
        "query": "sunset",
        "n_results": 5
      }
    }
  }'
```

---

## What's Next

### Integration with VibrantFrog App

The MCP client is ready. Now you need to:

1. **Wire up the chat interface** to use `MCPClientHTTP`
2. **Add tool result rendering** in the chat UI
3. **Handle image responses** from `get_photo` tool

### Example Integration

```swift
// In your ChatView or similar
@StateObject private var mcpClient = MCPClientHTTP()

// On app launch
.task {
    do {
        try await mcpClient.connect()
    } catch {
        print("Failed to connect to MCP server: \(error)")
    }
}

// When user asks to search
let result = try await mcpClient.callTool(
    name: "search_photos",
    arguments: ["query": userQuery, "n_results": 10]
)

// Display results
for content in result.content {
    if let text = content.text {
        // Show text result
    }
}
```

---

## Troubleshooting

### "Connection refused"
- Server not running → Start with `python3 vibrant_frog_mcp.py --transport http`
- Port in use → Try different port with `--port 5051`

### "Session not found"
- Not including session ID → Check that `Mcp-Session-Id` header is set
- Server restarted → Reinitialize connection

### "Method not found"
- Wrong method name → Check available methods: `initialize`, `tools/list`, `tools/call`
- Typo in tool name → Use exact names from `tools/list`

---

## Architecture

```
VibrantFrog.app (Swift)
    │
    │ MCPClientHTTP
    │ ├─ POST /mcp (initialize) → get session ID
    │ ├─ POST /mcp (tools/list) → get tools
    │ └─ POST /mcp (tools/call) → execute tools
    │
    ▼
Python MCP Server (port 5050)
    │
    │ Streamable HTTP transport
    │ ├─ /mcp endpoint
    │ ├─ Session management
    │ └─ 10 photo tools
    │
    ▼
Apple Photos Library
    │
    ├─ PhotoKit access
    ├─ ChromaDB vector search
    └─ LLaVA image analysis
```

---

## Available Tools

1. **search_photos** - Natural language search
2. **get_photo** - Get photo by UUID (returns image)
3. **create_album** - Create empty album
4. **delete_album** - Delete album
5. **list_albums** - List all albums
6. **add_photos_to_album** - Add photos to album
7. **remove_photos_from_album** - Remove from album
8. **create_album_from_search** - Search + create album
9. **index_photo** - Index single photo
10. **index_directory** - Index all photos in folder

---

## Status

✅ **Transport layer:** Fixed and working
✅ **MCP protocol:** Compliant with 2025-03-26 spec
✅ **Python server:** Streamable HTTP implemented
✅ **Swift client:** Simplified and working
✅ **Test script:** Validates connection
🔲 **Chat integration:** Next step
🔲 **UI polish:** Next step

---

**You're now ready to build the chat interface!**

The hard part (transport/protocol) is done. Now you can focus on the user experience.
