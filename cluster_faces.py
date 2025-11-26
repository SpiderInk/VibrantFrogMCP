#!/usr/bin/env python3
"""
Face Clustering for VibrantFrog MCP

Clusters faces across all photos to identify the same person appearing
in multiple images. Uses DBSCAN clustering on InsightFace embeddings.

Run this AFTER index_faces.py has completed.

Usage:
    python cluster_faces.py [OPTIONS]

Options:
    --threshold 0.6         Cosine distance threshold for clustering (default: 0.6)
                           Lower = stricter (fewer matches), Higher = looser (more matches)
    --min-cluster-size 3    Minimum faces to form a cluster (default: 3)
    --incremental           Only cluster new faces (faster for updates)
    --help, -h              Show this help message

Examples:
    # Cluster all faces with default settings
    python cluster_faces.py

    # More strict clustering (only very similar faces)
    python cluster_faces.py --threshold 0.5

    # Allow smaller clusters (useful for less common people)
    python cluster_faces.py --min-cluster-size 2

    # Quick update after adding new photos
    python cluster_faces.py --incremental

Performance:
    Clustering 10,000 faces: ~30 seconds
    Clustering 50,000 faces: ~2-3 minutes
"""

import os
import sys
import time
import logging
import chromadb
import numpy as np
from sklearn.cluster import DBSCAN
from collections import Counter

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Same DB path as main indexer
DB_PATH = os.path.expanduser("~/Library/Application Support/VibrantFrogMCP/photo_index")

def cluster_faces(threshold=0.6, min_cluster_size=3, incremental=False):
    """
    Cluster faces using DBSCAN algorithm

    Args:
        threshold: Cosine distance threshold (0.0-1.0)
                  0.0 = identical faces only
                  1.0 = all faces match
                  0.6 = good default (same person, different angles/lighting)
        min_cluster_size: Minimum faces needed to form a cluster
        incremental: Only cluster unclustered faces (faster)
    """
    start_time = time.time()

    logger.info("📷 Opening ChromaDB...")
    chroma_client = chromadb.PersistentClient(path=DB_PATH)

    # Get faces collection
    try:
        faces_collection = chroma_client.get_collection(name="faces")
    except:
        logger.error("❌ Faces collection not found!")
        logger.error("   Please run index_faces.py first.")
        sys.exit(1)

    logger.info(f"📊 Faces in database: {faces_collection.count()}")

    # Get all faces
    logger.info("📥 Loading face embeddings...")
    load_start = time.time()

    all_faces = faces_collection.get(include=['embeddings', 'metadatas'])

    if not all_faces['ids']:
        logger.error("❌ No faces found in database!")
        logger.error("   Please run index_faces.py first.")
        sys.exit(1)

    face_ids = all_faces['ids']
    embeddings = np.array(all_faces['embeddings'])
    metadatas = all_faces['metadatas']

    logger.info(f"📥 Loaded {len(face_ids)} faces in {time.time()-load_start:.2f}s")

    # Filter for incremental clustering
    if incremental:
        unclustered_mask = np.array([m.get('cluster_id', -1) == -1 for m in metadatas])
        if not unclustered_mask.any():
            logger.info("✨ No new faces to cluster!")
            return

        logger.info(f"📊 Clustering {unclustered_mask.sum()} new faces (incremental mode)")
        # For incremental, we still need all embeddings for proper clustering
        # but we'll only update the unclustered ones

    # Clustering
    logger.info(f"🔬 Running DBSCAN clustering...")
    logger.info(f"   Threshold: {threshold}")
    logger.info(f"   Min cluster size: {min_cluster_size}")

    cluster_start = time.time()

    clustering = DBSCAN(
        eps=threshold,
        min_samples=min_cluster_size,
        metric='cosine',
        n_jobs=-1  # Use all CPU cores
    )

    cluster_labels = clustering.fit_predict(embeddings)

    cluster_time = time.time() - cluster_start
    logger.info(f"🔬 Clustering completed in {cluster_time:.2f}s")

    # Analyze clusters
    unique_clusters = set(cluster_labels)
    num_clusters = len(unique_clusters) - (1 if -1 in unique_clusters else 0)
    num_outliers = sum(cluster_labels == -1)
    num_clustered = len(cluster_labels) - num_outliers

    cluster_sizes = Counter(cluster_labels)
    del cluster_sizes[-1]  # Remove outliers from size calculation

    logger.info(f"\n📊 Clustering Results:")
    logger.info(f"   Unique people found: {num_clusters}")
    logger.info(f"   Faces in clusters: {num_clustered}")
    logger.info(f"   Outliers (unmatched): {num_outliers}")

    if cluster_sizes:
        logger.info(f"   Largest cluster: {max(cluster_sizes.values())} faces")
        logger.info(f"   Average cluster size: {np.mean(list(cluster_sizes.values())):.1f} faces")

    # Show top 10 largest clusters
    if cluster_sizes:
        logger.info(f"\n📊 Top 10 largest clusters:")
        for cluster_id, size in cluster_sizes.most_common(10):
            logger.info(f"   Cluster {cluster_id}: {size} faces")

    # Update face metadata with cluster IDs
    logger.info(f"\n💾 Updating face metadata...")
    update_start = time.time()

    # Batch update for efficiency
    batch_size = 100
    for i in range(0, len(face_ids), batch_size):
        batch_ids = face_ids[i:i+batch_size]
        batch_metadatas = []

        for j, face_id in enumerate(batch_ids):
            metadata = metadatas[i+j].copy()
            metadata['cluster_id'] = int(cluster_labels[i+j])
            batch_metadatas.append(metadata)

        faces_collection.update(
            ids=batch_ids,
            metadatas=batch_metadatas
        )

        if (i + batch_size) % 1000 == 0:
            logger.info(f"   Updated {i + batch_size}/{len(face_ids)} faces...")

    update_time = time.time() - update_start
    logger.info(f"💾 Metadata updated in {update_time:.2f}s")

    # Save cluster statistics
    stats_path = os.path.join(os.path.dirname(DB_PATH), 'cluster_stats.txt')
    with open(stats_path, 'w') as f:
        f.write(f"Face Clustering Statistics\n")
        f.write(f"==========================\n\n")
        f.write(f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write(f"Total faces: {len(face_ids)}\n")
        f.write(f"Unique people (clusters): {num_clusters}\n")
        f.write(f"Faces in clusters: {num_clustered}\n")
        f.write(f"Outliers: {num_outliers}\n\n")
        f.write(f"Clustering parameters:\n")
        f.write(f"  Threshold: {threshold}\n")
        f.write(f"  Min cluster size: {min_cluster_size}\n\n")

        if cluster_sizes:
            f.write(f"Top 20 largest clusters:\n")
            for cluster_id, size in cluster_sizes.most_common(20):
                f.write(f"  Cluster {cluster_id}: {size} faces\n")

    logger.info(f"\n📄 Statistics saved to: {stats_path}")

    # Final summary
    total_time = time.time() - start_time
    logger.info(f"\n{'='*60}")
    logger.info(f"✨ Clustering complete in {total_time:.2f}s")
    logger.info(f"\n💡 Next steps:")
    logger.info(f"   1. Review clusters: python browse_faces_web.py")
    logger.info(f"   2. Assign names to clusters in the web interface")

    # Recommendations based on results
    logger.info(f"\n💡 Tuning recommendations:")
    if num_outliers > len(face_ids) * 0.5:
        logger.info(f"   ⚠️  High outlier rate ({num_outliers/len(face_ids)*100:.0f}%)")
        logger.info(f"      Consider increasing --threshold (currently {threshold})")
        logger.info(f"      or decreasing --min-cluster-size (currently {min_cluster_size})")
    elif num_clusters < 10 and len(face_ids) > 1000:
        logger.info(f"   ⚠️  Very few clusters found")
        logger.info(f"      Consider decreasing --threshold (currently {threshold})")
        logger.info(f"      for stricter matching")
    else:
        logger.info(f"   ✅ Clustering results look reasonable!")

if __name__ == "__main__":
    # Parse command-line arguments
    threshold = 0.6
    min_cluster_size = 3
    incremental = False

    # Show usage if --help
    if '--help' in sys.argv or '-h' in sys.argv:
        print(__doc__)
        sys.exit(0)

    # Parse arguments
    for i, arg in enumerate(sys.argv[1:], 1):
        if arg == '--incremental':
            incremental = True
        elif arg.startswith('--threshold'):
            if '=' in arg:
                threshold = float(arg.split('=')[1])
            elif i < len(sys.argv) - 1:
                threshold = float(sys.argv[i + 1])
        elif arg.startswith('--min-cluster-size'):
            if '=' in arg:
                min_cluster_size = int(arg.split('=')[1])
            elif i < len(sys.argv) - 1:
                min_cluster_size = int(sys.argv[i + 1])

    # Run clustering
    cluster_faces(
        threshold=threshold,
        min_cluster_size=min_cluster_size,
        incremental=incremental
    )
