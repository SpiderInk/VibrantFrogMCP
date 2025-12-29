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
import uuid
from datetime import datetime
from photo_retrieval import get_photo_by_uuid, get_photo_path_for_display, cleanup_temp_photo
from album_manager import (
    create_album, delete_album, list_albums, get_album_photo_count,
    add_photos_to_album, remove_photos_from_album, create_album_from_search
)
from index_photos import (
    index_photo_with_metadata,
    load_indexed_cache,
    save_indexed_cache,
    describe_image as index_photos_describe_image
)
import osxphotos

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

# Job Management State
indexing_jobs = {}
job_cancel_flags = {}

class IndexingJob:
    """Represents an indexing job with progress tracking for Apple Photos Library"""
    def __init__(self, job_id: str, batch_size: Optional[int] = None, reverse_chronological: bool = True, include_cloud: bool = True):
        self.job_id = job_id
        self.batch_size = batch_size
        self.reverse_chronological = reverse_chronological
        self.include_cloud = include_cloud
        self.status = "pending"  # pending, running, completed, failed, cancelled
        self.total_photos = 0
        self.processed_photos = 0
        self.current_photo = None
        self.started_at = None
        self.completed_at = None
        self.error = None
        self.indexed_uuids = []

    def to_dict(self):
        """Convert job to dictionary for JSON serialization"""
        return {
            "job_id": self.job_id,
            "batch_size": self.batch_size,
            "reverse_chronological": self.reverse_chronological,
            "include_cloud": self.include_cloud,
            "status": self.status,
            "total_photos": self.total_photos,
            "processed_photos": self.processed_photos,
            "current_photo": self.current_photo,
            "progress_percent": (
                round((self.processed_photos / self.total_photos * 100), 2)
                if self.total_photos > 0 else 0
            ),
            "started_at": self.started_at.isoformat() if self.started_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "error": self.error
        }

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

# Use the comprehensive describe_image and index_photo_with_metadata from index_photos.py
# These functions handle Apple Photos Library integration, HEIC conversion,
# rich metadata, caching, etc.

async def search_photos(query: str, n_results: int = 5) -> list:
    """Search photos by natural language query using semantic vector search"""
    start_time = time.time()
    logger.info(f"Searching for: '{query}' (max {n_results} results)")

    # Use SQLite database with semantic search
    from shared_index import SharedPhotoIndex
    import sqlite3
    import json
    import numpy as np

    shared_index = SharedPhotoIndex()

    try:
        # Generate embedding for search query
        logger.info("Generating query embedding...")
        embed_start = time.time()
        from sentence_transformers import SentenceTransformer

        # Use same model as indexing (all-MiniLM-L6-v2)
        model = SentenceTransformer('all-MiniLM-L6-v2')
        query_embedding = model.encode(query).tolist()
        logger.info(f"Query embedding generated in {time.time()-embed_start:.2f}s")

        # Load all embeddings from database and compute cosine similarity
        query_start = time.time()
        conn = sqlite3.connect(shared_index.db_path)
        cursor = conn.cursor()

        # Fetch all photos with embeddings
        cursor.execute("""
            SELECT uuid, description, embedding, indexed_at
            FROM photo_index
            WHERE embedding IS NOT NULL
        """)

        rows = cursor.fetchall()
        conn.close()

        logger.info(f"Loaded {len(rows)} photos with embeddings in {time.time()-query_start:.2f}s")

        if not rows:
            logger.info("No photos with embeddings found")
            return []

        # Calculate cosine similarity for each photo
        similarities = []
        query_vec = np.array(query_embedding)
        query_norm = np.linalg.norm(query_vec)

        for uuid, description, embedding_json, indexed_at in rows:
            try:
                # Parse embedding from JSON
                embedding = json.loads(embedding_json)
                photo_vec = np.array(embedding)

                # Cosine similarity = dot(a,b) / (norm(a) * norm(b))
                similarity = np.dot(query_vec, photo_vec) / (query_norm * np.linalg.norm(photo_vec))

                similarities.append({
                    'uuid': uuid,
                    'description': description,
                    'similarity': float(similarity),
                    'distance': 1.0 - float(similarity)  # Convert to distance for compatibility
                })
            except Exception as e:
                logger.warning(f"Failed to parse embedding for {uuid}: {e}")
                continue

        # Sort by similarity (highest first) and take top N
        similarities.sort(key=lambda x: x['similarity'], reverse=True)
        top_results = similarities[:n_results]

        logger.info(f"Semantic search completed in {time.time()-start_time:.2f}s total")
        logger.info(f"Top result similarity: {top_results[0]['similarity']:.4f}" if top_results else "No results")

        # Get photo metadata from osxphotos for each result
        import osxphotos
        photosdb = osxphotos.PhotosDB()

        results = []
        for result in top_results:
            # Try to get photo from library
            photo = photosdb.get_photo(result['uuid'])
            if photo:
                results.append({
                    'uuid': result['uuid'],
                    'path': photo.path if photo.path else 'N/A',
                    'filename': photo.original_filename,
                    'description': result['description'],
                    'distance': result['distance'],
                    'similarity': result['similarity']
                })
            else:
                # Photo not found in library, but still return description
                results.append({
                    'uuid': result['uuid'],
                    'path': 'N/A',
                    'filename': 'Unknown',
                    'description': result['description'],
                    'distance': result['distance'],
                    'similarity': result['similarity']
                })

        return results

    except Exception as e:
        logger.error(f"Error in semantic search: {e}")
        # Fallback to ChromaDB if semantic search fails
        logger.warning("Falling back to ChromaDB search")
        coll = get_collection()
        query_start = time.time()
        results = coll.query(
            query_texts=[query],
            n_results=n_results
        )
        logger.info(f"ChromaDB fallback search completed in {time.time()-query_start:.2f}s")

        if not results['ids'][0]:
            return []

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


async def run_indexing_job_background(job_id: str):
    """
    Background task to run Apple Photos Library indexing with progress tracking.
    Writes to SQLite database for iCloud sync compatibility.
    This allows the MCP tool to return immediately while indexing continues.
    """
    job = indexing_jobs[job_id]
    job.status = "running"
    job.started_at = datetime.now()

    logger.info(f"🚀 Starting background Apple Photos indexing job {job_id}")
    logger.info(f"📝 Writing to SQLite database for iCloud sync")

    try:
        # Initialize shared SQLite index (instead of ChromaDB)
        from shared_index import SharedPhotoIndex
        shared_index = SharedPhotoIndex()
        logger.info(f"📊 SQLite database initialized at: {shared_index.db_path}")

        # Open Apple Photos Library
        logger.info("📷 Opening Apple Photos Library...")
        photosdb = osxphotos.PhotosDB()

        # Load cache of already-indexed photos
        indexed_uuids = load_indexed_cache()
        logger.info(f"📊 Found {len(indexed_uuids)} already indexed photos")

        # Get all photos (images only, not videos)
        photos = photosdb.photos(images=True, movies=False)
        logger.info(f"📊 Total photos in library: {len(photos)}")

        # Sort by date (newest first if reverse_chronological)
        if job.reverse_chronological:
            photos = sorted(photos, key=lambda p: p.date if p.date else datetime.min, reverse=True)
            logger.info(f"📊 Sorted by date (newest first)")
        else:
            photos = sorted(photos, key=lambda p: p.date if p.date else datetime.max)
            logger.info(f"📊 Sorted by date (oldest first)")

        # Filter cloud assets if requested
        if not job.include_cloud:
            photos = [p for p in photos if not p.iscloudasset]
            logger.info(f"📊 Local photos only: {len(photos)}")

        # Filter out already indexed
        photos = [p for p in photos if p.uuid not in indexed_uuids]
        logger.info(f"📊 New photos to index: {len(photos)}")

        # Apply batch limit if specified
        if job.batch_size:
            photos = photos[:job.batch_size]
            logger.info(f"📊 Processing batch of {job.batch_size} photos")

        job.total_photos = len(photos)

        # Index each photo to SQLite
        for i, photo in enumerate(photos):
            # Check for cancellation
            if job_cancel_flags.get(job_id, False):
                logger.info(f"Job {job_id} cancelled by user")
                job.status = "cancelled"
                job.completed_at = datetime.now()
                # Save cache before exiting
                save_indexed_cache(indexed_uuids)
                return

            try:
                job.current_photo = photo.original_filename
                job.processed_photos = i

                logger.info(f"[{i+1}/{job.total_photos}] Processing {photo.original_filename}")

                # Import iCloud indexing function
                from index_photos_icloud import index_photo_to_icloud

                # Index the photo to SQLite
                uuid_result = await index_photo_to_icloud(photo, shared_index)

                if uuid_result:
                    job.indexed_uuids.append(uuid_result)
                    indexed_uuids.add(uuid_result)
                    # Save cache immediately after each successful index
                    save_indexed_cache(indexed_uuids)
                    logger.info(f"💾 Cache saved - {len(indexed_uuids)} total indexed")

                # Update progress
                job.processed_photos = i + 1

            except Exception as e:
                logger.error(f"Error indexing {photo.original_filename}: {e}")
                # Continue with next photo even if one fails

        # Job completed successfully
        job.status = "completed"
        job.completed_at = datetime.now()

        # Final cache save
        save_indexed_cache(indexed_uuids)

        elapsed = (job.completed_at - job.started_at).total_seconds()
        logger.info(f"✅ Job {job_id} completed: {job.processed_photos}/{job.total_photos} photos in {elapsed:.1f}s")
        logger.info(f"📊 Total indexed: {len(indexed_uuids)}")

        # Create CloudKit sync flag
        create_cloudkit_sync_flag(shared_index.db_path, len(indexed_uuids))

    except Exception as e:
        logger.error(f"❌ Job {job_id} failed: {e}")
        import traceback
        traceback.print_exc()
        job.status = "failed"
        job.error = str(e)
        job.completed_at = datetime.now()


def create_cloudkit_sync_flag(db_path: str, photo_count: int):
    """Create flag file to trigger CloudKit upload"""
    import json
    from pathlib import Path

    db_path_obj = Path(db_path)
    flag_path = db_path_obj.parent / ".needs-cloudkit-sync"

    flag_data = {
        "database_path": str(db_path_obj),
        "database_size": db_path_obj.stat().st_size if db_path_obj.exists() else 0,
        "timestamp": datetime.now().isoformat(),
        "photo_count": photo_count
    }

    flag_path.write_text(json.dumps(flag_data, indent=2))
    logger.info(f"✅ Created CloudKit sync flag: {flag_path}")
    logger.info(f"   Database: {db_path}")
    logger.info(f"   Size: {flag_data['database_size']:,} bytes")
    logger.info(f"   Photos: {photo_count}")

# Create MCP server
app = Server("vibrant-frog-mcp", "Vibrant Frog MCP for Apple Photo Library Indexing and Search")

@app.list_tools()
async def list_tools() -> list[Tool]:
    return [
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
        ),
        Tool(
            name="start_indexing_job",
            description="Start a background Apple Photos Library indexing job. Returns immediately with a job_id that can be used to poll for progress. This is the recommended way to index your photo library. By default, indexes newest photos first and skips already-indexed photos.",
            inputSchema={
                "type": "object",
                "properties": {
                    "batch_size": {
                        "type": "integer",
                        "description": "Optional: Limit number of photos to index. If not specified, indexes all unindexed photos. Recommended: 100-500 for manageable sessions."
                    },
                    "reverse_chronological": {
                        "type": "boolean",
                        "description": "Optional: Start with newest photos first (default: true). Set to false to index oldest photos first.",
                        "default": True
                    },
                    "include_cloud": {
                        "type": "boolean",
                        "description": "Optional: Include iCloud photos (default: true). Set to false to only index local photos.",
                        "default": True
                    }
                },
                "required": []
            }
        ),
        Tool(
            name="get_job_status",
            description="Get the current status and progress of an indexing job",
            inputSchema={
                "type": "object",
                "properties": {
                    "job_id": {
                        "type": "string",
                        "description": "The job ID returned from start_indexing_job"
                    }
                },
                "required": ["job_id"]
            }
        ),
        Tool(
            name="cancel_job",
            description="Cancel a running indexing job. The job will stop after the current photo completes.",
            inputSchema={
                "type": "object",
                "properties": {
                    "job_id": {
                        "type": "string",
                        "description": "The job ID to cancel"
                    }
                },
                "required": ["job_id"]
            }
        ),
        Tool(
            name="list_jobs",
            description="List all indexing jobs (running, completed, and failed)",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        )
    ]

@app.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    try:
        if name == "search_photos":
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

        elif name == "start_indexing_job":
            # Create new job
            job_id = str(uuid.uuid4())
            batch_size = arguments.get("batch_size")
            reverse_chronological = arguments.get("reverse_chronological", True)
            include_cloud = arguments.get("include_cloud", True)

            job = IndexingJob(
                job_id=job_id,
                batch_size=batch_size,
                reverse_chronological=reverse_chronological,
                include_cloud=include_cloud
            )
            indexing_jobs[job_id] = job
            job_cancel_flags[job_id] = False

            # Start background task
            asyncio.create_task(run_indexing_job_background(job_id))

            logger.info(f"Created Apple Photos indexing job {job_id}")

            sort_order = "newest first" if reverse_chronological else "oldest first"
            cloud_status = "including iCloud" if include_cloud else "local only"

            return [TextContent(
                type="text",
                text=f"Apple Photos indexing job started!\n\nJob ID: {job_id}\nBatch size: {batch_size if batch_size else 'all unindexed photos'}\nSort: {sort_order}\nScope: {cloud_status}\n\nUse get_job_status with this job_id to check progress.\n\nNote: Indexing is slow (~2-3 min per photo with LLaVA). The job will skip photos that are already indexed."
            )]

        elif name == "get_job_status":
            job_id = arguments["job_id"]

            if job_id not in indexing_jobs:
                return [TextContent(type="text", text=f"Job {job_id} not found")]

            job = indexing_jobs[job_id]
            job_dict = job.to_dict()

            # Format status message
            output = f"Job Status: {job_dict['status'].upper()}\n\n"
            output += f"Job ID: {job_dict['job_id']}\n"
            output += f"Source: Apple Photos Library\n"
            output += f"Progress: {job_dict['processed_photos']}/{job_dict['total_photos']} photos ({job_dict['progress_percent']}%)\n"

            if job_dict['current_photo']:
                output += f"Current: {job_dict['current_photo']}\n"

            if job_dict['started_at']:
                output += f"Started: {job_dict['started_at']}\n"

            if job_dict['completed_at']:
                output += f"Completed: {job_dict['completed_at']}\n"

            if job_dict['error']:
                output += f"\nError: {job_dict['error']}\n"

            return [TextContent(type="text", text=output)]

        elif name == "cancel_job":
            job_id = arguments["job_id"]

            if job_id not in indexing_jobs:
                return [TextContent(type="text", text=f"Job {job_id} not found")]

            job_cancel_flags[job_id] = True
            logger.info(f"Cancellation requested for job {job_id}")

            return [TextContent(
                type="text",
                text=f"Cancellation requested for job {job_id}. The job will stop after the current photo completes."
            )]

        elif name == "list_jobs":
            if not indexing_jobs:
                return [TextContent(type="text", text="No indexing jobs found.")]

            output = f"Total jobs: {len(indexing_jobs)}\n\n"

            for job_id, job in indexing_jobs.items():
                job_dict = job.to_dict()
                output += f"Job {job_id[:8]}...\n"
                output += f"  Status: {job_dict['status']}\n"
                output += f"  Progress: {job_dict['processed_photos']}/{job_dict['total_photos']} ({job_dict['progress_percent']}%)\n"
                output += f"  Source: Apple Photos Library\n"
                output += "\n"

            return [TextContent(type="text", text=output)]

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