# VibrantFrog Photo Search - Production Deployment Plan

**Reality Check:** The photo indexing already works with Python + Ollama. We just need to package it properly for users.

## Current Working System

### What Already Exists ✅

1. **Python MCP Server** (`vibrant_frog_mcp.py`)
   - ✅ Photo indexing with LLaVA (via Ollama)
   - ✅ ChromaDB vector storage
   - ✅ Semantic photo search
   - ✅ Album management
   - ✅ Photo retrieval by UUID
   - ✅ Face recognition (experimental)

2. **macOS App UI** (Swift)
   - ✅ IndexingView - Shows progress, triggers indexing
   - ✅ PhotoSearchView - Search interface
   - ✅ MCP integration - Can call Python server tools

3. **Infrastructure**
   - ✅ ChromaDB storage: `~/Library/Application Support/VibrantFrogMCP/photo_index`
   - ✅ Ollama LLaVA model for image descriptions
   - ✅ MCP stdio communication working

### What Doesn't Work ❌

1. **LLMService.swift** - Just placeholder code (all TODOs)
2. **EmbeddingStore.swift** - SQLite implementation not used
3. **No easy user setup** - Python dependencies not documented
4. **IndexingView** - May not actually trigger Python indexing
5. **PhotoSearchView** - May not connect to Python search

---

## The Real Problem

**Users can't easily deploy this because:**
1. No clear setup instructions
2. Python dependencies not packaged
3. MCP server not auto-started
4. No integration between Swift UI and Python backend

---

## Production-Ready Solution

### Architecture (What We're Actually Building)

```
┌─────────────────────────────────────────────────────┐
│         VibrantFrog macOS App (Swift)               │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ IndexingView │  │ AI Chat      │  │ Search   │ │
│  │              │  │              │  │ View     │ │
│  │ [Start      │  │ "show beach  │  │ [Query   │ │
│  │  Indexing]  │  │  photos"     │  │  Box]    │ │
│  └──────┬───────┘  └──────┬───────┘  └────┬─────┘ │
│         │                 │                │       │
│         └─────────────────┼────────────────┘       │
│                           ↓                        │
│                  MCPClient (stdio)                 │
│                           ↓                        │
└───────────────────────────┼─────────────────────────┘
                            │ stdio
                            ↓
┌─────────────────────────────────────────────────────┐
│     Python MCP Server (vibrant_frog_mcp.py)         │
│                                                     │
│  Tools:                                             │
│  • index_photo(image_path)      ← IndexingView     │
│  • index_directory(path)        ← IndexingView     │
│  • search_photos(query)         ← SearchView/Chat  │
│  • get_photo(uuid)              ← Display          │
│  • create_album(...)            ← Management       │
│                                                     │
│  Backend:                                           │
│  • Ollama (llava:7b) - Image descriptions          │
│  • ChromaDB - Vector storage & search              │
│  • Photos Library - macOS photo access             │
└─────────────────────────────────────────────────────┘
```

### Strategy: Package Python Server Properly

Since the Python server already works, we just need to make it easy to install and use.

---

## Implementation Plan

### Step 1: Package Python MCP Server

**Create proper package structure:**

```
VibrantFrogMCP/
├── python_mcp_server/
│   ├── __init__.py
│   ├── vibrant_frog_mcp.py      (main MCP server)
│   ├── photo_retrieval.py       (photo access)
│   ├── album_manager.py         (album operations)
│   ├── requirements.txt         (dependencies)
│   ├── setup.py                 (installation)
│   └── README.md                (setup guide)
```

**requirements.txt:**
```txt
# MCP Server
mcp>=0.9.0

# Vector Database
chromadb>=0.4.22
sentence-transformers>=2.2.2

# Image Processing
Pillow>=10.0.0

# Ollama Integration
ollama>=0.1.6

# macOS Photo Library (optional, if using osascript)
# No additional packages needed - uses system APIs
```

**setup.py:**
```python
from setuptools import setup, find_packages

setup(
    name="vibrantfrog-photo-mcp",
    version="1.0.0",
    description="MCP server for VibrantFrog photo search with AI",
    author="SpiderInk",
    packages=find_packages(),
    install_requires=[
        "mcp>=0.9.0",
        "chromadb>=0.4.22",
        "sentence-transformers>=2.2.2",
        "Pillow>=10.0.0",
        "ollama>=0.1.6",
    ],
    entry_points={
        'console_scripts': [
            'vibrantfrog-mcp=vibrant_frog_mcp:main',
        ],
    },
    python_requires='>=3.9',
)
```

### Step 2: Create Installation Script

**install_photo_mcp.sh:**
```bash
#!/bin/bash
set -e

echo "🐸 VibrantFrog Photo MCP Server Installation"
echo "============================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Installation directory
INSTALL_DIR="$HOME/Library/Application Support/VibrantFrog/mcp"
VENV_DIR="$INSTALL_DIR/venv"
PLIST_FILE="$HOME/Library/LaunchAgents/com.spiderink.vibrantfrog.mcp.plist"

echo "📍 Installation directory: $INSTALL_DIR"
echo ""

# Check Python
echo "🔍 Checking Python installation..."
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 not found${NC}"
    echo "Please install Python 3.9+ from https://www.python.org"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo -e "${GREEN}✅ Python $PYTHON_VERSION found${NC}"
echo ""

# Check Ollama
echo "🔍 Checking Ollama installation..."
if ! command -v ollama &> /dev/null; then
    echo -e "${YELLOW}⚠️  Ollama not found${NC}"
    echo "Installing Ollama..."
    brew install ollama || {
        echo -e "${RED}Failed to install Ollama${NC}"
        echo "Please install manually: https://ollama.ai"
        exit 1
    }
fi
echo -e "${GREEN}✅ Ollama installed${NC}"
echo ""

# Start Ollama if not running
echo "🔍 Checking if Ollama is running..."
if ! pgrep -x "ollama" > /dev/null; then
    echo "Starting Ollama service..."
    ollama serve &
    sleep 3
fi
echo -e "${GREEN}✅ Ollama running${NC}"
echo ""

# Pull LLaVA model
echo "📥 Checking LLaVA model..."
if ! ollama list | grep -q "llava:7b"; then
    echo "Downloading LLaVA model (this may take a few minutes)..."
    ollama pull llava:7b
fi
echo -e "${GREEN}✅ LLaVA model ready${NC}"
echo ""

# Create installation directory
echo "📁 Creating installation directory..."
mkdir -p "$INSTALL_DIR"
echo ""

# Create virtual environment
echo "🐍 Setting up Python virtual environment..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
echo ""

# Copy MCP server files
echo "📋 Copying MCP server files..."
cp vibrant_frog_mcp.py "$INSTALL_DIR/"
cp photo_retrieval.py "$INSTALL_DIR/"
cp album_manager.py "$INSTALL_DIR/"
cp python_mcp_server/requirements.txt "$INSTALL_DIR/"
echo ""

# Install dependencies
echo "📦 Installing Python dependencies..."
pip install --upgrade pip
pip install -r "$INSTALL_DIR/requirements.txt"
echo -e "${GREEN}✅ Dependencies installed${NC}"
echo ""

# Create startup script
echo "📝 Creating startup script..."
cat > "$INSTALL_DIR/start_mcp.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
python3 vibrant_frog_mcp.py --transport stdio
EOF
chmod +x "$INSTALL_DIR/start_mcp.sh"
echo ""

# Create LaunchAgent plist
echo "⚙️  Setting up auto-start..."
cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.spiderink.vibrantfrog.mcp</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/start_mcp.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/mcp.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/mcp-error.log</string>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
</dict>
</plist>
EOF
echo ""

# Load LaunchAgent
echo "🚀 Starting MCP server..."
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE"
sleep 2

# Check if running
if pgrep -f "vibrant_frog_mcp.py" > /dev/null; then
    echo -e "${GREEN}✅ MCP server is running${NC}"
else
    echo -e "${YELLOW}⚠️  MCP server may not have started${NC}"
    echo "Check logs at: $INSTALL_DIR/mcp-error.log"
fi
echo ""

echo "============================================="
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "The MCP server will start automatically when you log in."
echo ""
echo "📂 Installation location: $INSTALL_DIR"
echo "📋 Logs: $INSTALL_DIR/mcp.log"
echo "🔧 Config: $PLIST_FILE"
echo ""
echo "Next steps:"
echo "1. Open VibrantFrog"
echo "2. The app should auto-connect to the MCP server"
echo "3. Go to 'Indexing' tab to start indexing your photos"
echo ""
echo "To uninstall:"
echo "  ./uninstall_photo_mcp.sh"
echo ""
```

**uninstall_photo_mcp.sh:**
```bash
#!/bin/bash

INSTALL_DIR="$HOME/Library/Application Support/VibrantFrog/mcp"
PLIST_FILE="$HOME/Library/LaunchAgents/com.spiderink.vibrantfrog.mcp.plist"

echo "🗑️  Uninstalling VibrantFrog Photo MCP Server"
echo ""

# Stop service
if [ -f "$PLIST_FILE" ]; then
    echo "Stopping MCP server..."
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    rm "$PLIST_FILE"
fi

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing installation files..."
    rm -rf "$INSTALL_DIR"
fi

echo "✅ Uninstallation complete"
```

### Step 3: Update Swift App to Auto-Connect

**In VibrantFrogApp.swift or startup:**
```swift
// On app launch, configure MCP server connection
let mcpServerPath = NSHomeDirectory() + "/Library/Application Support/VibrantFrog/mcp"
let scriptPath = mcpServerPath + "/start_mcp.sh"

// Check if MCP server is installed
if FileManager.default.fileExists(atPath: scriptPath) {
    // Configure MCPClient to use stdio
    let mcpServer = MCPServer(
        id: UUID(),
        name: "VibrantFrog Photos",
        serverURL: "", // not used for stdio
        mcpEndpointPath: "",
        transport: .stdio,
        command: "/bin/bash",
        args: [scriptPath]
    )

    // Save to registry and auto-connect
    MCPServerRegistry.shared.addServer(mcpServer)

    // Auto-connect in AIChatView startup
}
```

### Step 4: Wire Up IndexingView to MCP

**Update IndexingView.swift to call MCP tools:**

```swift
// Start indexing button action
private func startIndexing() {
    guard let mcpClient = mcpClient, mcpClient.isConnected else {
        errorMessage = "MCP server not connected"
        return
    }

    isIndexing = true

    Task {
        do {
            // Get Photos library path
            let photosPath = NSHomeDirectory() + "/Pictures/Photos Library.photoslibrary"

            // Call index_directory tool via MCP
            let result = try await mcpClient.callTool(
                name: "index_directory",
                arguments: ["directory_path": photosPath]
            )

            // Parse result and update UI
            await MainActor.run {
                // Update statistics
                updateStatistics()
                isIndexing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isIndexing = false
            }
        }
    }
}
```

### Step 5: Wire Up PhotoSearchView to MCP

**Update PhotoSearchView.swift:**

```swift
private func performSearch() {
    guard !searchText.isEmpty else { return }
    guard let mcpClient = mcpClient, mcpClient.isConnected else {
        // Show error: MCP server not connected
        return
    }

    isSearching = true

    Task {
        do {
            // Call search_photos tool via MCP
            let result = try await mcpClient.callTool(
                name: "search_photos",
                arguments: [
                    "query": searchText,
                    "n_results": 20
                ]
            )

            // Parse results
            let results = parseSearchResults(result)

            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        } catch {
            await MainActor.run {
                self.isSearching = false
                // Show error
            }
        }
    }
}
```

### Step 6: Remove/Document Placeholder Code

**LLMService.swift:**
Add clear comment at top:
```swift
/// NOTE: This is legacy/placeholder code.
/// Photo search currently uses the Python MCP server (vibrant_frog_mcp.py)
/// via Ollama and ChromaDB. See docs/PHOTO_SEARCH_PRODUCTION_PLAN.md
///
/// This service may be implemented in future for standalone Swift operation.
@MainActor
class LLMService: ObservableObject {
    // ... existing placeholder code
}
```

**EmbeddingStore.swift:**
Similar comment explaining it's not currently used.

---

## User Documentation

### README.md Section

```markdown
## Photo Search with AI

VibrantFrog can search your entire photo library using natural language AI.

### Quick Setup (5 minutes)

1. **Install the Photo MCP Server**

   ```bash
   cd VibrantFrog
   ./install_photo_mcp.sh
   ```

   This installs:
   - Python dependencies
   - Ollama LLaVA model
   - Background MCP server

2. **Grant Photo Library Access**
   - Open VibrantFrog
   - Go to "Indexing" tab
   - Click "Grant Access" when prompted

3. **Index Your Photos**
   - Click "Start Indexing" in the Indexing tab
   - First time: ~2-3 seconds per photo
   - The MCP server runs in background
   - You can close VibrantFrog during indexing

4. **Search Your Photos**
   - AI Chat: "show me beach photos from summer"
   - Search tab: Type any description
   - Results show similarity scores

### Example Searches

- "sunset over water"
- "photos of my dog"
- "group photos with 3+ people"
- "pictures taken indoors"
- "food photography"
- "landscape photos with mountains"

### Advanced Features

- **Album Management**: Create albums from search results
- **Face Recognition** (experimental): Find photos of specific people
- **Batch Operations**: Export, share, or organize search results

### Troubleshooting

**"MCP server not connected"**
```bash
# Check if running
pgrep -f vibrant_frog_mcp.py

# Restart
launchctl unload ~/Library/LaunchAgents/com.spiderink.vibrantfrog.mcp.plist
launchctl load ~/Library/LaunchAgents/com.spiderink.vibrantfrog.mcp.plist
```

**Indexing is slow**
- Normal: 2-3 seconds per photo (LLaVA model)
- Uses Ollama in background
- Can continue using app while indexing

**Search returns no results**
- Make sure photos are indexed first
- Try broader search terms
- Check MCP server logs: `~/Library/Application Support/VibrantFrog/mcp/mcp.log`

### Uninstall Photo Search

```bash
./uninstall_photo_mcp.sh
```

This removes the MCP server but keeps VibrantFrog app intact.
```

---

## Release Checklist

### Before v1.0 Release

- [ ] **Create python_mcp_server/ package**
  - [ ] Move Python files to package
  - [ ] Add requirements.txt
  - [ ] Add setup.py
  - [ ] Add README.md

- [ ] **Create installation scripts**
  - [ ] install_photo_mcp.sh
  - [ ] uninstall_photo_mcp.sh
  - [ ] Test on clean Mac

- [ ] **Update Swift app**
  - [ ] Auto-detect MCP server installation
  - [ ] Auto-connect on startup
  - [ ] Wire IndexingView to call MCP tools
  - [ ] Wire PhotoSearchView to call MCP tools
  - [ ] Add connection status indicator

- [ ] **Document placeholder code**
  - [ ] Add comments to LLMService.swift
  - [ ] Add comments to EmbeddingStore.swift
  - [ ] Explain why they're not used

- [ ] **User documentation**
  - [ ] README section on photo search
  - [ ] Installation guide
  - [ ] Troubleshooting guide
  - [ ] Example searches

- [ ] **Testing**
  - [ ] Fresh install on clean Mac
  - [ ] Index 100+ photos
  - [ ] Perform 10 searches
  - [ ] Verify accuracy
  - [ ] Test uninstall

---

## Summary

**What this plan does:**
1. ✅ Packages existing working Python MCP server properly
2. ✅ Creates easy installation script
3. ✅ Auto-starts MCP server as background service
4. ✅ Connects Swift UI to Python backend
5. ✅ Documents everything clearly

**What users get:**
- Run one install script
- Photo search "just works"
- No manual server management
- Clean uninstall option

**Time estimate:**
- Package Python server: 2-3 hours
- Create install scripts: 3-4 hours
- Wire Swift UI: 4-6 hours
- Documentation: 2-3 hours
- Testing: 3-4 hours
- **Total: 2-3 days**

This is the realistic, production-ready approach that leverages what already works.
