# VibrantFrog.app Product Specification

**Version:** 1.0 Draft
**Last Updated:** 2025-11-22
**Author:** Claude + Tony Piazza

---

## Executive Summary

VibrantFrog.app is a native macOS application that provides AI-powered photo library search, organization, and management. It combines local LLM processing (via Ollama), an MCP server for tool integration, and its own agentic chat interface - all in a single, installable Mac application.

The app enables users to:
- Search their Apple Photos library using natural language
- Create and manage albums via AI assistant
- Connect Claude Desktop (or other MCP clients) to VibrantFrog's tools
- Optionally expose tools remotely via Cloudflare Tunnel for mobile access

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Core Components](#2-core-components)
3. [Installation & Setup](#3-installation--setup)
4. [Feature Specifications](#4-feature-specifications)
5. [MCP Server Specification](#5-mcp-server-specification)
6. [Chat Interface Specification](#6-chat-interface-specification)
7. [Claude Desktop Integration](#7-claude-desktop-integration)
8. [Remote Access via Cloudflare](#8-remote-access-via-cloudflare)
9. [Data Storage & Privacy](#9-data-storage--privacy)
10. [Future Roadmap](#10-future-roadmap)
11. [Technical Implementation Notes](#11-technical-implementation-notes)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         VibrantFrog.app                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐   │
│  │   Menu Bar UI    │  │   Chat Window    │  │   Settings Window    │   │
│  │                  │  │                  │  │                      │   │
│  │ - Status         │  │ - Agentic Chat   │  │ - Ollama Config      │   │
│  │ - Quick Search   │  │ - Photo Results  │  │ - MCP Server Config  │   │
│  │ - Indexing %     │  │ - Album Mgmt     │  │ - Cloudflare Setup   │   │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘   │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                        Core Services                               │  │
│  ├───────────────────────────────────────────────────────────────────┤  │
│  │                                                                    │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────────┐  │  │
│  │  │ MCP Server  │  │   Indexer   │  │  Photo      │  │  Album   │  │  │
│  │  │ (HTTP)      │  │   Service   │  │  Retrieval  │  │  Manager │  │  │
│  │  │             │  │             │  │             │  │          │  │  │
│  │  │ :5050       │  │ Background  │  │ ChromaDB    │  │ AppleScript│ │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └──────────┘  │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                      External Dependencies                         │  │
│  ├───────────────────────────────────────────────────────────────────┤  │
│  │                                                                    │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐    │  │
│  │  │   Ollama    │  │   ChromaDB  │  │   Apple Photos Library  │    │  │
│  │  │             │  │             │  │                         │    │  │
│  │  │ llava:7b    │  │ Embedded    │  │ Via osxphotos +         │    │  │
│  │  │ llama3.1    │  │ (bundled)   │  │ AppleScript             │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────┘    │  │
│  │                                                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

                    │                              │
                    ▼                              ▼
    ┌───────────────────────────┐    ┌───────────────────────────┐
    │     Claude Desktop        │    │   Cloudflare Tunnel       │
    │                           │    │                           │
    │  MCP Client connecting    │    │   Optional remote access  │
    │  to localhost:5050        │    │   for iOS / other clients │
    │  via streamable-http      │    │                           │
    └───────────────────────────┘    └───────────────────────────┘
```

---

## 2. Core Components

### 2.1 VibrantFrog.app (Native macOS)

**Technology:** Swift/SwiftUI
**Distribution:** DMG (notarized, outside App Store)
**Minimum macOS:** 13.0 (Ventura)
**Architectures:** Universal (Apple Silicon + Intel)

**Responsibilities:**
- Application lifecycle management
- Menu bar presence and status
- Native UI windows (Chat, Settings, Onboarding)
- Managing embedded services (MCP server, indexer)
- Ollama installation/management
- System permissions handling (Photos access)

### 2.2 MCP Server

**Technology:** Python (bundled via PyInstaller) or Swift
**Transport:** Streamable HTTP (SSE) on configurable port (default: 5050)
**Protocol:** MCP 1.0

**Responsibilities:**
- Exposing VibrantFrog tools via MCP protocol
- Handling requests from Claude Desktop, iOS, or other MCP clients
- Managing tool execution and responses

### 2.3 Indexer Service

**Technology:** Python (bundled)
**Runs:** Background process managed by main app

**Responsibilities:**
- Scanning Apple Photos Library via osxphotos
- Generating image descriptions via Ollama (llava:7b)
- Storing embeddings in ChromaDB
- Incremental indexing of new photos
- Face detection and clustering (Phase 2)

### 2.4 Chat Interface

**Technology:** SwiftUI (native) or Embedded Web View
**LLM Backend:** Ollama (llama3.1, mistral, or user's choice)

**Responsibilities:**
- Agentic chat experience with tool calling
- Displaying photo search results with thumbnails
- Album creation/management UI
- Conversation history

### 2.5 ChromaDB (Embedded)

**Technology:** ChromaDB (Python, bundled)
**Storage:** `~/Library/Application Support/VibrantFrog/`

**Collections:**
- `photos` - Photo descriptions and embeddings
- `faces` - Face embeddings and clusters (Phase 2)

---

## 3. Installation & Setup

### 3.1 Distribution

- **Download:** `VibrantFrog-1.0.dmg` from website or GitHub Releases
- **Size:** ~500MB (includes bundled Python, models, dependencies)
- **Signing:** Apple Developer ID signed and notarized
- **Updates:** Sparkle framework for auto-updates

### 3.2 First Launch Wizard

```
┌─────────────────────────────────────────────────────────┐
│                Welcome to VibrantFrog                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Step 1 of 5: Photos Access                             │
│  ─────────────────────────                              │
│                                                          │
│  VibrantFrog needs access to your Photos library        │
│  to index and search your photos.                       │
│                                                          │
│  [Grant Photos Access]                                  │
│                                                          │
│  ☐ Also allow location data (for location search)       │
│                                                          │
│                                          [Next →]        │
└─────────────────────────────────────────────────────────┘
```

**Wizard Steps:**

1. **Photos Access** - Request Photos library permission
2. **Ollama Setup** - Install Ollama or detect existing installation
3. **Model Download** - Download required models (llava:7b, llama3.1)
4. **Initial Indexing** - Start background indexing (can continue in background)
5. **Complete** - Show menu bar icon, offer to open chat

### 3.3 Ollama Management

**If Ollama not installed:**
```
┌─────────────────────────────────────────────────────────┐
│  Ollama Required                                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  VibrantFrog uses Ollama to run AI models locally.      │
│                                                          │
│  ○ Install Ollama automatically (recommended)           │
│  ○ I'll install Ollama manually                         │
│  ○ Use existing Ollama installation at: [________]      │
│                                                          │
│                              [Install & Continue →]      │
└─────────────────────────────────────────────────────────┘
```

**Automatic Installation:**
1. Download Ollama.dmg from official source
2. Mount and copy to /Applications
3. Launch Ollama
4. Pull required models: `ollama pull llava:7b && ollama pull llama3.1`

**Model Requirements:**

| Model | Purpose | Size | Required |
|-------|---------|------|----------|
| llava:7b | Image description | ~4GB | Yes |
| llama3.1:8b | Chat/reasoning | ~4.7GB | Yes |
| nomic-embed-text | Embeddings (optional) | ~274MB | No (using sentence-transformers) |

---

## 4. Feature Specifications

### 4.1 Menu Bar Interface

```
┌──────────────────────────────┐
│ 🐸 VibrantFrog               │
├──────────────────────────────┤
│ ✓ MCP Server Running         │
│   localhost:5050             │
├──────────────────────────────┤
│ 📊 Indexed: 18,432 / 21,000  │
│ 🔄 Indexing: 87%             │
├──────────────────────────────┤
│ 🔍 Quick Search...       ⌘F  │
│ 💬 Open Chat             ⌘O  │
│ ⚙️ Settings...           ⌘,  │
├──────────────────────────────┤
│ 📋 Copy MCP Config           │
│ 🌐 Remote Access: Off        │
├──────────────────────────────┤
│ Quit VibrantFrog         ⌘Q  │
└──────────────────────────────┘
```

### 4.2 Photo Search

**Natural Language Queries:**
- "beach sunset photos from last summer"
- "photos with dogs"
- "birthday party at grandma's house"
- "screenshots of receipts"
- "landscape photos with mountains"

**Search Filters (combinable):**
- Date range
- Location
- Favorites only
- Media type (photo, video, screenshot, selfie)
- Album membership
- Person (after face recognition)

### 4.3 Album Management

**Capabilities:**
- Create album from search results
- Create empty album
- Add photos to existing album
- Remove photos from album
- Delete album
- List all albums

**Example Flow:**
```
User: "Create an album called 'Beach 2024' with all my beach photos from this year"
Assistant: [Searching for photos matching "beach" in 2024]
Assistant: Found 47 photos. Creating album "Beach 2024"...
Assistant: Done! Created album "Beach 2024" with 47 photos.
```

---

## 5. MCP Server Specification

### 5.1 Transport: Streamable HTTP

The MCP server uses **Streamable HTTP** transport (not stdio) to allow:
- Multiple simultaneous clients
- Remote access via Cloudflare
- Claude Desktop connection via URL

**Endpoint:** `http://localhost:5050/mcp`

**Protocol Flow:**
```
Client                          Server (VibrantFrog)
  |                                   |
  |-- POST /mcp (initialize) -------->|
  |<-- SSE stream (capabilities) -----|
  |                                   |
  |-- POST /mcp (tools/list) -------->|
  |<-- SSE stream (tool list) --------|
  |                                   |
  |-- POST /mcp (tools/call) -------->|
  |<-- SSE stream (result) -----------|
```

### 5.2 Available Tools

| Tool Name | Description | Parameters |
|-----------|-------------|------------|
| `search_photos` | Search photos by natural language | `query: string, limit?: number` |
| `get_photo` | Retrieve photo by UUID | `uuid: string` |
| `create_album` | Create empty album | `album_name: string` |
| `delete_album` | Delete album | `album_name: string` |
| `list_albums` | List all albums | none |
| `create_album_from_search` | Search and create album | `album_name: string, query: string, limit?: number` |
| `add_photos_to_album` | Add photos to album | `album_name: string, photo_uuids: string[]` |
| `remove_photos_from_album` | Remove photos from album | `album_name: string, photo_uuids: string[]` |
| `get_library_stats` | Get photo library statistics | none |
| `search_photos_by_date` | Search by date range | `start_date: string, end_date: string` |
| `search_photos_by_person` | Search by person name | `person_name: string` (Phase 2) |

### 5.3 Server Configuration

**Settings (configurable via UI):**
```json
{
  "mcp_server": {
    "enabled": true,
    "port": 5050,
    "host": "127.0.0.1",
    "require_auth": false,
    "auth_token": null
  }
}
```

**With Authentication (for remote access):**
```json
{
  "mcp_server": {
    "enabled": true,
    "port": 5050,
    "host": "0.0.0.0",
    "require_auth": true,
    "auth_token": "your-secret-token-here"
  }
}
```

---

## 6. Chat Interface Specification

### 6.1 Chat Window Design

```
┌─────────────────────────────────────────────────────────────────┐
│  VibrantFrog Chat                                    ─  □  ×    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                                                             │ │
│  │  🐸 Hi! I can help you search and organize your photos.    │ │
│  │     Try asking me to find specific photos or create        │ │
│  │     albums.                                                 │ │
│  │                                                             │ │
│  │  👤 Show me sunset photos from my trip to Hawaii           │ │
│  │                                                             │ │
│  │  🐸 [Searching...] Found 23 photos matching "sunset        │ │
│  │     Hawaii trip":                                          │ │
│  │                                                             │ │
│  │     ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐              │ │
│  │     │     │ │     │ │     │ │     │ │     │              │ │
│  │     │ 📷  │ │ 📷  │ │ 📷  │ │ 📷  │ │ 📷  │              │ │
│  │     │     │ │     │ │     │ │     │ │     │              │ │
│  │     └─────┘ └─────┘ └─────┘ └─────┘ └─────┘              │ │
│  │     IMG_001 IMG_002 IMG_003 IMG_004 IMG_005               │ │
│  │                                                             │ │
│  │     Would you like me to create an album with these?       │ │
│  │                                                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Yes, call it "Hawaii Sunsets"                          [→] │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  Model: llama3.1:8b ▼    │ Clear Chat │ Export │ Settings ⚙️   │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Agent Architecture

```
User Input
    │
    ▼
┌─────────────────┐
│  Ollama LLM     │
│  (llama3.1)     │
│                 │
│  System Prompt: │
│  "You have      │
│  access to      │
│  photo tools"   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│  Tool Decision  │────>│  Tool Execution │
│                 │     │                 │
│  search_photos? │     │  ChromaDB query │
│  create_album?  │     │  AppleScript    │
│  etc.           │     │                 │
└─────────────────┘     └────────┬────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │  Format Results │
                        │                 │
                        │  - Photo grid   │
                        │  - Metadata     │
                        │  - Actions      │
                        └────────┬────────┘
                                 │
                                 ▼
                           Response to User
```

### 6.3 System Prompt

```
You are VibrantFrog, a helpful AI assistant for managing photos in Apple Photos.

You have access to the following tools:
- search_photos: Search the photo library using natural language
- get_photo: Retrieve a specific photo by UUID
- create_album: Create a new album
- delete_album: Delete an album (photos are preserved)
- add_photos_to_album: Add photos to an existing album
- create_album_from_search: Search and create album in one step
- list_albums: List all albums

Guidelines:
1. When users ask to find photos, use search_photos and display results as a grid
2. When users want to organize photos, offer to create albums
3. Always confirm before deleting albums
4. Be concise but helpful
5. If a search returns no results, suggest alternative search terms
```

---

## 7. Claude Desktop Integration

### 7.1 Configuration

Users can connect Claude Desktop to VibrantFrog's MCP server.

**Step 1:** Open Claude Desktop settings or edit config file:
```
~/Library/Application Support/Claude/claude_desktop_config.json
```

**Step 2:** Add VibrantFrog MCP server:
```json
{
  "mcpServers": {
    "vibrant-frog": {
      "transport": "streamable-http",
      "url": "http://localhost:5050/mcp"
    }
  }
}
```

**Step 3:** Restart Claude Desktop

**Step 4:** Verify connection - Claude should now show VibrantFrog tools

### 7.2 Copy Config Button

VibrantFrog provides a "Copy MCP Config" button in the menu bar that copies the correct JSON snippet to clipboard:

```json
{
  "vibrant-frog": {
    "transport": "streamable-http",
    "url": "http://localhost:5050/mcp"
  }
}
```

### 7.3 Usage in Claude Desktop

Once connected, users can ask Claude:
- "Search my photos for beach sunsets"
- "Create an album called 'Favorites 2024' with my best photos"
- "Show me photos from last Christmas"
- "Find all photos with dogs"

Claude will use VibrantFrog's tools to fulfill these requests.

---

## 8. Remote Access via Cloudflare

### 8.1 Overview

For users who want to access VibrantFrog from:
- Claude iOS app (when MCP support is added)
- Other devices
- Remote MCP clients

VibrantFrog can create a Cloudflare Tunnel to expose the MCP server securely.

### 8.2 Setup Flow

```
┌─────────────────────────────────────────────────────────┐
│  Remote Access Setup                                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Enable remote access to use VibrantFrog from other     │
│  devices or apps like Claude for iOS.                   │
│                                                          │
│  This uses Cloudflare Tunnel for secure access.         │
│                                                          │
│  ○ I have a Cloudflare account                          │
│    [Enter API Token: _______________]                   │
│                                                          │
│  ○ Create free Cloudflare account                       │
│    [Open Cloudflare →]                                  │
│                                                          │
│  ○ Use temporary tunnel (expires in 24h)                │
│    No account needed, but URL changes daily             │
│                                                          │
│                                          [Enable →]      │
└─────────────────────────────────────────────────────────┘
```

### 8.3 Cloudflare Tunnel Configuration

**Option A: Temporary Tunnel (No Account)**

VibrantFrog runs `cloudflared` with a temporary tunnel:
```bash
cloudflared tunnel --url http://localhost:5050
```

This creates a URL like: `https://random-words.trycloudflare.com`

**Limitations:**
- URL changes each time
- Expires after 24 hours of inactivity
- No custom domain

**Option B: Persistent Tunnel (Free Account)**

1. User creates Cloudflare account
2. User generates API token
3. VibrantFrog creates named tunnel via API
4. Tunnel persists with stable URL

**Configuration stored:**
```json
{
  "cloudflare": {
    "enabled": true,
    "tunnel_name": "vibrantfrog-macbook",
    "tunnel_url": "https://photos.yourdomain.com",
    "api_token": "encrypted..."
  }
}
```

### 8.4 Security

**Authentication Required for Remote:**
- When Cloudflare tunnel is enabled, auth token is required
- Token shown once during setup, user must save it
- All remote requests must include: `Authorization: Bearer <token>`

**Claude Desktop Config for Remote:**
```json
{
  "mcpServers": {
    "vibrant-frog-remote": {
      "transport": "streamable-http",
      "url": "https://your-tunnel.trycloudflare.com/mcp",
      "headers": {
        "Authorization": "Bearer your-auth-token"
      }
    }
  }
}
```

### 8.5 iOS Access (Future)

When Claude iOS supports MCP over streamable-http:
1. User enables remote access in VibrantFrog
2. User adds MCP server in Claude iOS settings
3. User can search photos from iPhone

---

## 9. Data Storage & Privacy

### 9.1 Storage Locations

| Data | Location | Size Estimate |
|------|----------|---------------|
| Photo index (ChromaDB) | `~/Library/Application Support/VibrantFrog/photo_index/` | ~500MB for 20K photos |
| Face embeddings | `~/Library/Application Support/VibrantFrog/photo_index/` | ~100MB for 50K faces |
| App settings | `~/Library/Application Support/VibrantFrog/settings.json` | <1KB |
| Logs | `~/Library/Logs/VibrantFrog/` | ~10MB |
| Cache | `~/Library/Caches/VibrantFrog/` | Variable |

### 9.2 Privacy Principles

1. **All processing is local** - Photos never leave your Mac
2. **No cloud uploads** - Descriptions and embeddings stay on your machine
3. **No telemetry** - VibrantFrog does not phone home
4. **Optional remote access** - Cloudflare tunnel is opt-in
5. **Deletable data** - User can delete all VibrantFrog data at any time

### 9.3 Data Deletion

**From Settings:**
- "Delete Photo Index" - Removes ChromaDB, keeps settings
- "Delete All Data" - Complete removal
- "Reset App" - Factory reset

---

## 10. Future Roadmap

### Phase 1: Core App (v1.0)
- [x] Photo indexing with LLaVA
- [x] Natural language search
- [x] Album management
- [ ] Native macOS app
- [ ] MCP server (streamable-http)
- [ ] Built-in chat interface
- [ ] Ollama installation wizard
- [ ] Claude Desktop integration docs

### Phase 2: Face Recognition (v1.1)
- [ ] Face detection (InsightFace)
- [ ] Face clustering (DBSCAN)
- [ ] Person labeling UI
- [ ] Search by person name
- [ ] `search_photos_by_person` MCP tool

### Phase 3: Remote Access (v1.2)
- [ ] Cloudflare Tunnel integration
- [ ] Authentication system
- [ ] Remote MCP access
- [ ] iOS documentation (when Claude iOS supports MCP)

### Phase 4: Advanced Features (v2.0)
- [ ] Video indexing
- [ ] Live Photo support
- [ ] Duplicate detection
- [ ] Similar photo search
- [ ] Smart album suggestions
- [ ] Export functionality
- [ ] Memories/Moments integration

### Phase 5: Multi-User & Sharing (v2.x)
- [ ] Multiple library support
- [ ] Shared family library
- [ ] Photo sharing links
- [ ] Collaborative albums

---

## 11. Technical Implementation Notes

### 11.1 Build System

**Swift App:**
- Xcode project with SwiftUI
- Target: macOS 13.0+
- Architecture: Universal (arm64 + x86_64)

**Python Components:**
- Bundled via PyInstaller or py2app
- Embedded in app bundle: `VibrantFrog.app/Contents/Resources/python/`
- Self-contained Python environment

### 11.2 IPC Between Swift and Python

**Option A: Process + HTTP**
```swift
// Swift launches Python MCP server as subprocess
let process = Process()
process.executableURL = Bundle.main.url(forResource: "mcp-server", withExtension: nil)
process.launch()

// Swift communicates via HTTP
let url = URL(string: "http://localhost:5050/mcp")
```

**Option B: Direct Python Embedding**
```swift
// Use PythonKit to embed Python directly
import PythonKit
let chromadb = Python.import("chromadb")
```

**Recommendation:** Option A (Process + HTTP) for better isolation and crash recovery.

### 11.3 App Signing & Notarization

```bash
# Sign the app
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Tony Piazza (TEAMID)" \
    --options runtime \
    VibrantFrog.app

# Create DMG
create-dmg \
    --volname "VibrantFrog" \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 400 200 \
    VibrantFrog.dmg \
    VibrantFrog.app

# Notarize
xcrun notarytool submit VibrantFrog.dmg \
    --apple-id "email@example.com" \
    --team-id TEAMID \
    --password "@keychain:AC_PASSWORD" \
    --wait

# Staple
xcrun stapler staple VibrantFrog.dmg
```

### 11.4 Auto-Update (Sparkle)

```swift
import Sparkle

let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
```

**Appcast URL:** `https://vibrantfrog.app/appcast.xml`

### 11.5 Dependencies

**Python Packages (bundled):**
- chromadb
- sentence-transformers
- osxphotos
- ollama
- fastapi (for MCP HTTP server)
- uvicorn
- insightface (Phase 2)
- scikit-learn (Phase 2)

**Swift Packages:**
- Sparkle (auto-updates)
- KeychainAccess (secure storage)

---

## Appendix A: MCP Streamable HTTP Implementation

Reference implementation for the MCP server using FastAPI:

```python
# mcp_http_server.py
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from sse_starlette.sse import EventSourceResponse
import json
import asyncio

app = FastAPI()

# MCP Tools
TOOLS = [
    {
        "name": "search_photos",
        "description": "Search photos by natural language query",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer", "default": 10}
            },
            "required": ["query"]
        }
    },
    # ... more tools
]

@app.post("/mcp")
async def mcp_endpoint(request: Request):
    body = await request.json()
    method = body.get("method")

    async def event_generator():
        if method == "initialize":
            yield {
                "event": "message",
                "data": json.dumps({
                    "jsonrpc": "2.0",
                    "id": body.get("id"),
                    "result": {
                        "protocolVersion": "1.0",
                        "capabilities": {"tools": True}
                    }
                })
            }
        elif method == "tools/list":
            yield {
                "event": "message",
                "data": json.dumps({
                    "jsonrpc": "2.0",
                    "id": body.get("id"),
                    "result": {"tools": TOOLS}
                })
            }
        elif method == "tools/call":
            # Execute tool and stream result
            result = await execute_tool(body.get("params"))
            yield {
                "event": "message",
                "data": json.dumps({
                    "jsonrpc": "2.0",
                    "id": body.get("id"),
                    "result": result
                })
            }

    return EventSourceResponse(event_generator())

async def execute_tool(params):
    tool_name = params.get("name")
    arguments = params.get("arguments", {})

    if tool_name == "search_photos":
        # Call your existing search function
        from photo_retrieval import search_photos_by_description
        results = search_photos_by_description(
            arguments.get("query"),
            arguments.get("limit", 10)
        )
        return {"content": [{"type": "text", "text": json.dumps(results)}]}

    # ... handle other tools

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=5050)
```

---

## Appendix B: Ollama Installation Script

```bash
#!/bin/bash
# install_ollama.sh - Called by VibrantFrog installer

set -e

OLLAMA_VERSION="0.4.0"
OLLAMA_DMG="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/Ollama-darwin.zip"

echo "Downloading Ollama..."
curl -L "$OLLAMA_DMG" -o /tmp/ollama.zip

echo "Installing Ollama..."
unzip -o /tmp/ollama.zip -d /Applications/

echo "Launching Ollama..."
open -a Ollama

echo "Waiting for Ollama to start..."
sleep 5

echo "Pulling required models..."
ollama pull llava:7b
ollama pull llama3.1:8b

echo "Done!"
```

---

## Appendix C: Project Structure

```
VibrantFrog/
├── VibrantFrog.xcodeproj/
├── VibrantFrog/
│   ├── App/
│   │   ├── VibrantFrogApp.swift
│   │   ├── AppDelegate.swift
│   │   └── MenuBarController.swift
│   ├── Views/
│   │   ├── ChatView.swift
│   │   ├── SettingsView.swift
│   │   ├── OnboardingView.swift
│   │   └── PhotoGridView.swift
│   ├── Services/
│   │   ├── MCPServerManager.swift
│   │   ├── IndexerManager.swift
│   │   ├── OllamaManager.swift
│   │   └── CloudflareManager.swift
│   ├── Models/
│   │   ├── Photo.swift
│   │   ├── Album.swift
│   │   └── Settings.swift
│   └── Resources/
│       ├── Assets.xcassets/
│       └── python/
│           ├── mcp_server.py
│           ├── photo_retrieval.py
│           ├── album_manager.py
│           ├── index_photos.py
│           └── requirements.txt
├── Scripts/
│   ├── build.sh
│   ├── notarize.sh
│   └── install_ollama.sh
├── Tests/
└── README.md
```

---

*Document Version: 1.0 Draft*
*Last Updated: 2025-11-22*
