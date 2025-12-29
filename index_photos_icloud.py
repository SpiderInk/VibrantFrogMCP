#!/usr/bin/env python3
"""
Index photos to shared iCloud database

This script indexes Apple Photos to a shared iCloud Drive database
that can be accessed by VibrantFrog Collab on iOS/Mac.
"""

import asyncio
import sys
import time
import logging
import json
import subprocess
from pathlib import Path
import osxphotos

# Import shared index module
from shared_index import SharedPhotoIndex
from index_photos import (
    describe_image,
    get_photo_path,
    restart_ollama,
    get_ollama_memory_usage,
    log_memory_to_file
)

# Import embedding function
from chromadb.utils import embedding_functions

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Initialize embedding function (same as ChromaDB version)
embedding_function = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name="all-MiniLM-L6-v2"
)


def get_cloud_identifiers_batch(uuids: list) -> dict:
    """
    Get PHCloudIdentifiers for a batch of photo UUIDs using Swift helper.

    Args:
        uuids: List of photo UUIDs

    Returns:
        Dictionary mapping UUID -> cloud_identifier_string
    """
    if not uuids:
        return {}

    try:
        script_path = Path(__file__).parent / "get_cloud_identifiers.swift"
        result = subprocess.run(
            ["swift", str(script_path)] + uuids,
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            logger.warning(f"Cloud identifier fetch failed: {result.stderr}")
            return {}
    except Exception as e:
        logger.warning(f"Failed to get cloud identifiers: {e}")
        return {}


async def index_photo_to_icloud(photo, shared_index: SharedPhotoIndex, cloud_guid: str = None):
    """
    Index a single photo to iCloud shared database.

    Args:
        photo: osxphotos.PhotoInfo object
        shared_index: SharedPhotoIndex instance

    Returns:
        photo.uuid if successful, None otherwise
    """
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

        # Step 2: Generate description using LLaVA
        description_start = time.time()
        description = await describe_image(photo_path)
        description_elapsed = time.time() - description_start
        logger.info(f"  ├─ Description generation: {description_elapsed:.2f}s")

        # Clean up temp file if needed
        if needs_cleanup:
            try:
                import os
                os.remove(photo_path)
                os.rmdir(os.path.dirname(photo_path))
            except:
                pass

        # Step 3: Generate embedding
        embedding_start = time.time()

        # Create searchable text
        searchable_text = description
        if photo.keywords:
            searchable_text += f"\nKeywords: {', '.join(photo.keywords)}"
        if photo.place:
            searchable_text += f"\nLocation: {photo.place.name}"
        if photo.albums:
            try:
                album_titles = [a.title if hasattr(a, 'title') else str(a) for a in photo.albums]
                searchable_text += f"\nAlbums: {', '.join(album_titles)}"
            except:
                pass

        # Generate embedding
        embedding = embedding_function([searchable_text])[0]  # Returns list of vectors
        embedding_elapsed = time.time() - embedding_start
        logger.info(f"  ├─ Embedding generation: {embedding_elapsed:.2f}s")

        # Step 4: Store in iCloud database (with cloud_guid if provided)
        db_start = time.time()
        success = shared_index.index_photo(photo, description, embedding.tolist(), cloud_guid=cloud_guid)
        db_elapsed = time.time() - db_start
        logger.info(f"  ├─ iCloud database write: {db_elapsed:.2f}s")

        if not success:
            logger.error(f"  └─ Failed to write to database")
            return None

        overall_elapsed = time.time() - overall_start
        logger.info(f"  └─ Total time: {overall_elapsed:.2f}s")
        logger.info(f"✅ Indexed to iCloud: {photo.original_filename}")

        return photo.uuid

    except Exception as e:
        overall_elapsed = time.time() - overall_start
        logger.error(f"❌ Error indexing {photo.original_filename} after {overall_elapsed:.2f}s: {e}")
        import traceback
        traceback.print_exc()
        return None


async def poll_and_index_icloud(
    limit=None,
    skip_indexed=True,
    include_cloud=True,
    reverse_chronological=True
):
    """
    Poll Apple Photos and index new photos to iCloud.

    Args:
        limit: Maximum number of photos to process
        skip_indexed: Skip photos already in shared index
        include_cloud: Include iCloud photos
        reverse_chronological: Start with newest photos first
    """
    session_start = time.time()

    logger.info("=" * 60)
    logger.info("VibrantFrogMCP → iCloud Photo Indexing")
    logger.info("=" * 60)
    logger.info("")

    # Initialize shared index
    logger.info("☁️  Connecting to iCloud Drive...")
    try:
        shared_index = SharedPhotoIndex()
        stats = shared_index.get_stats()
        logger.info(f"✅ Connected to shared index")
        logger.info(f"   Current photos: {stats['total_photos']}")
        logger.info(f"   Database size: {stats['database_size_mb']} MB")
        logger.info(f"   Last updated: {stats.get('last_updated', 'Never')}")
    except Exception as e:
        logger.error(f"❌ Failed to connect to iCloud: {e}")
        logger.error("Make sure iCloud Drive is enabled in System Settings")
        return

    # Open Apple Photos Library
    logger.info("\n📷 Opening Apple Photos Library...")
    photosdb = osxphotos.PhotosDB()

    # Get already-indexed photos
    indexed_uuids = shared_index.get_indexed_uuids() if skip_indexed else set()
    logger.info(f"📊 Found {len(indexed_uuids)} already indexed photos")

    # Get all photos
    photos = photosdb.photos(images=True, movies=False)
    logger.info(f"📊 Total photos in library: {len(photos)}")

    # Sort by date
    from datetime import datetime as dt
    if reverse_chronological:
        photos = sorted(photos, key=lambda p: p.date if p.date else dt.min, reverse=True)
        logger.info(f"📊 Sorted by date (newest first)")
        if photos and photos[0].date:
            logger.info(f"   Newest: {photos[0].date.strftime('%Y-%m-%d')} - {photos[0].original_filename}")
    else:
        photos = sorted(photos, key=lambda p: p.date if p.date else dt.max)
        logger.info(f"📊 Sorted by date (oldest first)")

    # Filter cloud assets if requested
    if not include_cloud:
        photos = [p for p in photos if not p.iscloudasset]
        logger.info(f"📊 Local photos only: {len(photos)}")

    # Filter out already indexed
    if skip_indexed:
        photos = [p for p in photos if p.uuid not in indexed_uuids]
        logger.info(f"📊 New photos to index: {len(photos)}")

    # Apply limit
    if limit:
        photos = photos[:limit]
        logger.info(f"📊 Processing batch of {limit} photos")

    if not photos:
        logger.info("\n✅ No new photos to index!")
        logger.info("\nRun with --help for options")
        return

    # Index photos
    newly_indexed = []

    # Log initial Ollama memory
    mem, procs = get_ollama_memory_usage()
    if mem is not None:
        logger.info(f"\n📊 Initial Ollama memory usage: {mem:.1f} MB")

    logger.info(f"\n{'='*60}")
    logger.info(f"Starting indexing of {len(photos)} photos")
    logger.info(f"{'='*60}\n")

    for i, photo in enumerate(photos, 1):
        logger.info(f"\n[{i}/{len(photos)}] Starting photo processing")
        photo_start = time.time()

        # Auto-restart Ollama every 500 photos
        if i > 1 and i % 500 == 0:
            logger.info(f"\n{'='*60}")
            logger.info(f"🔄 Reached {i} photos - preventive Ollama restart")
            restart_ollama()
            logger.info(f"{'='*60}\n")

        # Index photo
        uuid = await index_photo_to_icloud(photo, shared_index)

        if uuid:
            newly_indexed.append(uuid)
            indexed_uuids.add(uuid)

        # Progress stats
        photo_elapsed = time.time() - photo_start
        avg_time = (time.time() - session_start) / i
        estimated_remaining = avg_time * (len(photos) - i)

        logger.info(f"Photo {i} completed in {photo_elapsed:.2f}s")
        logger.info(f"Average time per photo: {avg_time:.2f}s")
        logger.info(f"Estimated time remaining: {estimated_remaining/60:.1f} minutes")

    # Final stats
    session_elapsed = time.time() - session_start
    logger.info(f"\n{'='*60}")
    logger.info(f"✨ Done! Indexed {len(newly_indexed)} new photos")
    logger.info(f"📊 Total indexed: {len(indexed_uuids)}")
    logger.info(f"⏱️  Total session time: {session_elapsed/60:.1f} minutes")
    if newly_indexed:
        logger.info(f"⏱️  Average time per photo: {session_elapsed/len(newly_indexed):.2f}s")

    # Show updated stats
    stats = shared_index.get_stats()
    logger.info(f"\n☁️  iCloud Database:")
    logger.info(f"   Total photos: {stats['total_photos']}")
    logger.info(f"   Database size: {stats['database_size_mb']} MB")
    logger.info(f"   Path: {stats['database_path']}")

    logger.info(f"\n📱 Photos will sync to VibrantFrog Collab automatically")
    logger.info(f"   Open the app to search!")
    logger.info(f"{'='*60}\n")


if __name__ == "__main__":
    # Parse command-line arguments
    limit = None
    include_cloud = True
    reverse_chronological = True

    if '--help' in sys.argv or '-h' in sys.argv:
        print("""
VibrantFrogMCP → iCloud Photo Indexer
======================================

Index photos from Apple Photos Library directly to iCloud Drive,
making them searchable in VibrantFrog Collab on iOS/Mac.

Usage:
    python index_photos_icloud.py [LIMIT] [OPTIONS]

Arguments:
    LIMIT                   Number of photos to process (default: all unindexed)

Options:
    --local-only           Only index local photos (skip iCloud)
    --oldest-first         Start with oldest photos instead of newest
    --stats                Show current index statistics
    --help, -h             Show this help message

Examples:
    # Show current statistics
    python index_photos_icloud.py --stats

    # Index 100 newest photos
    python index_photos_icloud.py 100

    # Index 50 oldest unindexed photos
    python index_photos_icloud.py 50 --oldest-first

    # Index all local photos (no iCloud), newest first
    python index_photos_icloud.py --local-only

Features:
    ☁️  Indexes directly to iCloud Drive
    📱 Photos appear in VibrantFrog Collab automatically
    💾 Progress saved after each photo (safe to Ctrl+C)
    🔄 Incremental indexing (only new photos)
    🎯 Smart caching (skip already-indexed photos)

Requirements:
    - iCloud Drive enabled
    - Ollama running with llava:7b model
    - Apple Photos library access

Performance:
    ~2-3 minutes per photo with llava:7b
    Run in batches for long indexing sessions
        """)
        sys.exit(0)

    # Show stats
    if '--stats' in sys.argv:
        try:
            shared_index = SharedPhotoIndex()
            stats = shared_index.get_stats()

            print("\n" + "="*60)
            print("☁️  iCloud Photo Index Statistics")
            print("="*60)
            print(f"Total Photos:     {stats['total_photos']}")
            print(f"Favorites:        {stats.get('favorites', 0)}")
            print(f"iCloud Photos:    {stats.get('cloud_photos', 0)}")
            print(f"Last Updated:     {stats.get('last_updated', 'Never')}")
            print(f"Embedding Model:  {stats.get('embedding_model', 'Unknown')}")
            print(f"Database Size:    {stats['database_size_mb']} MB")
            print(f"Database Path:    {stats['database_path']}")
            print("="*60)
            print("\n📱 Open VibrantFrog Collab to search photos")
            print()
        except Exception as e:
            print(f"❌ Error: {e}")
            print("Make sure iCloud Drive is enabled")
        sys.exit(0)

    # Parse other arguments
    for arg in sys.argv[1:]:
        if arg == '--local-only':
            include_cloud = False
        elif arg == '--oldest-first':
            reverse_chronological = False
        elif arg.isdigit():
            limit = int(arg)

    # Run indexing
    asyncio.run(poll_and_index_icloud(
        limit=limit,
        include_cloud=include_cloud,
        reverse_chronological=reverse_chronological
    ))

    # Trigger CloudKit sync after successful indexing
    try:
        from trigger_cloudkit_sync import trigger_sync
        print("\n📤 Triggering CloudKit sync...")
        trigger_sync()
    except Exception as e:
        print(f"⚠️  Could not trigger CloudKit sync: {e}")
        print("   (This is optional - you can manually upload from the Mac app)")
