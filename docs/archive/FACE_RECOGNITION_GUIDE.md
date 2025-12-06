# Face Recognition Guide

## Overview

The VibrantFrog MCP face recognition system allows you to:
- **Detect faces** in all your photos
- **Extract face embeddings** using state-of-the-art InsightFace model
- **Cluster faces** to group the same person across different photos
- **Label clusters** with people's names
- **Search photos** by person name

This is a **two-phase approach**:
1. **Phase 1**: Index photo descriptions with LLaVA (what you're doing now)
2. **Phase 2**: Add face recognition data to existing photos (run later)

---

## Architecture

### Database Collections

**Collection 1: `photos`** (existing)
- LLaVA text descriptions
- Photo metadata (date, location, keywords, etc.)
- Face count (added by face indexer)

**Collection 2: `faces`** (new)
- Face embeddings (512-dimensional vectors from InsightFace)
- Bounding boxes (where faces are in photos)
- Cluster IDs (which person)
- Person names (user-assigned labels)

### Why Separate Collections?

- **Performance**: Face embeddings are large (2KB each); separating them keeps photo searches fast
- **Flexibility**: Can re-cluster faces without touching photo data
- **Scalability**: Can have multiple faces per photo without bloating photo metadata

---

## Installation

### When You're Ready (After 21K Photos Indexed)

```bash
# Activate your virtual environment
source venv/bin/activate

# Install InsightFace and dependencies
pip install insightface onnxruntime opencv-python scikit-learn

# For M2 Pro optimization (recommended - uses Neural Engine)
pip install onnxruntime-coreml
```

### Verify Installation

```bash
python -c "from insightface.app import FaceAnalysis; print('✅ InsightFace installed')"
```

---

## Workflow

### Step 1: Index Faces

Process all 21,000 photos to detect and extract face embeddings.

```bash
# Process all photos
python index_faces.py

# Or process in batches of 1000
python index_faces.py 1000
python index_faces.py 1000  # Continues where it left off
# ... repeat until done
```

**Expected Time**: 3-6 hours for 21,000 photos on M2 Pro

**What It Does**:
- Reads existing photos from ChromaDB
- Loads each photo from disk
- Converts HEIC to JPEG if needed
- Detects faces using InsightFace
- Extracts 512-dimensional embedding for each face
- Stores face data in separate `faces` collection
- Updates photo record with `num_faces` count

### Step 2: Cluster Faces

Group similar faces across all photos to identify the same person.

```bash
# Run clustering with default settings
python cluster_faces.py

# More strict clustering (only very similar faces)
python cluster_faces.py --threshold 0.5

# Allow smaller clusters (2+ faces instead of 3+)
python cluster_faces.py --min-cluster-size 2
```

**Expected Time**: 2-3 minutes for 50,000 faces

**What It Does**:
- Loads all face embeddings from ChromaDB
- Runs DBSCAN clustering algorithm
- Groups faces with cosine similarity > threshold
- Assigns cluster ID to each face
- Generates statistics report

**Output Example**:
```
📊 Clustering Results:
   Unique people found: 127
   Faces in clusters: 8,542
   Outliers (unmatched): 1,203
   Largest cluster: 387 faces
   Average cluster size: 67.2 faces

📊 Top 10 largest clusters:
   Cluster 0: 387 faces  ← Probably you!
   Cluster 1: 245 faces  ← Spouse/partner?
   Cluster 2: 189 faces
   ...
```

### Step 3: Review and Label Clusters

Use the web interface to review face clusters and assign names.

```bash
# Start web interface
python browse_faces_web.py

# Open in browser
open http://localhost:8081
```

**Web Interface Features**:
- View all face clusters sorted by size
- See sample faces from each cluster (max 20)
- Filter by cluster size, labeled/unlabeled, hide outliers
- Assign person names to clusters
- Updates all faces in cluster with one click

**Workflow**:
1. Start with largest clusters (likely most important people)
2. Review sample faces to confirm they're the same person
3. Enter person's name and click "Save Label"
4. Move to next cluster

---

## Advanced Usage

### Tuning Clustering Parameters

**Threshold** (`--threshold`)
- **What it is**: Maximum cosine distance for two faces to be considered the same person
- **Range**: 0.0 to 1.0
- **Default**: 0.6
- **Lower** (e.g., 0.4-0.5): Stricter matching, fewer false positives, more outliers
- **Higher** (e.g., 0.7-0.8): Looser matching, more false positives, fewer outliers

**Min Cluster Size** (`--min-cluster-size`)
- **What it is**: Minimum faces needed to form a cluster
- **Default**: 3
- **Lower** (e.g., 2): Find people who appear in fewer photos
- **Higher** (e.g., 5-10): Focus on frequently appearing people only

**When to Adjust**:

```bash
# Too many outliers (>50%)?
# → Increase threshold or decrease min-cluster-size
python cluster_faces.py --threshold 0.7 --min-cluster-size 2

# Clusters mixing different people?
# → Decrease threshold
python cluster_faces.py --threshold 0.5

# Want to find everyone, even if they appear only twice?
# → Lower min-cluster-size
python cluster_faces.py --min-cluster-size 2
```

### Incremental Updates

When you add new photos:

```bash
# 1. Index new photos (descriptions)
python index_photos.py 50

# 2. Index faces for those photos
python index_faces.py 50

# 3. Re-cluster (fast, only clusters new faces)
python cluster_faces.py --incremental
```

### Reindexing Faces

If you want to use a different face detection model or settings:

```bash
# Reprocess all photos with new settings
python index_faces.py --reindex --min-confidence 0.8
```

---

## Performance

### Face Detection Speed (M2 Pro)

| Component | Time | Notes |
|-----------|------|-------|
| Face detection | 100-300ms | Per image |
| Face embedding | 50-100ms | Per face |
| HEIC conversion | 500ms-1s | If needed |
| **Total per photo** | **0.5-1.5s** | Assuming 1-3 faces |

### Clustering Speed

| Faces | Time | Notes |
|-------|------|-------|
| 10,000 | ~30s | DBSCAN on CPU |
| 50,000 | ~2-3 min | Uses all CPU cores |
| 100,000 | ~5-8 min | Still very fast |

### Storage

| Data | Size per Face | Total (21K photos) |
|------|--------------|-------------------|
| Face embedding | 2KB | ~84MB (2 faces/photo) |
| Metadata | ~200 bytes | ~8MB |
| **Total** | ~2.2KB | **~92MB** |

Very manageable!

---

## Troubleshooting

### Problem: "InsightFace not installed"

```bash
# Solution
pip install insightface onnxruntime opencv-python
```

### Problem: "Faces collection not found"

```bash
# You need to run index_faces.py first
python index_faces.py
```

### Problem: Face detection is slow

```bash
# Check if using Neural Engine
python index_faces.py 10  # Process 10 photos

# Look for this in output:
# "Using CoreML (Neural Engine) for face detection" ✅ Good
# "Using CPU for face detection (slower)" ⚠️ Slower

# If using CPU, install CoreML support:
pip install onnxruntime-coreml
```

### Problem: Too many clusters (faces not grouping)

```bash
# Increase threshold for looser matching
python cluster_faces.py --threshold 0.7
```

### Problem: Clusters mixing different people

```bash
# Decrease threshold for stricter matching
python cluster_faces.py --threshold 0.5
```

### Problem: HEIC conversion errors

The script automatically converts HEIC to JPEG using macOS `sips` tool.
If conversion fails, the photo is skipped. Check the logs for details.

---

## Data Schema

### Faces Collection

```python
{
    'id': 'ABC123_face_0',  # {photo_uuid}_face_{index}
    'embedding': [0.123, -0.456, ...],  # 512 floats
    'metadata': {
        'photo_uuid': 'ABC123',  # Link to photo
        'face_index': 0,  # Which face in photo (0, 1, 2...)
        'bbox_x': 100,  # Bounding box top-left X
        'bbox_y': 150,  # Bounding box top-left Y
        'bbox_w': 200,  # Bounding box width
        'bbox_h': 250,  # Bounding box height
        'confidence': 0.987,  # Detection confidence (0-1)
        'age': 25,  # Estimated age (from InsightFace)
        'gender': 'M',  # M or F (from InsightFace)
        'cluster_id': 5,  # Which cluster (-1 = outlier)
        'person_name': 'John Smith'  # User-assigned label
    }
}
```

### Photos Collection (Updated Fields)

```python
{
    'id': 'ABC123',
    'metadata': {
        # ... existing fields (description, date, location, etc.)
        'num_faces': 2,  # Count of faces detected
        'has_face_data': True,  # Face processing completed
        'face_detection_confidence': 0.5  # Min confidence used
    }
}
```

---

## Searching by Person

### Option 1: Via Web Interface

```bash
python browse_faces_web.py
# Navigate to http://localhost:8081
# Filter to show only labeled clusters
```

### Option 2: Via MCP (Future Enhancement)

```python
# We can add an MCP tool for this:

# Find all photos containing "John Smith"
photos_with_john = search_photos_by_person("John Smith")

# Returns list of photo UUIDs and face locations
```

### Option 3: Direct ChromaDB Query

```python
# Get all faces labeled as "John Smith"
faces = faces_collection.get(
    where={"person_name": "John Smith"},
    include=['metadatas']
)

# Get unique photo UUIDs
photo_uuids = set(f['photo_uuid'] for f in faces['metadatas'])

# Retrieve those photos
photos = photos_collection.get(
    ids=list(photo_uuids),
    include=['metadatas', 'documents']
)
```

---

## Tips & Best Practices

### 1. Start with Largest Clusters
The largest clusters are likely the most important people (you, family members).
Label these first to get immediate value.

### 2. Review Sample Faces Carefully
Before labeling, check multiple sample faces to ensure they're all the same person.
Occasional mismatches are normal; you can fine-tune clustering later.

### 3. Use Descriptive Names
Instead of just "John", use "John Smith" to avoid confusion.
You can also use relationships like "Dad", "Mom", "Brother Tom", etc.

### 4. Ignore Small Clusters Initially
Clusters with <5 faces might be:
- Group photos where face detection was partial
- Photos at distance where face quality is low
- People who appear rarely in your library

Focus on large clusters first (>20 faces).

### 5. Iterate on Clustering
After labeling major clusters, you might want to re-cluster with different settings
to catch more matches or separate incorrectly grouped faces.

### 6. Backup Your Database
Before major operations (re-clustering, reindexing), backup your database:

```bash
# Backup
cp -r ~/Library/Application\ Support/VibrantFrogMCP ~/Desktop/VibrantFrogMCP_backup

# Restore if needed
rm -rf ~/Library/Application\ Support/VibrantFrogMCP
cp -r ~/Desktop/VibrantFrogMCP_backup ~/Library/Application\ Support/VibrantFrogMCP
```

---

## Future Enhancements

### Planned Features

1. **MCP Tool Integration**
   - `search_photos_by_person(name)` tool
   - Returns photos containing specified person
   - Can be used in Claude Desktop queries

2. **Smart Merging**
   - Merge two clusters if they're the same person
   - Split cluster if it contains multiple people

3. **Face Verification**
   - Upload a photo of someone
   - Find all photos containing that person

4. **Quality Filtering**
   - Filter out low-quality faces (blurry, partial, occluded)
   - Focus on clear, frontal faces for better clustering

5. **Temporal Clustering**
   - Use photo dates to help clustering
   - E.g., faces in photos from same event are likely same people

6. **Export Functionality**
   - Export all photos of a person
   - Create photo albums by person

---

## Command Reference

### index_faces.py

```bash
# Process all unprocessed photos
python index_faces.py

# Process 100 photos
python index_faces.py 100

# Reprocess all photos (overwrite existing face data)
python index_faces.py --reindex

# Only detect high-confidence faces (>80%)
python index_faces.py --min-confidence 0.8

# Show help
python index_faces.py --help
```

### cluster_faces.py

```bash
# Cluster with default settings (threshold=0.6, min_size=3)
python cluster_faces.py

# Stricter clustering (only very similar faces)
python cluster_faces.py --threshold 0.5

# Looser clustering (more matches)
python cluster_faces.py --threshold 0.7

# Allow smaller clusters (2+ faces instead of 3+)
python cluster_faces.py --min-cluster-size 2

# Quick incremental update (only cluster new faces)
python cluster_faces.py --incremental

# Show help
python cluster_faces.py --help
```

### browse_faces_web.py

```bash
# Start web interface on port 8081
python browse_faces_web.py

# Then open browser to:
http://localhost:8081
```

---

## FAQ

**Q: Do I need to reindex photos with LLaVA?**
A: No! Face indexing is completely independent. It reads photo paths from existing ChromaDB records.

**Q: Can I run this on photos not in Apple Photos?**
A: The current face indexer works with any photos that have been indexed by `index_photos.py`.
Since that script uses osxphotos, it only works with Apple Photos Library.
However, you could adapt `index_faces.py` to work with any photo directory.

**Q: How accurate is face recognition?**
A: InsightFace is state-of-the-art (>99% accuracy on standard benchmarks).
However, accuracy depends on photo quality, lighting, angles, age differences, etc.
Expect occasional mismatches, especially for:
- Profile shots (side view)
- Poor lighting
- Sunglasses/masks
- Significant age differences (baby vs adult)

**Q: Can it recognize faces in group photos?**
A: Yes! It detects multiple faces per photo and creates embeddings for each.

**Q: What about privacy?**
A: All face data is stored locally on your machine in ChromaDB.
Nothing is sent to external servers. InsightFace runs entirely locally.

**Q: Can I delete face data later?**
A: Yes! Simply delete the `faces` collection:
```python
chroma_client.delete_collection("faces")
```
Your photo descriptions and metadata remain untouched.

**Q: Why use DBSCAN instead of other clustering algorithms?**
A: DBSCAN has several advantages:
- Doesn't require specifying number of clusters (you don't know how many people are in your photos)
- Handles outliers well (single-appearance faces)
- Works well with cosine similarity for face embeddings
- Fast enough for large datasets

---

## Getting Help

If you encounter issues:

1. Check the logs (console output shows detailed progress)
2. Review this guide's Troubleshooting section
3. Verify installations: `pip list | grep -E 'insightface|onnxruntime|opencv'`
4. Check ChromaDB collections: They should exist and contain data

---

## Summary Workflow

```bash
# AFTER 21K photos are indexed with LLaVA...

# 1. Install dependencies
pip install insightface onnxruntime opencv-python onnxruntime-coreml scikit-learn

# 2. Index faces (one-time, 3-6 hours)
python index_faces.py

# 3. Cluster faces (one-time, 2-3 minutes)
python cluster_faces.py

# 4. Label clusters (interactive)
python browse_faces_web.py
# Open http://localhost:8081 and assign names

# 5. Done! Now you can search by person name
```

Enjoy your AI-powered photo organization! 📷✨
