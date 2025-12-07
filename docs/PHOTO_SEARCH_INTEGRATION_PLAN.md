# VibrantFrog Photo Search Integration Plan

**Goal:** Make VibrantFrog's photo search capability a complete, production-ready feature that users can easily deploy and use.

## Current State Analysis

### What Exists

#### 1. **macOS App Components** ✅
- **IndexingView** - UI for indexing photos with progress tracking
- **PhotoSearchView** - UI for searching photos with natural language
- **PhotoLibraryService** - Photos framework integration
- **EmbeddingStore** - SQLite-based vector storage (384-dimensional)
- **LLMService** - Local LLM integration for image description

#### 2. **Python MCP Server** ✅
- **vibrant_frog_mcp.py** - Complete MCP server with:
  - Photo indexing with LLaVA
  - Vector search with ChromaDB
  - Album management
  - Photo retrieval by UUID
  - Face recognition (experimental)

#### 3. **Storage Systems** ⚠️
- **Swift:** SQLite embeddings in `~/Library/Application Support/VibrantFrog/embeddings.sqlite`
- **Python:** ChromaDB in `~/Library/Application Support/VibrantFrogMCP/photo_index`
- **Problem:** Two separate databases, no synchronization

### What's Missing

1. **Unified Storage** - Swift and Python use different databases
2. **MCP Integration** - Photo search not exposed via MCP to AI Chat
3. **Deployment Guide** - No clear setup instructions for users
4. **Background Indexing** - No automatic re-indexing
5. **Progress Sync** - Can't see Python indexing progress in Swift UI

---

## Recommended Architecture: Two-Track Approach

### Track 1: Standalone Swift (Quick Win) 🚀
**Best for users who want everything in one app, no Python setup**

### Track 2: Swift + Python MCP (Power Users) 💪
**Best for advanced features, face recognition, external tool integration**

---

## Track 1: Standalone Swift Photo Search

### Overview
Make the existing Swift implementation fully functional within VibrantFrog app.

### Components

```
┌─────────────────────────────────────────────────────┐
│              VibrantFrog macOS App                  │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ Indexing Tab │  │ AI Chat Tab  │  │ Search   │ │
│  │              │  │              │  │ Tab      │ │
│  │  • Progress  │  │  • Search    │  │  • Query │ │
│  │  • Batch     │  │    photos    │  │  • Grid  │ │
│  │  • Manual    │  │    via chat  │  │  • Album │ │
│  └──────┬───────┘  └──────┬───────┘  └────┬─────┘ │
│         │                 │                │       │
│         └─────────────────┼────────────────┘       │
│                           ↓                        │
│               ┌───────────────────────┐            │
│               │  PhotoSearchService   │            │
│               │  • Index photos       │            │
│               │  • Generate embedding │            │
│               │  • Vector search      │            │
│               └───────────┬───────────┘            │
│                           ↓                        │
│               ┌───────────────────────┐            │
│               │    EmbeddingStore     │            │
│               │   (SQLite + BLOB)     │            │
│               └───────────────────────┘            │
└─────────────────────────────────────────────────────┘
```

### Implementation Steps

#### Phase 1: Complete Swift PhotoSearchService
**File:** `Services/PhotoSearchService.swift` (NEW)

**Responsibilities:**
1. **Indexing**
   - Use Ollama's LLaVA model (already available locally)
   - Generate descriptions
   - Create embeddings using Ollama
   - Store in SQLite via EmbeddingStore

2. **Searching**
   - Generate query embedding
   - Cosine similarity search
   - Return top N results

3. **Integration**
   - Called from IndexingView
   - Called from PhotoSearchView
   - **NEW:** Available to AI Chat for tool calling

**Pseudocode:**
```swift
class PhotoSearchService: ObservableObject {
    private let embeddingStore: EmbeddingStore
    private let ollamaService: OllamaService

    // Index a photo
    func indexPhoto(_ asset: PHAsset) async throws {
        // 1. Load image from Photos
        let image = await loadImage(asset)

        // 2. Generate description with LLaVA via Ollama
        let description = try await ollamaService.describeImage(image)

        // 3. Generate embedding from description
        let embedding = try await ollamaService.generateEmbedding(description)

        // 4. Store in SQLite
        try embeddingStore.addPhoto(
            id: asset.localIdentifier,
            description: description,
            embedding: embedding
        )
    }

    // Search photos
    func search(query: String, limit: Int = 10) async throws -> [SearchResult] {
        // 1. Generate embedding for query
        let queryEmbedding = try await ollamaService.generateEmbedding(query)

        // 2. Search in vector DB
        let results = try embeddingStore.searchSimilar(
            embedding: queryEmbedding,
            limit: limit
        )

        // 3. Return results with photos
        return results
    }
}
```

#### Phase 2: Expose as Internal "Tool"
Make photo search available to AI Chat without MCP server.

**Approach:** Internal tool dispatch
```swift
// In AIChatView
func handlePhotoSearchRequest(_ query: String) async {
    let results = try await photoSearchService.search(query: query)

    // Format results for AI
    let formattedResults = results.map { result in
        """
        Photo: \(result.filename)
        Description: \(result.description)
        Similarity: \(result.similarity)
        UUID: \(result.photoID)
        """
    }.joined(separator: "\n\n")

    // Add to conversation as "tool result"
    conversationHistory.append(.init(
        role: "tool",
        content: "Found \(results.count) photos:\n\n\(formattedResults)"
    ))
}
```

#### Phase 3: UI Polish
**IndexingView improvements:**
- ✅ Batch indexing with progress
- ✅ Cancel/pause functionality
- ✅ Statistics dashboard
- 🆕 Auto-index new photos (background)
- 🆕 Re-index modified photos

**PhotoSearchView improvements:**
- ✅ Search with results grid
- 🆕 Similarity scores
- 🆕 Quick preview
- 🆕 Export to album

**AI Chat integration:**
- 🆕 Detect photo search intents
- 🆕 Display thumbnails inline
- 🆕 Allow photo selection for follow-up

### Benefits of Track 1
✅ **All-in-one** - No Python setup required
✅ **Fast** - Uses local Ollama (already required)
✅ **Simple** - One database, one app
✅ **Integrated** - Works seamlessly with chat
✅ **Maintainable** - Pure Swift codebase

### Limitations of Track 1
❌ No face recognition (requires Python)
❌ No external MCP tool access
❌ Limited to Ollama's embedding models
❌ Can't share index with other apps

---

## Track 2: Swift + Python MCP Integration

### Overview
Deploy the Python MCP server as a companion service for advanced features.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│              VibrantFrog macOS App                  │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ AI Chat      │  │ MCP Server   │  │ Tool     │ │
│  │              │  │ Config       │  │ Call     │ │
│  └──────┬───────┘  └──────┬───────┘  └────┬─────┘ │
│         │                 │                │       │
│         └─────────────────┼────────────────┘       │
│                           ↓                        │
│               ┌───────────────────────┐            │
│               │   MCPClientHTTP/Stdio │            │
│               └───────────┬───────────┘            │
└───────────────────────────┼─────────────────────────┘
                            │
                            ↓ HTTP or Stdio
┌─────────────────────────────────────────────────────┐
│         Python MCP Server (vibrant_frog_mcp.py)     │
│                                                     │
│  Tools:                                             │
│  • search_photos(query, n_results)                  │
│  • index_photo(image_path)                          │
│  • index_directory(directory_path)                  │
│  • get_photo(uuid)                                  │
│  • create_album(name, photo_uuids)                  │
│  • list_albums()                                    │
│  • index_faces()  [experimental]                    │
│  • search_faces(name)  [experimental]               │
│                                                     │
│  Storage: ChromaDB + Photo Library Access           │
└─────────────────────────────────────────────────────┘
```

### Deployment Options

#### Option A: HTTP Server (Recommended)
**Pros:**
- Easy to debug
- Works across network (optional)
- Stateless requests
- Can restart independently

**Setup:**
```bash
# Install dependencies
cd /path/to/VibrantFrogMCP
pip install -r requirements.txt

# Start HTTP server
python -m http_server_wrapper vibrant_frog_mcp.py --port 8080

# Or use existing restart script
./restart_http_server.sh
```

**VibrantFrog Configuration:**
```
MCP Server URL: http://localhost:8080
Endpoint Path: /mcp
Transport: HTTP
```

#### Option B: Stdio (Advanced)
**Pros:**
- Single process management
- Lower latency
- More secure (no network)

**Cons:**
- Harder to debug
- Must restart with app
- Process lifetime coupling

**VibrantFrog Configuration:**
```
Transport: Stdio
Command: python3
Args: ["/path/to/vibrant_frog_mcp.py"]
```

### Implementation Steps

#### Phase 1: Package Python MCP Server

**Create proper Python package structure:**
```
VibrantFrogMCP/
├── python_server/
│   ├── __init__.py
│   ├── vibrant_frog_mcp.py
│   ├── photo_retrieval.py
│   ├── album_manager.py
│   ├── requirements.txt
│   ├── setup.py
│   └── README.md
```

**requirements.txt:**
```
mcp>=0.9.0
chromadb>=0.4.0
ollama>=0.1.0
Pillow>=10.0.0
sentence-transformers>=2.2.0
```

**setup.py:**
```python
from setuptools import setup, find_packages

setup(
    name="vibrantfrog-mcp-server",
    version="1.0.0",
    packages=find_packages(),
    install_requires=[...],
    entry_points={
        'console_scripts': [
            'vibrantfrog-mcp=vibrant_frog_mcp:main',
        ],
    },
)
```

#### Phase 2: Installation Script

**install_photo_search.sh:**
```bash
#!/bin/bash
set -e

echo "🐸 VibrantFrog Photo Search Installation"
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 not found. Please install Python 3.9+"
    exit 1
fi

# Check Ollama
if ! command -v ollama &> /dev/null; then
    echo "⚠️  Ollama not found. Installing..."
    brew install ollama
fi

# Pull required models
echo "📥 Pulling LLaVA model..."
ollama pull llava:7b

# Install Python package
echo "📦 Installing Python dependencies..."
cd python_server
pip3 install -e .

# Start HTTP server
echo "🚀 Starting MCP server..."
python3 -m vibrant_frog_mcp --http --port 8080 &

echo "✅ Installation complete!"
echo ""
echo "Add this MCP server in VibrantFrog:"
echo "  URL: http://localhost:8080"
echo "  Path: /mcp"
```

#### Phase 3: Auto-Start Integration

**macOS LaunchAgent** (optional):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.spiderink.vibrantfrog.mcp</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/python3</string>
        <string>/Users/USER/Library/Application Support/VibrantFrog/mcp/vibrant_frog_mcp.py</string>
        <string>--http</string>
        <string>--port</string>
        <string>8080</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/vibrantfrog-mcp.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/vibrantfrog-mcp-error.log</string>
</dict>
</plist>
```

Save to: `~/Library/LaunchAgents/com.spiderink.vibrantfrog.mcp.plist`

Load: `launchctl load ~/Library/LaunchAgents/com.spiderink.vibrantfrog.mcp.plist`

### Benefits of Track 2
✅ **Advanced features** - Face recognition, external tools
✅ **Flexible** - Can add Python-only features easily
✅ **Powerful** - ChromaDB is battle-tested
✅ **Extensible** - Other apps can use same MCP server

### Limitations of Track 2
❌ **Complex setup** - Python, dependencies, server management
❌ **Two databases** - Swift SQLite + Python ChromaDB
❌ **More moving parts** - Server must be running
❌ **Harder to debug** - Cross-language issues

---

## Recommended Hybrid Approach 🎯

### Phase 1: Ship Track 1 (v1.0)
**Goal:** Get photo search working for most users immediately

**Deliverables:**
1. Complete `PhotoSearchService.swift`
2. Integrate with AI Chat (internal tool calling)
3. Polish IndexingView and PhotoSearchView
4. Document in README

**User Experience:**
- Install VibrantFrog
- Open "Indexing" tab
- Click "Index All Photos"
- Go to AI Chat, ask "show me beach photos"
- ✨ It just works

**Timeline:** 1-2 weeks

### Phase 2: Add Track 2 as Optional (v1.1)
**Goal:** Power users get advanced features

**Deliverables:**
1. Package Python MCP server properly
2. Create installation script
3. Add "Advanced Photo Search" section to docs
4. Optional face recognition guide

**User Experience:**
- Advanced users run `./install_photo_search.sh`
- Configure MCP server in app
- Get face recognition and album management
- Can use same search from other MCP clients

**Timeline:** 2-3 weeks

### Phase 3: Convergence (v2.0)
**Goal:** Best of both worlds

**Possible approaches:**
1. **Swift calls Python via process** - Use Python for indexing, Swift for search
2. **Shared storage** - Both write to same ChromaDB
3. **Pure Swift** - Port ChromaDB operations to Swift (long-term)

**Timeline:** Future roadmap

---

## Implementation Checklist

### Track 1: Standalone Swift ✅

- [ ] **Create PhotoSearchService.swift**
  - [ ] Photo indexing with Ollama LLaVA
  - [ ] Embedding generation with Ollama
  - [ ] Vector search in SQLite
  - [ ] Progress reporting

- [ ] **Enhance EmbeddingStore.swift**
  - [ ] Add cosine similarity search
  - [ ] Optimize for performance
  - [ ] Add batch operations

- [ ] **Integrate with AI Chat**
  - [ ] Detect photo search intents
  - [ ] Call PhotoSearchService internally
  - [ ] Format results for LLM
  - [ ] Display thumbnails

- [ ] **UI Polish**
  - [ ] Background indexing option
  - [ ] Better progress visualization
  - [ ] Search results preview
  - [ ] Export to album

- [ ] **Documentation**
  - [ ] README section on photo search
  - [ ] Troubleshooting guide
  - [ ] Performance tips

### Track 2: Python MCP Server (Optional)

- [ ] **Package Python server**
  - [ ] Proper directory structure
  - [ ] requirements.txt
  - [ ] setup.py
  - [ ] README.md

- [ ] **Installation automation**
  - [ ] install_photo_search.sh script
  - [ ] Dependency checks
  - [ ] Model downloads
  - [ ] Server startup

- [ ] **Auto-start (optional)**
  - [ ] LaunchAgent plist
  - [ ] Status checking
  - [ ] Restart on failure

- [ ] **Documentation**
  - [ ] Installation guide
  - [ ] Configuration options
  - [ ] Troubleshooting
  - [ ] Face recognition guide

---

## User Documentation Outline

### Quick Start (Track 1)

```markdown
# Photo Search with VibrantFrog

VibrantFrog can search your photo library using natural language AI.

## Setup (2 minutes)

1. **Grant Photo Library Access**
   - Open VibrantFrog
   - Go to "Indexing" tab
   - Click "Grant Access" when prompted

2. **Index Your Photos**
   - Click "Start Indexing"
   - Wait for completion (10-20 photos/minute)
   - You can use the app while indexing runs

3. **Search Your Photos**
   - Go to "AI Chat" tab
   - Ask: "show me sunset photos"
   - Or use the "Search" tab directly

## Example Queries

- "beach photos from summer"
- "pictures of my dog"
- "photos with blue skies"
- "group photos with 3+ people"
- "food photography"
```

### Advanced Setup (Track 2)

```markdown
# Advanced Photo Search (Python MCP Server)

For advanced features like face recognition and album management.

## Prerequisites

- Python 3.9+
- Ollama installed
- macOS 14.0+

## Installation

```bash
cd /path/to/VibrantFrog
./install_photo_search.sh
```

## Configuration

1. Open VibrantFrog
2. Go to "MCP Server" tab
3. Add server:
   - Name: VibrantFrog Photos
   - URL: http://localhost:8080
   - Path: /mcp
4. Click "Connect"

## Advanced Features

- Face recognition and clustering
- Smart album creation
- Batch photo operations
- External tool integration
```

---

## Performance Considerations

### Indexing Speed

**Track 1 (Swift + Ollama):**
- **LLaVA description:** ~2-3 seconds/photo
- **Embedding generation:** ~0.1 seconds/photo
- **Database write:** ~0.01 seconds/photo
- **Total:** ~2-3 seconds/photo
- **1000 photos:** ~40-50 minutes

**Optimizations:**
- Batch processing (10 photos at a time)
- Skip already indexed photos
- Background indexing
- Pause/resume support

### Search Speed

**Track 1:**
- Query embedding: ~0.1 seconds
- Vector search (SQLite): ~0.01-0.1 seconds (1000 photos)
- Total: ~0.15 seconds

**Track 2:**
- ChromaDB optimized for larger collections
- Sub-second search on 10,000+ photos

### Storage

**Per photo:**
- Description: ~200 bytes
- Embedding (384-dim): ~1.5 KB
- Metadata: ~100 bytes
- **Total:** ~2 KB/photo

**1000 photos:** ~2 MB
**10,000 photos:** ~20 MB

---

## Testing Plan

### Unit Tests
- [ ] PhotoSearchService indexing
- [ ] Embedding generation
- [ ] Vector search accuracy
- [ ] EmbeddingStore operations

### Integration Tests
- [ ] Full indexing workflow
- [ ] Search results quality
- [ ] MCP server communication (Track 2)
- [ ] UI responsiveness during indexing

### User Testing
- [ ] Index 100 photos
- [ ] Perform 10 searches
- [ ] Verify results relevance
- [ ] Check performance on older Macs

---

## Deployment Strategy

### v1.0 Release
**Include:** Track 1 only

**Rationale:**
- Simpler for users
- Fewer dependencies
- Easier to support
- Gets feature shipped faster

**Communication:**
- "Built-in photo search powered by AI"
- "No additional setup required"
- "Works offline with local models"

### v1.1 Update
**Add:** Track 2 as optional

**Rationale:**
- Power users get advanced features
- Validates MCP server architecture
- Community contributions (Python easier)

**Communication:**
- "New: Advanced photo search features"
- "Optional Python server for face recognition"
- "For advanced users only"

### v2.0 Vision
**Goal:** Unified solution

**Possibilities:**
- Pure Swift (port ChromaDB operations)
- Hybrid (Swift UI, Python backend)
- Plugin architecture

---

## Success Metrics

### v1.0 (Track 1)
- ✅ 80%+ users can index photos successfully
- ✅ Search results relevant 70%+ of the time
- ✅ Indexing completes without crashes
- ✅ < 5% support requests about photo search

### v1.1 (Track 2)
- ✅ 20%+ advanced users install Python server
- ✅ Face recognition accurate 80%+ of the time
- ✅ MCP server stable (99% uptime)
- ✅ Clear documentation reduces confusion

---

## Decision: Recommended Path Forward

### Immediate (Next 2 Weeks)
✅ **Implement Track 1**
- Complete PhotoSearchService.swift
- Integrate with AI Chat
- Polish UI
- Document thoroughly

### Short-term (Following Month)
✅ **Package Track 2**
- Clean up Python server
- Create install script
- Document advanced features
- Mark as "optional/advanced"

### Long-term (v2.0+)
🔮 **Evaluate convergence**
- Monitor user adoption
- Gather feedback
- Decide on unified approach

---

## Summary

**Best approach:** Start with Track 1 (Pure Swift), add Track 2 (Python MCP) as optional advanced feature.

**Why this works:**
1. **Immediate value** - Most users get photo search in v1.0
2. **Low barrier** - No Python setup required initially
3. **Power user support** - Advanced users get more features in v1.1
4. **Iterative** - Can refine based on real usage
5. **Maintainable** - Two independent systems, easier to debug

**What makes it production-ready:**
- ✅ Clear documentation
- ✅ Simple installation (Track 1)
- ✅ Optional advanced features (Track 2)
- ✅ Performance tested
- ✅ Error handling
- ✅ Progress reporting
- ✅ Background operation

This plan gives VibrantFrog a competitive photo search feature while maintaining simplicity for most users and power for advanced users.
