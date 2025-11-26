#!/usr/bin/env python3
"""
Face Recognition Indexer for VibrantFrog MCP

Reads existing photos from ChromaDB, detects faces using InsightFace,
and stores face embeddings in a separate collection.

This script is designed to run AFTER index_photos.py has completed indexing.
It adds face recognition data to existing photo records without re-running
the expensive LLaVA description generation.

Usage:
    python index_faces.py [LIMIT] [OPTIONS]

Arguments:
    LIMIT                   Number of photos to process (default: all unprocessed)

Options:
    --reindex               Reprocess photos that already have face data
    --min-confidence 0.5    Minimum face detection confidence (default: 0.5)
    --help, -h              Show this help message

Examples:
    # Process all photos that don't have face data yet
    python index_faces.py

    # Process 100 photos
    python index_faces.py 100

    # Reprocess all photos (useful if you want better face detection)
    python index_faces.py --reindex

    # Only detect high-confidence faces
    python index_faces.py --min-confidence 0.8

Performance:
    Expected: 0.5-1 second per photo on M2 Pro with Neural Engine
    21,000 photos ≈ 3-6 hours total
"""

import os
import sys
import time
import logging
from pathlib import Path
import chromadb
from chromadb.utils import embedding_functions
import cv2
import numpy as np

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Same DB path as main indexer
DB_PATH = os.path.expanduser("~/Library/Application Support/VibrantFrogMCP/photo_index")

def check_insightface():
    """Check if InsightFace is installed and provide installation instructions"""
    try:
        from insightface.app import FaceAnalysis
        return True
    except ImportError:
        logger.error("InsightFace not installed!")
        logger.error("")
        logger.error("To install InsightFace and dependencies:")
        logger.error("  pip install insightface onnxruntime opencv-python")
        logger.error("")
        logger.error("For M2 Pro optimization (recommended):")
        logger.error("  pip install onnxruntime-coreml")
        logger.error("")
        return False

def initialize_face_detector():
    """Initialize InsightFace with optimal settings for M2 Pro"""
    from insightface.app import FaceAnalysis

    logger.info("Initializing InsightFace face detector...")
    start_time = time.time()

    # Try to use CoreML (M2 Neural Engine) first, fallback to CPU
    try:
        app = FaceAnalysis(providers=['CoreMLExecutionProvider', 'CPUExecutionProvider'])
        logger.info("Using CoreML (Neural Engine) for face detection")
    except:
        app = FaceAnalysis(providers=['CPUExecutionProvider'])
        logger.info("Using CPU for face detection (slower)")

    # Prepare with optimal detection size
    # det_size=(640, 640) is a good balance of speed and accuracy
    app.prepare(ctx_id=0, det_size=(640, 640))

    logger.info(f"Face detector initialized in {time.time()-start_time:.2f}s")
    return app

def process_photo_for_faces(photo_metadata, face_app, faces_collection, min_confidence=0.5):
    """
    Detect faces in a photo and store embeddings

    Returns:
        (num_faces, processing_time)
    """
    start_time = time.time()
    photo_uuid = photo_metadata['uuid']

    # Get photo path (try multiple sources)
    photo_path = None
    for path_key in ['path', 'path_edited']:
        if path_key in photo_metadata and photo_metadata[path_key]:
            potential_path = photo_metadata[path_key]
            if os.path.exists(potential_path):
                photo_path = potential_path
                break

    if not photo_path:
        logger.warning(f"⚠️  Photo path not found for {photo_uuid}")
        return 0, time.time() - start_time

    # Handle HEIC conversion (same as main indexer)
    if photo_path.lower().endswith('.heic') or photo_path.lower().endswith('.heif'):
        import tempfile
        import subprocess

        temp_dir = tempfile.mkdtemp()
        jpeg_path = os.path.join(temp_dir, Path(photo_path).stem + '.jpg')

        result = subprocess.run(
            ['sips', '-s', 'format', 'jpeg', photo_path, '--out', jpeg_path],
            capture_output=True,
            timeout=30
        )

        if result.returncode == 0 and os.path.exists(jpeg_path):
            photo_path = jpeg_path
            cleanup_needed = True
        else:
            logger.warning(f"⚠️  HEIC conversion failed for {photo_uuid}")
            return 0, time.time() - start_time
    else:
        cleanup_needed = False

    try:
        # Load image
        img = cv2.imread(photo_path)
        if img is None:
            logger.warning(f"⚠️  Could not load image: {photo_path}")
            return 0, time.time() - start_time

        # Detect faces
        faces = face_app.get(img)

        # Filter by confidence
        faces = [f for f in faces if f.det_score >= min_confidence]

        # Store each face
        face_ids = []
        face_embeddings = []
        face_metadatas = []

        for i, face in enumerate(faces):
            face_id = f"{photo_uuid}_face_{i}"

            face_ids.append(face_id)
            face_embeddings.append(face.embedding.tolist())
            face_metadatas.append({
                'photo_uuid': photo_uuid,
                'face_index': i,
                'bbox_x': int(face.bbox[0]),
                'bbox_y': int(face.bbox[1]),
                'bbox_w': int(face.bbox[2] - face.bbox[0]),
                'bbox_h': int(face.bbox[3] - face.bbox[1]),
                'confidence': float(face.det_score),
                'age': int(face.age) if hasattr(face, 'age') else None,
                'gender': 'M' if (hasattr(face, 'gender') and face.gender == 1) else 'F',
                'cluster_id': -1,  # Not clustered yet
                'person_name': None,  # User-assigned label
            })

        # Add faces to collection (if any detected)
        if face_ids:
            faces_collection.upsert(
                ids=face_ids,
                embeddings=face_embeddings,
                metadatas=face_metadatas
            )

        return len(faces), time.time() - start_time

    finally:
        # Clean up temp JPEG if needed
        if cleanup_needed:
            try:
                os.remove(photo_path)
                os.rmdir(os.path.dirname(photo_path))
            except:
                pass

def index_faces(limit=None, reindex=False, min_confidence=0.5):
    """
    Main face indexing function

    Args:
        limit: Maximum number of photos to process
        reindex: Reprocess photos that already have face data
        min_confidence: Minimum face detection confidence threshold
    """
    session_start = time.time()

    # Check InsightFace installation
    if not check_insightface():
        sys.exit(1)

    logger.info("📷 Opening ChromaDB...")
    chroma_client = chromadb.PersistentClient(path=DB_PATH)

    # Get photos collection
    try:
        photos_collection = chroma_client.get_collection(name="photos")
    except:
        logger.error("❌ Photos collection not found!")
        logger.error("   Please run index_photos.py first to index your photos.")
        sys.exit(1)

    # Create or get faces collection
    faces_collection = chroma_client.get_or_create_collection(
        name="faces",
        metadata={"description": "Face embeddings from InsightFace"}
    )

    logger.info(f"📊 Photos collection: {photos_collection.count()} photos")
    logger.info(f"📊 Faces collection: {faces_collection.count()} faces")

    # Initialize face detector
    face_app = initialize_face_detector()

    # Get all photos
    all_photos = photos_collection.get(include=['metadatas'])
    photo_metadatas = all_photos['metadatas']
    photo_ids = all_photos['ids']

    logger.info(f"📊 Total photos in database: {len(photo_metadatas)}")

    # Filter photos to process
    photos_to_process = []
    for photo_id, metadata in zip(photo_ids, photo_metadatas):
        if not reindex and metadata.get('has_face_data'):
            continue  # Skip already processed
        photos_to_process.append((photo_id, metadata))

    logger.info(f"📊 Photos to process: {len(photos_to_process)}")

    # Apply limit if specified
    if limit:
        photos_to_process = photos_to_process[:limit]
        logger.info(f"📊 Processing batch of {limit} photos")

    # Process photos
    total_faces = 0
    processed_count = 0

    for i, (photo_id, metadata) in enumerate(photos_to_process, 1):
        logger.info(f"\n{'='*60}")
        logger.info(f"[{i}/{len(photos_to_process)}] Processing: {metadata.get('filename', 'Unknown')}")

        photo_start = time.time()

        # Detect faces
        num_faces, detection_time = process_photo_for_faces(
            metadata, face_app, faces_collection, min_confidence
        )

        # Update photo metadata
        photos_collection.update(
            ids=[photo_id],
            metadatas=[{
                **metadata,
                'num_faces': num_faces,
                'has_face_data': True,
                'face_detection_confidence': min_confidence
            }]
        )

        total_faces += num_faces
        processed_count += 1

        photo_elapsed = time.time() - photo_start
        avg_time = (time.time() - session_start) / i
        estimated_remaining = avg_time * (len(photos_to_process) - i)

        logger.info(f"  └─ Found {num_faces} face(s) in {photo_elapsed:.2f}s")
        logger.info(f"Photo {i} completed in {photo_elapsed:.2f}s")
        logger.info(f"Average time per photo: {avg_time:.2f}s")
        logger.info(f"Estimated time remaining: {estimated_remaining/60:.1f} minutes")

    # Final summary
    session_elapsed = time.time() - session_start
    logger.info(f"\n{'='*60}")
    logger.info(f"✨ Done! Processed {processed_count} photos")
    logger.info(f"📊 Total faces detected: {total_faces}")
    logger.info(f"📊 Average faces per photo: {total_faces/processed_count:.1f}")
    logger.info(f"⏱️  Total time: {session_elapsed/60:.1f} minutes")
    if processed_count > 0:
        logger.info(f"⏱️  Average time per photo: {session_elapsed/processed_count:.2f}s")

    logger.info(f"\n💡 Next steps:")
    logger.info(f"   1. Run clustering: python cluster_faces.py")
    logger.info(f"   2. Review clusters: python browse_faces_web.py")

if __name__ == "__main__":
    # Parse command-line arguments
    limit = None
    reindex = False
    min_confidence = 0.5

    # Show usage if --help
    if '--help' in sys.argv or '-h' in sys.argv:
        print(__doc__)
        sys.exit(0)

    # Parse arguments
    for arg in sys.argv[1:]:
        if arg == '--reindex':
            reindex = True
        elif arg.startswith('--min-confidence'):
            if '=' in arg:
                min_confidence = float(arg.split('=')[1])
            else:
                # Next arg should be the value
                idx = sys.argv.index(arg)
                if idx + 1 < len(sys.argv):
                    min_confidence = float(sys.argv[idx + 1])
        elif arg.isdigit():
            limit = int(arg)

    # Run face indexing
    index_faces(
        limit=limit,
        reindex=reindex,
        min_confidence=min_confidence
    )
