This is a great project! Here's a solid approach to build a local photo search MCP server on your Mac:

## Recommended Stack

**Vision Model**: Use **LLaVA via Ollama** - it's optimized for Mac (including Apple Silicon), easy to set up, and produces excellent image descriptions.

**Vector DB**: **ChromaDB** - lightweight, Python-native, perfect for local deployment, and has excellent embedding support.

**MCP**: Python-based MCP server using the `mcp` package.

## Setup Steps

### 1. Install Dependencies

```bash
# Install Ollama (if not already installed)
brew install ollama

# Pull a vision model (llava is good balance of quality/speed)
ollama pull llava:13b  # or llava:7b for faster inference

# Install Python packages
pip install mcp chromadb pillow ollama sentence-transformers
```

### 2. MCP Server Structure

Here's a basic implementation:

```python
# photo_search_mcp.py
import asyncio
import base64
from pathlib import Path
from typing import Optional
import chromadb
from chromadb.utils import embedding_functions
import ollama
from PIL import Image
from mcp.server import Server
from mcp.types import Tool, TextContent
import mcp.server.stdio

# Initialize ChromaDB
chroma_client = chromadb.PersistentClient(path="./photo_index")
embedding_function = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name="all-MiniLM-L6-v2"
)

collection = chroma_client.get_or_create_collection(
    name="photos",
    embedding_function=embedding_function
)

async def describe_image(image_path: str) -> str:
    """Use LLaVA to generate rich description of image"""
    response = ollama.chat(
        model='llava:13b',
        messages=[{
            'role': 'user',
            'content': 'Describe this image in detail, including objects, colors, mood, composition, and any notable features:',
            'images': [image_path]
        }]
    )
    return response['message']['content']

async def index_photo(image_path: str) -> dict:
    """Index a single photo"""
    path = Path(image_path)
    
    # Generate description
    description = await describe_image(image_path)
    
    # Store in vector DB
    collection.add(
        documents=[description],
        ids=[str(path.absolute())],
        metadatas=[{
            'path': str(path.absolute()),
            'filename': path.name,
            'description': description
        }]
    )
    
    return {
        'path': image_path,
        'description': description
    }

async def search_photos(query: str, n_results: int = 5) -> list:
    """Search photos by natural language query"""
    results = collection.query(
        query_texts=[query],
        n_results=n_results
    )
    
    return [{
        'path': results['metadatas'][0][i]['path'],
        'filename': results['metadatas'][0][i]['filename'],
        'description': results['documents'][0][i],
        'distance': results['distances'][0][i]
    } for i in range(len(results['ids'][0]))]

# Create MCP server
app = Server("photo-search")

@app.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="index_photo",
            description="Index a photo by generating a rich description and storing it in the vector database",
            inputSchema={
                "type": "object",
                "properties": {
                    "image_path": {
                        "type": "string",
                        "description": "Absolute path to the image file"
                    }
                },
                "required": ["image_path"]
            }
        ),
        Tool(
            name="search_photos",
            description="Search indexed photos using natural language queries",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Natural language search query"
                    },
                    "n_results": {
                        "type": "integer",
                        "description": "Number of results to return (default: 5)",
                        "default": 5
                    }
                },
                "required": ["query"]
            }
        ),
        Tool(
            name="index_directory",
            description="Recursively index all photos in a directory",
            inputSchema={
                "type": "object",
                "properties": {
                    "directory_path": {
                        "type": "string",
                        "description": "Path to directory containing photos"
                    }
                },
                "required": ["directory_path"]
            }
        )
    ]

@app.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    if name == "index_photo":
        result = await index_photo(arguments["image_path"])
        return [TextContent(
            type="text",
            text=f"Indexed: {result['path']}\nDescription: {result['description']}"
        )]
    
    elif name == "search_photos":
        results = await search_photos(
            arguments["query"],
            arguments.get("n_results", 5)
        )
        
        output = f"Found {len(results)} photos:\n\n"
        for i, r in enumerate(results, 1):
            output += f"{i}. {r['filename']}\n"
            output += f"   Path: {r['path']}\n"
            output += f"   Description: {r['description']}\n"
            output += f"   Relevance: {1 - r['distance']:.2f}\n\n"
        
        return [TextContent(type="text", text=output)]
    
    elif name == "index_directory":
        directory = Path(arguments["directory_path"])
        image_extensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'}
        
        indexed = []
        for img_path in directory.rglob('*'):
            if img_path.suffix.lower() in image_extensions:
                result = await index_photo(str(img_path))
                indexed.append(result)
        
        return [TextContent(
            type="text",
            text=f"Indexed {len(indexed)} photos from {directory}"
        )]

async def main():
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options()
        )

if __name__ == "__main__":
    asyncio.run(main())
```

### 3. Claude Desktop Configuration

Add to your `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "photo-search": {
      "command": "python",
      "args": ["/path/to/photo_search_mcp.py"]
    }
  }
}
```

## Alternative Vision Models

If LLaVA isn't meeting your needs:
- **Moondream2** - faster, smaller, still via Ollama (`ollama pull moondream`)
- **Bakllava** - LLaVA variant optimized for Mac (`ollama pull bakllava`)
- **llama.cpp with vision** - more control, requires building from source

## Enhanced Features You Could Add

1. **EXIF metadata extraction** - combine with image descriptions
2. **Face detection/recognition** - using local models
3. **Batch processing with progress** - for large photo libraries
4. **Incremental updates** - only process new/modified photos
5. **Multiple vector spaces** - separate collections for different types of searches

This gives you a fully local, privacy-preserving photo search system accessible through Claude via MCP. Want me to elaborate on any part or help with the integration?