# VibrantFrog MCP Server Setup Guide

This guide explains how to set up and use the VibrantFrog Photo Search MCP server.

## Overview

VibrantFrog includes a **Python-based MCP server** (`vibrant_frog_mcp.py`) that provides AI-powered photo search capabilities. This server can be used in two ways:

1. **With VibrantFrog app** - Search photos directly in the chat interface
2. **With Claude Desktop** - Use photo search tools in Claude Desktop

## Prerequisites

- macOS 14.0 or later
- Python 3.10 or later
- Apple Photos library with photos
- Ollama with a model that supports embeddings (e.g., `nomic-embed-text`)

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/SpiderInk/VibrantFrogMCP.git
cd VibrantFrogMCP
```

### 2. Set Up Python Environment

```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### 3. Install Ollama Model for Embeddings

```bash
# Install Ollama if you haven't already
brew install ollama

# Start Ollama service
ollama serve

# Pull the embedding model (in a new terminal)
ollama pull nomic-embed-text
```

## Usage

### Option 1: Use with VibrantFrog App

#### Step 1: Start the MCP Server

```bash
cd /path/to/VibrantFrogMCP
source venv/bin/activate
python3 vibrant_frog_mcp.py --transport http
```

You should see:
```
Starting MCP server on http://127.0.0.1:5050
Server is ready to accept connections
```

#### Step 2: Configure VibrantFrog

1. Launch VibrantFrog.app
2. Go to the **"MCP Server"** tab
3. The **"VibrantFrog Photos"** server should be listed (pre-configured)
4. Check the status indicator - it should show **green (Connected)**
5. Click **"Refresh"** to load available tools
6. You should see 12 photo-related tools

#### Step 3: Index Your Photos (First Time Only)

1. Go to the **"Indexing"** tab
2. Click **"Start Indexing"**
3. This will:
   - Scan your Apple Photos library
   - Generate AI descriptions for each photo
   - Create vector embeddings for semantic search
   - This may take a while depending on library size

#### Step 4: Start Searching

1. Go to the **"AI Chat"** tab
2. Select **"VibrantFrog Photos"** from the MCP server dropdown
3. Select **"Photo Assistant"** prompt template
4. Ask natural language questions:
   - "Show me pictures of the beach"
   - "Find photos from my last vacation"
   - "Search for pictures with dogs"
   - "Find sunset photos from 2024"

### Option 2: Use with Claude Desktop

#### Step 1: Configure Claude Desktop

Edit your Claude Desktop config file:
```bash
code ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

Add the VibrantFrog MCP server:
```json
{
  "mcpServers": {
    "vibrantfrog-photos": {
      "command": "python3",
      "args": [
        "/absolute/path/to/VibrantFrogMCP/vibrant_frog_mcp.py"
      ]
    }
  }
}
```

**Important:** Replace `/absolute/path/to/` with your actual path!

#### Step 2: Restart Claude Desktop

Close and reopen Claude Desktop. The MCP server will start automatically.

#### Step 3: Use in Claude Desktop

In Claude Desktop, you can now:
- "Search my photos for beaches"
- "Find pictures from last summer"
- "Create an album called 'Best Sunset Photos' and add sunset pictures to it"

Claude will automatically use the photo search tools when relevant.

## Available Tools

The MCP server provides these tools:

### Photo Search
- **`search_photos`** - Search photos using natural language queries
  - Supports semantic search (meaning-based)
  - Returns photo UUIDs and thumbnails
  - Example: "beach sunset" or "dogs playing in the park"

- **`get_photo`** - Retrieve a specific photo by UUID
  - Returns full photo data including image data
  - Used for displaying photos in chat

### Album Management
- **`create_album`** - Create a new Apple Photos album
- **`create_album_from_search`** - Search for photos and create an album with results
- **`list_albums`** - List all albums in your library
- **`add_photos_to_album`** - Add photos to an existing album
- **`remove_photos_from_album`** - Remove photos from an album
- **`delete_album`** - Delete an album (photos remain in library)

### Photo Analysis
- **`get_info_status`** - Check indexing status
- **`start_indexing_job`** - Start or resume photo indexing
- **`cancel_job`** - Cancel running indexing job

## Troubleshooting

### Server Won't Start

**Problem:** `ModuleNotFoundError: No module named 'starlette'`

**Solution:**
```bash
source venv/bin/activate
pip install -r requirements.txt
```

### Connection Failed in VibrantFrog

**Problem:** Status shows "Unknown" or "Error" in red

**Solution:**
1. Verify the Python server is running: `ps aux | grep vibrant_frog_mcp`
2. Check the server logs for errors
3. Verify the port is correct: `http://127.0.0.1:5050/mcp`
4. Try restarting the server

### No Photos Found

**Problem:** Search returns no results

**Solution:**
1. Make sure you've indexed your photos (go to "Indexing" tab)
2. Check that Ollama is running: `ollama list`
3. Verify `nomic-embed-text` model is installed
4. Try re-indexing: Click "Start Indexing" again

### Claude Desktop Can't Find MCP Server

**Problem:** MCP server doesn't appear in Claude Desktop

**Solution:**
1. Verify the config file path is correct
2. Use **absolute paths**, not relative paths
3. Restart Claude Desktop completely
4. Check Claude Desktop logs: `~/Library/Logs/Claude/`

## Advanced Configuration

### Change Server Port

Edit `vibrant_frog_mcp.py` and change:
```python
PORT = 5050  # Change to your desired port
```

Then update the URL in VibrantFrog's MCP Server settings.

### Use Different Embedding Model

Edit `vibrant_frog_mcp.py` and change:
```python
EMBEDDING_MODEL = "nomic-embed-text"  # Change to another model
```

Make sure to pull the model first: `ollama pull your-model-name`

### Customize Index Location

By default, the photo index is stored in:
```
~/Library/Application Support/VibrantFrogMCP/photo_index/
```

For the newer SQLite-based shared index, it's stored in:
```
~/VibrantFrogPhotoIndex/photo_index.db
```

To change this, edit `vibrant_frog_mcp.py` and update the `INDEX_DIR` variable (for ChromaDB) or modify `shared_index.py` for the SQLite path.

## Performance Tips

1. **Initial indexing** can take a while (10-30 minutes for 10,000 photos)
2. **Keep Ollama running** for faster searches
3. **Use SSD storage** for better indexing performance
4. **Large libraries** (50k+ photos) may benefit from a more powerful embedding model

## Security & Privacy

- All photo processing happens **locally on your Mac**
- No data is sent to external servers
- Photo embeddings are stored locally
- The MCP server only listens on `localhost` (127.0.0.1)

## Additional Resources

- [MCP Protocol Documentation](https://modelcontextprotocol.io)
- [Ollama Documentation](https://ollama.ai/docs)
- [VibrantFrog GitHub Issues](https://github.com/SpiderInk/VibrantFrogMCP/issues)

## Questions?

- Open an issue: https://github.com/SpiderInk/VibrantFrogMCP/issues
- Discussions: https://github.com/SpiderInk/VibrantFrogMCP/discussions
