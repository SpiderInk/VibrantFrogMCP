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
from mcp.types import Tool, TextContent, ImageContent
import mcp.server.stdio
import sys
import time
import logging
import base64
from photo_retrieval import get_photo_by_uuid, get_photo_path_for_display, cleanup_temp_photo
from album_manager import (
    create_album, delete_album, list_albums, get_album_photo_count,
    add_photos_to_album, remove_photos_from_album, create_album_from_search
)

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
        model='llava:7b',  # Using 7b for better performance (2-3x faster than 13b)
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
        'uuid': results['ids'][0][i],
        'path': results['metadatas'][0][i].get('path', 'N/A'),
        'filename': results['metadatas'][0][i].get('filename', 'Unknown'),
        'description': results['documents'][0][i],
        'distance': results['distances'][0][i]
    } for i in range(len(results['ids'][0]))]

async def get_photo(uuid: str) -> dict:
    """
    Retrieve a photo from Apple Photos Library by UUID.
    Returns image data as base64. Auto-cleans up temp exports.
    """
    start_time = time.time()
    logger.info(f"Retrieving photo with UUID: {uuid}")

    # Get photo metadata
    photo = get_photo_by_uuid(uuid)
    if not photo:
        raise ValueError(f"Photo with UUID {uuid} not found in Apple Photos Library")

    logger.info(f"Found photo: {photo.original_filename}")

    # Get accessible path (exports from iCloud if needed)
    path, needs_cleanup = get_photo_path_for_display(uuid, export_if_needed=True)

    if not path:
        raise ValueError(f"Could not access photo {uuid}. It may not be downloaded from iCloud.")

    try:
        # Read and encode image as base64
        encode_start = time.time()
        with open(path, 'rb') as f:
            image_data = f.read()
        image_base64 = base64.b64encode(image_data).decode('utf-8')
        logger.info(f"Image encoded in {time.time()-encode_start:.2f}s")

        # Determine MIME type
        ext = Path(path).suffix.lower()
        mime_types = {
            '.jpg': 'image/jpeg',
            '.jpeg': 'image/jpeg',
            '.png': 'image/png',
            '.gif': 'image/gif',
            '.webp': 'image/webp',
            '.heic': 'image/heic',
            '.heif': 'image/heif'
        }
        mime_type = mime_types.get(ext, 'image/jpeg')

        result = {
            'uuid': uuid,
            'filename': photo.original_filename,
            'image_data': image_base64,
            'mime_type': mime_type,
            'width': photo.width,
            'height': photo.height,
            'was_exported': needs_cleanup
        }

        logger.info(f"Photo retrieved in {time.time()-start_time:.2f}s total")

        return result

    finally:
        # Always clean up temp exports
        if needs_cleanup:
            cleanup_start = time.time()
            cleanup_temp_photo(path)
            logger.info(f"Temp export cleaned up in {time.time()-cleanup_start:.2f}s")


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
        ),
        Tool(
            name="get_photo",
            description="Retrieve a photo by UUID from Apple Photos Library. Returns the image data. If photo is in iCloud, it will be exported temporarily and cleaned up automatically.",
            inputSchema={
                "type": "object",
                "properties": {
                    "uuid": {
                        "type": "string",
                        "description": "The photo UUID from search results"
                    }
                },
                "required": ["uuid"]
            }
        ),
        Tool(
            name="create_album_from_search",
            description="Search for photos and create a new Apple Photos album with the results. This is the easiest way to create an album - just provide a name and search query.",
            inputSchema={
                "type": "object",
                "properties": {
                    "album_name": {
                        "type": "string",
                        "description": "Name for the new album"
                    },
                    "search_query": {
                        "type": "string",
                        "description": "Natural language search query to find photos (e.g., 'beach sunset vacation')"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of photos to add (default: 100)",
                        "default": 100
                    }
                },
                "required": ["album_name", "search_query"]
            }
        ),
        Tool(
            name="create_album",
            description="Create a new empty album in Apple Photos",
            inputSchema={
                "type": "object",
                "properties": {
                    "album_name": {
                        "type": "string",
                        "description": "Name for the new album"
                    }
                },
                "required": ["album_name"]
            }
        ),
        Tool(
            name="delete_album",
            description="Delete an album from Apple Photos. This only deletes the album, not the photos in it.",
            inputSchema={
                "type": "object",
                "properties": {
                    "album_name": {
                        "type": "string",
                        "description": "Name of the album to delete"
                    }
                },
                "required": ["album_name"]
            }
        ),
        Tool(
            name="list_albums",
            description="List all albums in Apple Photos",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="add_photos_to_album",
            description="Add photos to an existing Apple Photos album using their UUIDs from search results",
            inputSchema={
                "type": "object",
                "properties": {
                    "album_name": {
                        "type": "string",
                        "description": "Name of the album to add photos to"
                    },
                    "photo_uuids": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of photo UUIDs to add to the album"
                    }
                },
                "required": ["album_name", "photo_uuids"]
            }
        ),
        Tool(
            name="remove_photos_from_album",
            description="Remove photos from an Apple Photos album (does not delete the photos themselves)",
            inputSchema={
                "type": "object",
                "properties": {
                    "album_name": {
                        "type": "string",
                        "description": "Name of the album to remove photos from"
                    },
                    "photo_uuids": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of photo UUIDs to remove from the album"
                    }
                },
                "required": ["album_name", "photo_uuids"]
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
                photo_uri = f"photos://asset?uuid={r['uuid']}"
                output += f"{i}. {r['filename']}\n"
                output += f"   UUID: {r['uuid']}\n"
                output += f"   Link: {photo_uri}\n"
                output += f"   Path: {r['path']}\n"
                output += f"   Description: {r['description']}\n"
                output += f"   Relevance: {1 - r['distance']:.2f}\n\n"

            output += "\nTo view a photo, click the Link or use the get_photo tool with the UUID."

            return [TextContent(type="text", text=output)]
        
        elif name == "index_directory":
            indexed = await index_directory(arguments["directory_path"])
            return [TextContent(
                type="text",
                text=f"Indexed {len(indexed)} photos from {arguments['directory_path']}"
            )]

        elif name == "get_photo":
            result = await get_photo(arguments["uuid"])

            # Return image as ImageContent for proper display in Claude Desktop
            return [
                ImageContent(
                    type="image",
                    data=result['image_data'],
                    mimeType=result['mime_type']
                ),
                TextContent(
                    type="text",
                    text=f"Photo: {result['filename']}\nSize: {result['width']}x{result['height']}\n" +
                         ("(Exported from iCloud and cleaned up)" if result['was_exported'] else "(Local file)")
                )
            ]

        elif name == "create_album_from_search":
            result = create_album_from_search(
                arguments["album_name"],
                arguments["search_query"],
                arguments.get("limit", 100)
            )
            return [TextContent(type="text", text=result['message'])]

        elif name == "create_album":
            result = create_album(arguments["album_name"])
            return [TextContent(type="text", text=result['message'])]

        elif name == "delete_album":
            result = delete_album(arguments["album_name"])
            return [TextContent(type="text", text=result['message'])]

        elif name == "list_albums":
            result = list_albums()
            if result['success']:
                output = f"Found {result['count']} albums:\n\n"
                for album in result['albums']:
                    output += f"  - {album}\n"
                return [TextContent(type="text", text=output)]
            else:
                return [TextContent(type="text", text=f"Error listing albums: {result.get('message', 'Unknown error')}")]

        elif name == "add_photos_to_album":
            result = add_photos_to_album(
                arguments["album_name"],
                arguments["photo_uuids"]
            )
            return [TextContent(type="text", text=result['message'])]

        elif name == "remove_photos_from_album":
            result = remove_photos_from_album(
                arguments["album_name"],
                arguments["photo_uuids"]
            )
            return [TextContent(type="text", text=result['message'])]

        else:
            raise ValueError(f"Unknown tool: {name}")
            
    except Exception as e:
        print(f"Error in {name}: {e}", file=sys.stderr)
        return [TextContent(type="text", text=f"Error: {str(e)}")]

async def main():
    import argparse

    parser = argparse.ArgumentParser(description='VibrantFrog MCP Server')
    parser.add_argument('--transport', choices=['stdio', 'http'], default='stdio',
                       help='Transport mode: stdio (for Claude Desktop) or http (for VibrantFrog app)')
    parser.add_argument('--host', default='127.0.0.1',
                       help='HTTP host (only used with --transport http)')
    parser.add_argument('--port', type=int, default=5050,
                       help='HTTP port (only used with --transport http)')

    args = parser.parse_args()

    if args.transport == 'stdio':
        print("Starting MCP server in stdio mode...", file=sys.stderr)
        async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
            await app.run(
                read_stream,
                write_stream,
                app.create_initialization_options()
            )
    else:  # http - Using Streamable HTTP transport (MCP 2025-03-26)
        print(f"Starting MCP server in Streamable HTTP mode on {args.host}:{args.port}...", file=sys.stderr)
        from starlette.applications import Starlette
        from starlette.routing import Route
        from starlette.responses import JSONResponse, Response
        from starlette.requests import Request
        import uvicorn
        import uuid

        # Session management
        sessions = {}  # session_id -> session_data

        async def handle_mcp_post(request: Request):
            """Handle POST requests to /mcp endpoint (Streamable HTTP)"""
            try:
                # Get session ID if provided
                session_id = request.headers.get("mcp-session-id")

                # Parse JSON-RPC request
                body = await request.json()

                # Check if this is an initialize request
                if body.get("method") == "initialize":
                    # Create new session
                    session_id = str(uuid.uuid4())
                    sessions[session_id] = {"initialized": True}

                    # Create response
                    result = {
                        "jsonrpc": "2.0",
                        "id": body.get("id"),
                        "result": {
                            "protocolVersion": "2024-11-05",
                            "capabilities": {
                                "tools": {}
                            },
                            "serverInfo": {
                                "name": app.name,
                                "version": "1.0.0"
                            }
                        }
                    }

                    # Return JSON response with session ID header
                    return JSONResponse(
                        result,
                        headers={"Mcp-Session-Id": session_id}
                    )

                # Handle tools/list
                elif body.get("method") == "tools/list":
                    tools = await list_tools()
                    result = {
                        "jsonrpc": "2.0",
                        "id": body.get("id"),
                        "result": {
                            "tools": [
                                {
                                    "name": t.name,
                                    "description": t.description,
                                    "inputSchema": t.inputSchema
                                }
                                for t in tools
                            ]
                        }
                    }
                    return JSONResponse(result)

                # Handle tools/call
                elif body.get("method") == "tools/call":
                    params = body.get("params", {})
                    tool_name = params.get("name")
                    arguments = params.get("arguments", {})

                    # Call the tool
                    content_list = await call_tool(tool_name, arguments)

                    # Convert to proper format
                    result = {
                        "jsonrpc": "2.0",
                        "id": body.get("id"),
                        "result": {
                            "content": [
                                {
                                    "type": c.type,
                                    "text": getattr(c, 'text', None),
                                    "data": getattr(c, 'data', None),
                                    "mimeType": getattr(c, 'mimeType', None)
                                }
                                for c in content_list
                            ]
                        }
                    }
                    return JSONResponse(result)

                # Handle notifications (no response needed)
                elif "id" not in body:
                    return Response(status_code=202)  # Accepted

                # Unknown method
                else:
                    return JSONResponse({
                        "jsonrpc": "2.0",
                        "id": body.get("id"),
                        "error": {
                            "code": -32601,
                            "message": f"Method not found: {body.get('method')}"
                        }
                    })

            except Exception as e:
                logger.error(f"Error handling MCP request: {e}")
                return JSONResponse({
                    "jsonrpc": "2.0",
                    "id": body.get("id") if hasattr(body, 'get') else None,
                    "error": {
                        "code": -32603,
                        "message": f"Internal error: {str(e)}"
                    }
                }, status_code=500)

        async def handle_mcp_get(request: Request):
            """Handle GET requests to /mcp endpoint (SSE stream for server messages)"""
            # Check if client wants SSE
            accept = request.headers.get("accept", "")
            if "text/event-stream" not in accept:
                return Response(status_code=405, content="GET requires Accept: text/event-stream")

            # Return SSE stream
            async def event_stream():
                """Generate SSE events for server-initiated messages"""
                # Keep connection alive with periodic heartbeat
                try:
                    while True:
                        # Send keepalive comment every 30 seconds
                        yield f": keepalive\n\n"
                        await asyncio.sleep(30)
                except Exception as e:
                    logger.error(f"SSE stream error: {e}")

            from starlette.responses import StreamingResponse
            return StreamingResponse(
                event_stream(),
                media_type="text/event-stream",
                headers={
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                    "X-Accel-Buffering": "no"
                }
            )

        # CORS middleware for browser clients (MCP Inspector)
        from starlette.middleware.cors import CORSMiddleware

        async def handle_mcp_options(_request: Request):
            """Handle OPTIONS requests for CORS preflight"""
            return Response(
                status_code=200,
                headers={
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Accept, Mcp-Session-Id",
                    "Access-Control-Max-Age": "86400"
                }
            )

        starlette_app = Starlette(
            routes=[
                Route("/mcp", endpoint=handle_mcp_post, methods=["POST"]),
                Route("/mcp", endpoint=handle_mcp_get, methods=["GET"]),
                Route("/mcp", endpoint=handle_mcp_options, methods=["OPTIONS"]),
            ]
        )

        # Add CORS middleware
        starlette_app = CORSMiddleware(
            starlette_app,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["GET", "POST", "OPTIONS"],
            allow_headers=["*"],
        )

        config = uvicorn.Config(
            starlette_app,
            host=args.host,
            port=args.port,
            log_level="info"
        )
        server = uvicorn.Server(config)
        await server.serve()

if __name__ == "__main__":
    asyncio.run(main())