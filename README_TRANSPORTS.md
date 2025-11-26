# VibrantFrog MCP - Transport Guide

## Quick Answer

**Your server supports BOTH transports with ONE codebase!**

```bash
# For MCP Inspector + Swift App (HTTP)
python vibrant_frog_mcp.py --transport http --port 5050

# For Claude Desktop (stdio)
python vibrant_frog_mcp.py --transport stdio
```

---

## Transport Comparison

| Feature | stdio | Streamable HTTP |
|---------|-------|-----------------|
| **For** | Claude Desktop, MCP tools | MCP Inspector, Swift app, web clients |
| **Communication** | stdin/stdout | HTTP POST + GET (SSE) |
| **Launch** | As subprocess | Standalone server |
| **Port** | N/A | 5050 (default) |
| **Multiple clients** | No | Yes (concurrent) |
| **Endpoint** | N/A | `/mcp` |

---

## Usage Examples

### 1. MCP Inspector (Streamable HTTP)

**Start server:**
```bash
./restart_http_server.sh
# or manually:
./venv/bin/python3 vibrant_frog_mcp.py --transport http --port 5050
```

**Connect in MCP Inspector:**
- Transport Type: `Streamable HTTP`
- URL: `http://127.0.0.1:5050/mcp`

### 2. Claude Desktop (stdio)

**Configure:** `~/Library/Application Support/Claude/claude_desktop_config.json`
```json
{
  "mcpServers": {
    "vibrant-frog": {
      "command": "/Users/tpiazza/git/VibrantFrogMCP/venv/bin/python3",
      "args": [
        "/Users/tpiazza/git/VibrantFrogMCP/vibrant_frog_mcp.py",
        "--transport",
        "stdio"
      ]
    }
  }
}
```

**Restart Claude Desktop** - server will be launched automatically

### 3. VibrantFrog Swift App (Streamable HTTP)

**Start server:** (same as MCP Inspector)
```bash
./restart_http_server.sh
```

**Swift code:**
```swift
let client = MCPClientHTTP(serverURL: "http://127.0.0.1:5050")
try await client.connect()
```

---

## One Server, Multiple Clients

When running in HTTP mode, you can have **multiple clients** connected simultaneously:

```
VibrantFrog MCP Server (HTTP mode, port 5050)
    │
    ├── MCP Inspector (browser)
    ├── VibrantFrog.app (Swift)
    └── curl/Python test scripts
```

All see the same tools and share the same photo index!

---

## Current Status

✅ **Streamable HTTP mode** - Fully implemented (MCP 2025-03-26 spec)
✅ **stdio mode** - Working (original implementation)
✅ **Session management** - Mcp-Session-Id header support
✅ **SSE stream** - GET /mcp for server → client messages
✅ **JSON-RPC** - POST /mcp for client → server messages

---

## Files Reference

| File | Purpose |
|------|---------|
| `vibrant_frog_mcp.py` | Main server (supports both transports) |
| `restart_http_server.sh` | Quick server restart script |
| `test_mcp_http.py` | Python test client for HTTP mode |
| `mcp_inspector_config.json` | MCP Inspector stdio config (alternative) |
| `MCPClientHTTP.swift` | Swift client for Streamable HTTP |
| `MCPClient.swift` | Swift client for stdio (deprecated for app) |

---

## Choosing a Transport

### Use **stdio** when:
- Connecting from Claude Desktop
- MCP server should be launched by the client
- Single client only
- Local machine only

### Use **Streamable HTTP** when:
- Building a Swift/web app
- Need multiple concurrent clients
- Testing with MCP Inspector
- May need remote access (future)
- Want to keep server running independently

---

## Troubleshooting

### "Connection refused" (HTTP)
```bash
# Check if server is running
lsof -i :5050

# Restart server
./restart_http_server.sh
```

### "Module not found" errors
```bash
# Make sure using venv Python
./venv/bin/python3 vibrant_frog_mcp.py --transport http
```

### Claude Desktop not seeing server
```bash
# Check config path
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json

# Verify Python path
which /Users/tpiazza/git/VibrantFrogMCP/venv/bin/python3
```

---

## Summary

✅ **ONE codebase** → TWO transports
✅ **stdio** → Claude Desktop
✅ **Streamable HTTP** → MCP Inspector + VibrantFrog.app
✅ **Both work perfectly**

Just use the `--transport` flag to choose!
