# Face Recognition Quick Start

**Run this AFTER finishing your 21,000 photo indexing with LLaVA.**

## Installation (5 minutes)

```bash
# Activate virtual environment
source venv/bin/activate

# Install InsightFace and dependencies
pip install insightface onnxruntime opencv-python onnxruntime-coreml scikit-learn

# Verify installation
python -c "from insightface.app import FaceAnalysis; print('✅ Ready!')"
```

## Usage (3 steps)

### Step 1: Index Faces (3-6 hours)

```bash
# Process all 21,000 photos
python index_faces.py

# Expected output:
# 📷 Opening ChromaDB...
# 📊 Photos collection: 21000 photos
# 🔍 Processing: IMG_001.jpg
#   └─ Found 2 face(s) in 0.8s
# ...
# ✨ Done! Processed 21000 photos
# 📊 Total faces detected: 42,000
```

### Step 2: Cluster Faces (2-3 minutes)

```bash
# Group similar faces
python cluster_faces.py

# Expected output:
# 🔬 Running DBSCAN clustering...
# 📊 Clustering Results:
#    Unique people found: 127
#    Faces in clusters: 38,500
#    Outliers: 3,500
#    Largest cluster: 387 faces
```

### Step 3: Label Clusters (Interactive)

```bash
# Start web interface
python browse_faces_web.py

# Open browser
open http://localhost:8081
```

Then in the web interface:
1. Click on largest cluster
2. Review sample faces
3. Enter person's name
4. Click "Save Label"
5. Repeat for other clusters

## That's It!

You now have:
- ✅ Face detection on all photos
- ✅ Automatic grouping of same person
- ✅ Ability to label and search by person name

For full documentation, see `FACE_RECOGNITION_GUIDE.md`
