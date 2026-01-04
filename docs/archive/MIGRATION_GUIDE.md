# VibrantFrogMCP Migration Guide

## Understanding the Two Conversions

### Conversion 1: AI Model (One-Time Setup)

**Script:** `convert_to_coreml.py`

**What it converts:** The all-MiniLM-L6-v2 embedding model itself

**Purpose:** Allows VibrantFrog Collab to generate embeddings on iOS/Mac

**Input:** Downloads model from HuggingFace (sentence-transformers)

**Output:** `SentenceEmbedding.mlpackage` (~90 MB)

**When to run:** Once, before integrating into Xcode

**Command:**
```bash
cd /Users/tpiazza/git/VibrantFrogMCP
pip install coremltools sentence-transformers torch
python convert_to_coreml.py
```

**Result:** Creates CoreML model that you add to Xcode project

---

### Conversion 2: Your Photo Data (Migrate Existing Index)

**Script:** `migrate_to_icloud.py`

**What it converts:** Your actual indexed photos (ChromaDB → SQLite)

**Purpose:** Makes your existing photo index accessible to VibrantFrog Collab

**Input:** Your ChromaDB at `~/Library/Application Support/VibrantFrogMCP/photo_index/`

**Output:** SQLite database in iCloud Drive

**When to run:** Once to migrate existing data, then incremental updates

**Command:**
```bash
cd /Users/tpiazza/git/VibrantFrogMCP
python migrate_to_icloud.py
```

**Result:**
```
Before:
~/Library/Application Support/VibrantFrogMCP/
└── photo_index/
    ├── chroma.sqlite3 (428 MB)  ← Your ChromaDB
    └── indexed_photos.json

After (ALSO creates):
~/Library/Mobile Documents/iCloud~com~vibrantfrog~AuthorAICollab/PhotoSearch/
├── photo_index.db (10 MB)       ← New SQLite in iCloud
└── indexed_photos.json
```

**Important:** Your original ChromaDB is NOT deleted (kept as backup)

---

## Complete Setup Flow

### Step 1: Convert AI Model (One-Time)
```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# Install dependencies
pip install coremltools sentence-transformers torch

# Convert model
python convert_to_coreml.py

# Result: SentenceEmbedding.mlpackage created
```

**Action:** Copy `SentenceEmbedding.mlpackage` to your Xcode project

---

### Step 2: Migrate Your Existing Photo Index
```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# Migrate ChromaDB → iCloud SQLite
python migrate_to_icloud.py

# Output:
# ✅ Found 5,432 indexed photos
# ✅ Migrated 5,432 photos to iCloud
# 📊 Database size: 10.2 MB
```

**Action:** Wait ~30 seconds for iCloud to sync

---

### Step 3: Update VibrantFrogMCP for Future Indexing

After migration, future photos should be indexed directly to iCloud.

Update your indexing workflow:

```python
# In index_photos.py, add option to use shared iCloud database
from shared_index import SharedPhotoIndex

# Old way (ChromaDB):
# collection.upsert(...)

# New way (iCloud SQLite):
shared_index = SharedPhotoIndex()
shared_index.index_photo(photo, description, embedding)
```

Or run the migration script in "incremental" mode:
```bash
# Index new photos directly to iCloud
python index_photos.py --icloud
```

---

### Step 4: Open VibrantFrog Collab

1. Launch app on iOS or Mac
2. Go to Settings → Photo Search
3. App detects iCloud database automatically
4. Shows: "✅ 5,432 photos indexed"
5. Start searching!

---

## Comparison Table

| Aspect | Model Conversion | Data Migration |
|--------|-----------------|----------------|
| **What** | AI model | Your photo index |
| **From** | HuggingFace | ChromaDB |
| **To** | CoreML | SQLite in iCloud |
| **Size** | ~90 MB | ~10 MB |
| **When** | Once | Once + incremental |
| **Where** | Xcode bundle | iCloud Drive |
| **Purpose** | Generate embeddings | Search photos |

---

## After Migration: Two Workflows

### Workflow A: Continue Using VibrantFrogMCP (Recommended)

Index new photos directly to iCloud:

```bash
# Index new photos
cd /Users/tpiazza/git/VibrantFrogMCP
python index_photos.py --icloud 100

# Result: New photos appear in VibrantFrog Collab automatically
```

**How it works:**
1. VibrantFrogMCP detects photos not in iCloud index
2. Generates descriptions with LLaVA
3. Stores directly in `iCloud~/PhotoSearch/photo_index.db`
4. VibrantFrog Collab sees new photos within ~30 seconds

---

### Workflow B: Index Within VibrantFrog Collab (Future Feature)

You could also add indexing capability to the iOS/Mac app:

```swift
// In VibrantFrog Collab
let indexer = PhotoIndexer(mode: .visionFramework)  // or .aiPowered
await indexer.indexNewPhotos()

// Writes to same iCloud database
// No need to use VibrantFrogMCP at all
```

This requires implementing the Swift version of indexing (future work).

---

## File Structure After Setup

```
VibrantFrogMCP/
├── convert_to_coreml.py         ← Converts AI model
├── migrate_to_icloud.py         ← Migrates your data
├── shared_index.py              ← Future indexing to iCloud
├── SentenceEmbedding.mlpackage  ← Generated CoreML model
└── photo_index/ (old)           ← Original ChromaDB (backup)

iCloud Drive/
└── iCloud~com~vibrantfrog~AuthorAICollab/
    └── PhotoSearch/
        ├── photo_index.db       ← Migrated SQLite (10 MB)
        └── indexed_photos.json  ← Cache

VibrantFrog Collab (Xcode)/
└── SentenceEmbedding.mlpackage  ← Copied from VibrantFrogMCP
```

---

## FAQ

### Q: Will migration delete my ChromaDB?
**A:** No, your original ChromaDB stays intact as a backup.

### Q: What if I index more photos after migration?
**A:** Use `python index_photos.py --icloud` to add them directly to iCloud.

### Q: Can I re-run the migration?
**A:** Yes, it will update existing records and add new ones.

### Q: What if iCloud is full?
**A:** The database is only ~10 MB for 5,000 photos, very small.

### Q: Do I need to convert the model every time?
**A:** No, convert once. The CoreML model is reusable forever.

### Q: Can I delete ChromaDB after migration?
**A:** Yes, but keep it as backup until you verify iCloud sync works.

---

## Troubleshooting

### iCloud Drive Not Found
```bash
# Check if iCloud Drive is enabled
ls ~/Library/Mobile\ Documents/

# Should show folders, including iCloud~com~vibrantfrog~AuthorAICollab
```

**Fix:** Enable iCloud Drive in System Settings → Apple ID → iCloud

### Migration Shows 0 Photos
```bash
# Check if you have indexed photos
ls -lh ~/Library/Application\ Support/VibrantFrogMCP/

# Should show photo_index/ directory and indexed_photos.json
```

**Fix:** Index some photos first with `python index_photos.py`

### CoreML Conversion Fails
```bash
# Check dependencies
pip list | grep -E "coremltools|sentence-transformers|torch"
```

**Fix:**
```bash
pip install --upgrade coremltools sentence-transformers torch
```

---

## Summary

**Two different conversions, both needed:**

1. **Model Conversion** (`convert_to_coreml.py`)
   - Converts AI model for iOS use
   - Run once
   - Output: `SentenceEmbedding.mlpackage` → Add to Xcode

2. **Data Migration** (`migrate_to_icloud.py`)
   - Migrates your existing photo index
   - Run once, then incremental updates
   - Output: SQLite in iCloud Drive → VibrantFrog Collab reads automatically

**After both conversions:**
- VibrantFrog Collab can search your photos
- New photos can be indexed directly to iCloud
- Everything syncs automatically across devices
- No more export/import hassle!
