# vibrant_frog_mcp.py
import asyncio
import os
from pathlib import Path
from typing import Optional
import chromadb
from chromadb.utils import embedding_functions
import ollama
from PIL import Image
from mcp.server import Server
from mcp.types import Tool, TextContent
import mcp.server.stdio
import sys
import time
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    stream=sys.stderr
)
logger = logging.getLogger(__name__)

# Use absolute path in user's home directory
DB_PATH = os.path.expanduser("~/Library/Application Support/VibrantFrogMCP/photo_index")
os.makedirs(DB_PATH, exist_ok=True)

# Global variables for lazy initialization
chroma_client = None
collection = None

def get_collection():
    """Lazy-load ChromaDB collection to avoid startup timeout"""
    global chroma_client, collection

    if collection is None:
        start_time = time.time()
        logger.info("Initializing ChromaDB...")
        chroma_client = chromadb.PersistentClient(path=DB_PATH)

        logger.info("Loading embedding function...")
        embedding_start = time.time()
        embedding_function = embedding_functions.SentenceTransformerEmbeddingFunction(
            model_name="all-MiniLM-L6-v2"
        )
        logger.info(f"Embedding function loaded in {time.time()-embedding_start:.2f}s")

        logger.info("Getting collection...")
        collection_start = time.time()
        collection = chroma_client.get_or_create_collection(
            name="photos",
            embedding_function=embedding_function
        )
        logger.info(f"Collection loaded in {time.time()-collection_start:.2f}s")
        logger.info(f"ChromaDB initialized in {time.time()-start_time:.2f}s total")

    return collection

async def describe_image(image_path: str) -> str:
    """Use LLaVA to generate rich description of image"""
    start_time = time.time()
    logger.info(f"Generating description for {os.path.basename(image_path)}")

    prompt = """Describe this image in comprehensive detail, including:
- Main subjects and objects present
- Colors and lighting (bright, dim, warm tones, cool tones, etc.)
- Composition and framing (close-up, wide shot, rule of thirds, etc.)
- Image orientation (landscape, portrait, square)
- Image quality (sharp, blurry, well-exposed, underexposed, etc.)
- Mood and atmosphere (cheerful, somber, energetic, calm, etc.)
- Setting and background elements
- Any notable features, patterns, or textures
- Activities or actions taking place
Be specific and detailed to enable accurate searching."""

    response = ollama.chat(
        model='llava:13b',
        messages=[{
            'role': 'user',
            'content': prompt,
            'images': [image_path]
        }]
    )

    elapsed = time.time() - start_time
    logger.info(f"Description generated in {elapsed:.2f}s")

    return response['message']['content']

async def index_photo(image_path: str) -> dict:
    """Index a single photo"""
    overall_start = time.time()
    path = Path(image_path)

    if not path.exists():
        raise FileNotFoundError(f"Image not found: {image_path}")

    logger.info(f"Indexing photo: {path.name}")

    # Generate description
    description_start = time.time()
    description = await describe_image(image_path)
    logger.info(f"Description step: {time.time()-description_start:.2f}s")

    # Get collection (lazy init)
    collection_start = time.time()
    coll = get_collection()
    logger.info(f"Collection retrieval: {time.time()-collection_start:.2f}s")

    # Store in vector DB (upsert = update if exists, add if new)
    db_start = time.time()
    coll.upsert(
        documents=[description],
        ids=[str(path.absolute())],
        metadatas=[{
            'path': str(path.absolute()),
            'filename': path.name,
            'description': description
        }]
    )
    logger.info(f"Database upsert: {time.time()-db_start:.2f}s")
    logger.info(f"Total indexing time: {time.time()-overall_start:.2f}s")

    return {
        'path': image_path,
        'description': description
    }

async def search_photos(query: str, n_results: int = 5) -> list:
    """Search photos by natural language query"""
    start_time = time.time()
    logger.info(f"Searching for: '{query}' (max {n_results} results)")

    # Get collection (lazy init)
    coll = get_collection()

    query_start = time.time()
    results = coll.query(
        query_texts=[query],
        n_results=n_results
    )
    logger.info(f"Vector search completed in {time.time()-query_start:.2f}s")

    if not results['ids'][0]:
        logger.info("No results found")
        return []

    logger.info(f"Found {len(results['ids'][0])} results in {time.time()-start_time:.2f}s total")

    return [{
        'path': results['metadatas'][0][i]['path'],
        'filename': results['metadatas'][0][i]['filename'],
        'description': results['documents'][0][i],
        'distance': results['distances'][0][i]
    } for i in range(len(results['ids'][0]))]

async def index_directory(directory_path: str) -> list:
    """Recursively index all photos in a directory"""
    start_time = time.time()
    directory = Path(directory_path)
    image_extensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'}

    logger.info(f"Indexing directory: {directory_path}")

    # Count total images first
    image_files = [img for img in directory.rglob('*') if img.suffix.lower() in image_extensions]
    logger.info(f"Found {len(image_files)} images to index")

    indexed = []
    for i, img_path in enumerate(image_files, 1):
        try:
            logger.info(f"[{i}/{len(image_files)}] Processing {img_path.name}")
            result = await index_photo(str(img_path))
            indexed.append(result)
        except Exception as e:
            logger.error(f"Error indexing {img_path}: {e}")

    elapsed = time.time() - start_time
    logger.info(f"Directory indexing complete: {len(indexed)} photos in {elapsed:.1f}s")
    if indexed:
        logger.info(f"Average: {elapsed/len(indexed):.2f}s per photo")

    return indexed

# Create MCP server
app = Server("vibrant-frog-mcp", "Vibrant Frog MCP for Apple Photo Library Indexing and Search")

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
    try:
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
            
            if not results:
                return [TextContent(type="text", text="No photos found matching your query.")]
            
            output = f"Found {len(results)} photos:\n\n"
            for i, r in enumerate(results, 1):
                output += f"{i}. {r['filename']}\n"
                output += f"   Path: {r['path']}\n"
                output += f"   Description: {r['description']}\n"
                output += f"   Relevance: {1 - r['distance']:.2f}\n\n"
            
            return [TextContent(type="text", text=output)]
        
        elif name == "index_directory":
            indexed = await index_directory(arguments["directory_path"])
            return [TextContent(
                type="text",
                text=f"Indexed {len(indexed)} photos from {arguments['directory_path']}"
            )]
        
        else:
            raise ValueError(f"Unknown tool: {name}")
            
    except Exception as e:
        print(f"Error in {name}: {e}", file=sys.stderr)
        return [TextContent(type="text", text=f"Error: {str(e)}")]

async def main():
    print("Starting MCP server...", file=sys.stderr)
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options()
        )

if __name__ == "__main__":
    asyncio.run(main())