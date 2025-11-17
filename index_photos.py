#!/usr/bin/env python3
"""
Script to poll Apple Photos Library and index new photos
"""
import asyncio
import json
import tempfile
from pathlib import Path
from datetime import datetime
import os
import osxphotos
import ollama
import chromadb
from chromadb.utils import embedding_functions
import time
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Same DB path as MCP server
DB_PATH = os.path.expanduser("~/Library/Application Support/VibrantFrogMCP/photo_index")
INDEXED_CACHE = Path(DB_PATH).parent / "indexed_photos.json"

# Initialize ChromaDB (same as MCP server)
chroma_client = chromadb.PersistentClient(path=DB_PATH)
embedding_function = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name="all-MiniLM-L6-v2"
)
collection = chroma_client.get_or_create_collection(
    name="photos",
    embedding_function=embedding_function
)

async def describe_image(image_path: str) -> str:
    """Use LLaVA to generate rich description of image"""
    start_time = time.time()
    logger.info(f"Starting LLaVA description generation for {os.path.basename(image_path)}")

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
    logger.info(f"LLaVA description completed in {elapsed:.2f}s")

    return response['message']['content']

def load_indexed_cache():
    """Load set of already-indexed photo UUIDs"""
    if INDEXED_CACHE.exists():
        with open(INDEXED_CACHE) as f:
            return set(json.load(f))
    return set()

def save_indexed_cache(indexed_uuids):
    """Save indexed photo UUIDs"""
    INDEXED_CACHE.parent.mkdir(parents=True, exist_ok=True)
    with open(INDEXED_CACHE, 'w') as f:
        json.dump(list(indexed_uuids), f)

def get_photo_path(photo):
    """Get accessible path for photo, trying multiple methods"""
    start_time = time.time()

    # Try direct path first (fastest if available)
    if photo.path and os.path.exists(photo.path):
        logger.debug(f"Using direct path ({time.time()-start_time:.2f}s)")
        return photo.path, False  # (path, needs_cleanup)

    # Try edited version
    if photo.path_edited and os.path.exists(photo.path_edited):
        logger.debug(f"Using edited version ({time.time()-start_time:.2f}s)")
        return photo.path_edited, False

    # Try derivatives
    if photo.path_derivatives:
        for deriv_path in photo.path_derivatives:
            if os.path.exists(deriv_path):
                logger.debug(f"Using derivative path ({time.time()-start_time:.2f}s)")
                return deriv_path, False

    # Last resort: export to temp directory
    # This handles iCloud photos and other inaccessible formats
    try:
        logger.info("Attempting to export iCloud photo to temp directory...")
        export_start = time.time()
        temp_dir = tempfile.mkdtemp()
        exported = photo.export(temp_dir, timeout=30)
        if exported:
            logger.info(f"Photo export completed in {time.time()-export_start:.2f}s")
            return exported[0], True  # (path, needs_cleanup)
    except Exception as e:
        logger.error(f"Export failed after {time.time()-start_time:.2f}s: {e}")

    return None, False

def clean_metadata(metadata):
    """Convert lists and unsupported types to valid ChromaDB metadata"""
    cleaned = {}
    for key, value in metadata.items():
        if isinstance(value, list):
            # Convert list to comma-separated string, or None if empty
            cleaned[key] = ', '.join(str(v) for v in value) if value else None
        elif value is None or isinstance(value, (str, int, float, bool)):
            cleaned[key] = value
        else:
            # Convert other types to string
            cleaned[key] = str(value)
    
    # Remove None values if you prefer
    return {k: v for k, v in cleaned.items() if v is not None}

async def index_photo_with_metadata(photo):
    """Index a photo with Apple Photos metadata"""
    overall_start = time.time()
    try:
        logger.info(f"🔍 Processing: {photo.original_filename}")

        # Step 1: Get photo path
        path_start = time.time()
        photo_path, needs_cleanup = get_photo_path(photo)
        path_elapsed = time.time() - path_start
        logger.info(f"  ├─ Photo path resolution: {path_elapsed:.2f}s")

        if not photo_path:
            logger.warning(f"⚠️  Skipping {photo.original_filename}: No accessible path")
            return None

        # Step 2: Generate description using vision model
        description_start = time.time()
        description = await describe_image(photo_path)
        description_elapsed = time.time() - description_start
        logger.info(f"  ├─ Description generation: {description_elapsed:.2f}s")

        # Clean up temp file if we exported
        if needs_cleanup:
            try:
                os.remove(photo_path)
                os.rmdir(os.path.dirname(photo_path))
            except:
                pass

        # Step 3: Build metadata
        metadata_start = time.time()

        # Determine orientation
        orientation = "square"
        if photo.width and photo.height:
            if photo.width > photo.height * 1.1:  # 10% tolerance
                orientation = "landscape"
            elif photo.height > photo.width * 1.1:
                orientation = "portrait"

        metadata = {
            'uuid': photo.uuid,  # PRIMARY KEY for retrieval
            'path': photo.path if photo.path else None,  # Local path if available
            'path_edited': photo.path_edited if photo.path_edited else None,  # Edited version path
            'filename': photo.original_filename,
            'description': description,
            'date': photo.date.isoformat() if photo.date else None,
            'location': f"{photo.place.name}" if photo.place else None,
            'albums': [album.title for album in photo.albums],
            'keywords': photo.keywords,
            'favorite': photo.favorite,
            'width': photo.width,
            'height': photo.height,
            'orientation': orientation,  # Calculated orientation
            'cloud_asset': photo.iscloudasset,  # Important: indicates if photo needs iCloud download
            'has_adjustments': photo.hasadjustments  # Indicates if photo has been edited
        }

        # Create searchable text combining everything
        searchable_text = f"{description}"
        if photo.keywords:
            searchable_text += f"\nKeywords: {', '.join(photo.keywords)}"
        if photo.place:
            searchable_text += f"\nLocation: {photo.place.name}"
        if photo.albums:
            searchable_text += f"\nAlbums: {', '.join([a.title for a in photo.albums])}"

        metadata = clean_metadata(metadata)
        metadata_elapsed = time.time() - metadata_start
        logger.info(f"  ├─ Metadata preparation: {metadata_elapsed:.2f}s")

        # Step 4: Store in vector DB
        # Use upsert instead of add to handle reindexing (updates if exists, adds if new)
        db_start = time.time()
        collection.upsert(
            documents=[searchable_text],
            ids=[photo.uuid],
            metadatas=[metadata]
        )
        db_elapsed = time.time() - db_start
        logger.info(f"  ├─ ChromaDB upsert: {db_elapsed:.2f}s")

        overall_elapsed = time.time() - overall_start
        logger.info(f"  └─ Total time: {overall_elapsed:.2f}s")
        logger.info(f"✅ Indexed: {photo.original_filename}")

        return photo.uuid

    except Exception as e:
        overall_elapsed = time.time() - overall_start
        logger.error(f"❌ Error indexing {photo.original_filename} after {overall_elapsed:.2f}s: {e}")
        import traceback
        traceback.print_exc()
        return None

async def poll_and_index(limit=None, skip_indexed=True, include_cloud=True, reverse_chronological=True):
    """
    Poll Apple Photos and index new photos

    Args:
        limit: Maximum number of photos to process in this batch
        skip_indexed: Skip photos already in cache
        include_cloud: Include iCloud photos (not just local)
        reverse_chronological: Start with newest photos first (recommended)
    """
    session_start = time.time()

    logger.info("📷 Opening Apple Photos Library...")
    photosdb = osxphotos.PhotosDB()

    # Load cache of already-indexed photos
    indexed_uuids = load_indexed_cache() if skip_indexed else set()
    logger.info(f"📊 Found {len(indexed_uuids)} already indexed photos")

    # Get all photos (images only, not videos)
    photos = photosdb.photos(images=True, movies=False)
    logger.info(f"📊 Total photos in library: {len(photos)}")

    # Sort by date (newest first if reverse_chronological)
    if reverse_chronological:
        # Sort by date descending (newest first), handling None dates
        photos = sorted(photos, key=lambda p: p.date if p.date else datetime.min, reverse=True)
        logger.info(f"📊 Sorted by date (newest first)")
        if photos and photos[0].date:
            logger.info(f"   Newest: {photos[0].date.strftime('%Y-%m-%d')} - {photos[0].original_filename}")
        if photos and photos[-1].date:
            logger.info(f"   Oldest: {photos[-1].date.strftime('%Y-%m-%d')} - {photos[-1].original_filename}")
    else:
        # Sort by date ascending (oldest first)
        photos = sorted(photos, key=lambda p: p.date if p.date else datetime.max)
        logger.info(f"📊 Sorted by date (oldest first)")

    # Filter cloud assets if requested
    if not include_cloud:
        photos = [p for p in photos if not p.iscloudasset]
        logger.info(f"📊 Local photos only: {len(photos)}")

    # Filter out already indexed
    if skip_indexed:
        photos = [p for p in photos if p.uuid not in indexed_uuids]
        logger.info(f"📊 New photos to index: {len(photos)}")

    # Apply limit if specified
    if limit:
        photos = photos[:limit]
        logger.info(f"📊 Processing batch of {limit} photos (out of {len(photos)} remaining)")

    # Index photos
    newly_indexed = []

    for i, photo in enumerate(photos, 1):
        logger.info(f"\n{'='*60}")
        logger.info(f"[{i}/{len(photos)}] Starting photo processing")
        photo_start = time.time()

        uuid = await index_photo_with_metadata(photo)
        if uuid:
            newly_indexed.append(uuid)
            indexed_uuids.add(uuid)
            # Save cache immediately after each successful index
            save_indexed_cache(indexed_uuids)
            logger.info(f"💾 Cache saved - {len(indexed_uuids)} total indexed")

        photo_elapsed = time.time() - photo_start
        avg_time = (time.time() - session_start) / i
        estimated_remaining = avg_time * (len(photos) - i)

        logger.info(f"Photo {i} completed in {photo_elapsed:.2f}s")
        logger.info(f"Average time per photo: {avg_time:.2f}s")
        logger.info(f"Estimated time remaining: {estimated_remaining/60:.1f} minutes")

    # Final save
    save_indexed_cache(indexed_uuids)

    session_elapsed = time.time() - session_start
    logger.info(f"\n{'='*60}")
    logger.info(f"✨ Done! Indexed {len(newly_indexed)} new photos")
    logger.info(f"📊 Total indexed: {len(indexed_uuids)}")
    logger.info(f"⏱️  Total session time: {session_elapsed/60:.1f} minutes")
    if newly_indexed:
        logger.info(f"⏱️  Average time per photo: {session_elapsed/len(newly_indexed):.2f}s")

if __name__ == "__main__":
    import sys

    # Parse command-line arguments
    limit = None
    include_cloud = True
    reverse_chronological = True  # Default: newest first

    # Show usage if --help
    if '--help' in sys.argv or '-h' in sys.argv:
        print("""
VibrantFrog Photo Indexer
==========================

Index photos from Apple Photos Library with AI-powered descriptions.

Usage:
    python index_photos.py [LIMIT] [OPTIONS]

Arguments:
    LIMIT                   Number of photos to process (default: all unindexed)

Options:
    --local-only           Only index local photos (skip iCloud)
    --oldest-first         Start with oldest photos instead of newest
    --help, -h             Show this help message

Examples:
    # Index 500 newest photos
    python index_photos.py 500

    # Index 100 oldest unindexed photos
    python index_photos.py 100 --oldest-first

    # Index all local photos (no iCloud), newest first
    python index_photos.py --local-only

    # Index 1000 photos in batches of 500
    python index_photos.py 500  # Run once
    python index_photos.py 500  # Run again (continues from where it left off)

Tips:
    - Indexing is SLOW (~2-3 min per photo with llava:7b)
    - Start with recent photos (default) to get useful results quickly
    - Use batches of 500 for manageable sessions
    - Can safely Ctrl+C anytime - progress is saved after each photo
    - Re-run same command to continue where you left off

Performance:
    500 photos ≈ 16-25 hours
    1000 photos ≈ 33-50 hours
    5000 photos ≈ 7-10 days (run in batches!)
        """)
        sys.exit(0)

    # Parse arguments
    for arg in sys.argv[1:]:
        if arg == '--local-only':
            include_cloud = False
        elif arg == '--oldest-first':
            reverse_chronological = False
        elif arg.isdigit():
            limit = int(arg)

    # Run indexing
    asyncio.run(poll_and_index(
        limit=limit,
        include_cloud=include_cloud,
        reverse_chronological=reverse_chronological
    ))