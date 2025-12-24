# VibrantFrogMCP iCloud Integration Testing Guide

## Overview

This guide walks you through testing the new iCloud-based photo indexing that will be shared between:
- **VibrantFrogMCP** (Python MCP server + Mac app)
- **VibrantFrog Collab** (iOS/Mac app - to be implemented)

## Current State

### What You Have Now
```
~/Library/Application Support/VibrantFrogMCP/
├── photo_index/
│   ├── chroma.sqlite3        ← Your existing ChromaDB (428 MB)
│   └── 9b07978e-.../         ← HNSW index
└── indexed_photos.json       ← Cache (862 KB)
```

### What Will Happen After Migration
```
# OLD location (still kept as backup):
~/Library/Application Support/VibrantFrogMCP/
└── photo_index/              ← Still exists, not deleted

# NEW location (shared via iCloud):
~/Library/Mobile Documents/iCloud~com~vibrantfrog~AuthorAICollab/PhotoSearch/
├── photo_index.db            ← New SQLite database (~10 MB)
└── indexed_photos.json       ← Copy of cache
```

**Important:** Your old ChromaDB is **NOT deleted**. It stays as a backup. Both will coexist.

---

## Question 1: What Will No Longer Use ChromaDB?

### Short Answer
**Future indexing** will use the new iCloud SQLite database instead of ChromaDB.

### Detailed Explanation

**What Changes:**
- `index_photos.py` (old script) → Uses ChromaDB
- `index_photos_icloud.py` (new script) → Uses iCloud SQLite ✅

**Your Existing ChromaDB:**
- Will be **migrated** (copied) to iCloud SQLite
- Will **remain on disk** as backup
- Can still be used if needed (backward compatible)

**VibrantFrogApp (Mac app):**
- Currently uses MCP server which reads ChromaDB
- After migration, can read from **either**:
  - HTTP MCP server (still uses old ChromaDB)
  - OR iCloud SQLite database (new shared format)

**Recommendation:** Keep using VibrantFrogApp with the MCP server as-is during testing. The iCloud database is for VibrantFrog Collab (iOS).

---

## Question 2: Can I Run VibrantFrogMCP on the Mac?

### Yes! You Have Two Components:

### 1. **VibrantFrog Mac App** (`/Users/tpiazza/git/VibrantFrogMCP/VibrantFrogApp/`)
- Native macOS SwiftUI application
- Connects to MCP server via HTTP
- Uses Ollama for AI chat
- Has UI for photo search, MCP tools, etc.

**How it works now:**
```
VibrantFrog.app (Mac)
   ↓ HTTP
Python MCP Server (vibrant_frog_mcp.py)
   ↓
ChromaDB (local)
   ↓
Apple Photos Library
```

**This still works!** No changes needed for VibrantFrog.app.

### 2. **Python MCP Server** (`vibrant_frog_mcp.py`)
- Runs in terminal
- Provides MCP tools (search_photos, create_album, etc.)
- Can run in HTTP mode or stdio mode

**Start the server:**
```bash
cd /Users/tpiazza/git/VibrantFrogMCP
python vibrant_frog_mcp.py --transport http
# Runs on http://127.0.0.1:5050/mcp
```

**Then open VibrantFrog.app** and connect to the server.

---

## Complete Testing Outline

### Phase 1: Verify Current Setup (5 minutes)

#### Step 1.1: Check Your Existing ChromaDB
```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# Show current stats
python -c "
import chromadb
client = chromadb.PersistentClient(path='${HOME}/Library/Application Support/VibrantFrogMCP/photo_index')
collection = client.get_collection('photos')
print(f'Total photos indexed: {collection.count()}')
"
```

**Expected Output:**
```
Total photos indexed: 5432
```

#### Step 1.2: Check iCloud Drive Is Enabled
```bash
# Check if iCloud Drive folder exists
ls -la ~/Library/Mobile\ Documents/ | grep -i vibrantfrog

# If empty, iCloud Drive is not enabled or container doesn't exist yet
```

**If iCloud container doesn't exist yet:**
- Open VibrantFrog Collab on Mac or iOS once
- This creates the iCloud container
- OR manually enable iCloud Drive in System Settings

---

### Phase 2: Migrate Existing ChromaDB to iCloud (10 minutes)

#### Step 2.1: Run Migration Script
```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# Make sure you're on the feature branch
git branch
# Should show: * feature/icloud-shared-index

# Run migration
python migrate_to_icloud.py
```

**Expected Output:**
```
============================================================
VibrantFrogMCP → iCloud Migration
============================================================

✅ iCloud Drive found at: ~/Library/Mobile Documents
✅ Created iCloud directory: ...PhotoSearch
📂 Loading existing ChromaDB from: ...
✅ Loaded ChromaDB collection: 'photos'

📊 Fetching all indexed photos from ChromaDB...
✅ Found 5432 indexed photos

📝 Creating SQLite database at: .../photo_index.db
✅ Created SQLite schema

🔄 Migrating 5432 photos to SQLite...
  Progress: 100/5432 (1.8%)
  Progress: 200/5432 (3.7%)
  ...
  Progress: 5432/5432 (100.0%)

✅ Migration complete!
   Migrated: 5432 photos

📊 Database Statistics:
   Location: .../PhotoSearch/photo_index.db
   Size: 10.2 MB
   Photos: 5432
   Format: SQLite with JSON embeddings

✅ Verification passed: 5432 photos in database

============================================================
Migration Complete! 🎉
============================================================

📱 Next Steps:
1. Wait ~30 seconds for iCloud to sync the database
2. Open VibrantFrog Collab on iOS/Mac
3. Go to Settings → Photo Search
4. The app should detect your 5432 indexed photos
5. Start searching!

💡 Future Indexing:
   From now on, new photos will be indexed directly to iCloud
   Run: python index_photos_icloud.py
```

#### Step 2.2: Verify Migration
```bash
# Check iCloud database was created
ls -lh ~/Library/Mobile\ Documents/iCloud~com~vibrantfrog~AuthorAICollab/PhotoSearch/

# Should show:
# photo_index.db      (~10 MB)
# indexed_photos.json (~1 MB)

# Check database contents
python shared_index.py --stats
```

**Expected Output:**
```
============================================================
📊 Shared Photo Index Statistics
============================================================
Total Photos:     5432
Favorites:        234
iCloud Photos:    1203
Last Updated:     2024-12-24T15:30:00
Embedding Model:  all-MiniLM-L6-v2
Database Size:    10.2 MB
Database Path:    .../PhotoSearch/photo_index.db
iCloud Synced:    ✅
============================================================

📱 Open VibrantFrog Collab to search photos
```

#### Step 2.3: Verify Old ChromaDB Still Exists (Backup)
```bash
# Confirm original is still there
ls -lh ~/Library/Application\ Support/VibrantFrogMCP/photo_index/

# Should still show:
# chroma.sqlite3  (428 MB)  ← Original still exists!
```

---

### Phase 3: Test Indexing New Photos to iCloud (15 minutes)

Now test indexing **new** photos directly to the iCloud database.

#### Step 3.1: Check for New Photos
```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# See how many photos would be indexed
python index_photos_icloud.py --stats
```

**Output shows:**
```
Total Photos:     5432
Last Updated:     2024-12-24T15:30:00
```

#### Step 3.2: Take a Test Photo (Optional)
- Open Photos app
- Take a screenshot or import a new photo
- Wait a moment for it to appear in library

#### Step 3.3: Index New Photos
```bash
# Index up to 10 new photos to test
python index_photos_icloud.py 10
```

**Expected Output:**
```
============================================================
VibrantFrogMCP → iCloud Photo Indexing
============================================================

☁️  Connecting to iCloud Drive...
✅ Connected to shared index
   Current photos: 5432
   Database size: 10.2 MB
   Last updated: 2024-12-24T15:30:00

📷 Opening Apple Photos Library...
📊 Found 5432 already indexed photos
📊 Total photos in library: 5450
📊 Sorted by date (newest first)
📊 New photos to index: 18

[1/10] Starting photo processing
🔍 Processing: IMG_1234.jpg
  ├─ Photo path resolution: 0.12s
  ├─ Description generation: 125.34s  ← LLaVA is slow
  ├─ Embedding generation: 2.45s
  ├─ iCloud database write: 0.08s
  └─ Total time: 127.99s
✅ Indexed to iCloud: IMG_1234.jpg

...

✨ Done! Indexed 10 new photos
📊 Total indexed: 5442
⏱️  Total session time: 21.3 minutes
⏱️  Average time per photo: 128.1s

☁️  iCloud Database:
   Total photos: 5442
   Database size: 10.4 MB
   Path: .../PhotoSearch/photo_index.db

📱 Photos will sync to VibrantFrog Collab automatically
   Open the app to search!
============================================================
```

#### Step 3.4: Verify New Photos in Database
```bash
python shared_index.py --stats

# Should show increased count:
# Total Photos:     5442  ← Increased from 5432
```

---

### Phase 4: Test VibrantFrog Mac App (Still Works) (5 minutes)

Your existing Mac app should still work with the old MCP server.

#### Step 4.1: Start MCP Server
```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# Start server in HTTP mode
python vibrant_frog_mcp.py --transport http
```

**Expected Output:**
```
INFO - Initializing ChromaDB...
INFO - Loading embedding function...
✅ ChromaDB collection loaded: 5432 photos
INFO - Starting HTTP server on 127.0.0.1:5050
```

#### Step 4.2: Open VibrantFrog.app
- Open `VibrantFrogApp/VibrantFrog.xcodeproj` in Xcode
- Run the app
- OR if you have a built version, open it

#### Step 4.3: Test Photo Search
- In VibrantFrog app, go to MCP Servers tab
- Make sure connected to localhost:5050
- Try searching: "sunset", "dog", etc.
- Photos should appear as before

**This proves the old system still works in parallel!**

---

### Phase 5: Monitor iCloud Sync (2 minutes)

The iCloud database should sync to other devices.

#### Step 5.1: Check Sync Status
```bash
# On Mac, check file metadata
ls -l@ ~/Library/Mobile\ Documents/iCloud~com~vibrantfrog~AuthorAICollab/PhotoSearch/photo_index.db

# Look for extended attributes indicating iCloud status
# com.apple.LaunchServices.OpenWith
# com.apple.metadata:kMDItemWhereFroms
```

#### Step 5.2: Force Sync (if needed)
```bash
# Trigger iCloud sync
brctl log --wait --shorten
```

#### Step 5.3: Wait
- iCloud sync typically takes 10-60 seconds for small files
- 10 MB database should sync quickly

---

## Troubleshooting

### Migration Fails: "iCloud Drive not available"

**Solution:**
```bash
# Check if iCloud is enabled
defaults read ~/Library/Preferences/MobileMeAccounts.plist

# Enable iCloud Drive in System Settings:
# System Settings → Apple ID → iCloud → iCloud Drive → ON
```

### Migration Shows "0 photos"

**Problem:** ChromaDB is empty or not found

**Solution:**
```bash
# Verify ChromaDB exists
ls -lh ~/Library/Application\ Support/VibrantFrogMCP/photo_index/

# If empty, index some photos first:
cd /Users/tpiazza/git/VibrantFrogMCP
git checkout main  # Go back to main branch
python index_photos.py 10  # Index 10 photos to ChromaDB
git checkout feature/icloud-shared-index  # Return to feature branch
python migrate_to_icloud.py  # Try migration again
```

### "PRAGMA journal_mode=WAL" Error

**Problem:** Database locked or permissions issue

**Solution:**
```bash
# Close all apps using the database
# Delete and recreate
rm -rf ~/Library/Mobile\ Documents/iCloud~com~vibrantfrog~AuthorAICollab/PhotoSearch/
python migrate_to_icloud.py
```

### New Photos Not Indexing

**Problem:** Ollama not running

**Solution:**
```bash
# Check Ollama
ollama list

# Start Ollama if needed
ollama serve

# Pull required model
ollama pull llava:7b
```

---

## Summary

### What You're Testing

1. ✅ **Migration:** ChromaDB → iCloud SQLite (one-time)
2. ✅ **New Indexing:** Add photos directly to iCloud
3. ✅ **Backward Compat:** Old VibrantFrog app still works
4. ✅ **iCloud Sync:** Database syncs across devices

### What's NOT Tested Yet

- ❌ VibrantFrog Collab reading the database (iOS implementation pending)
- ❌ CoreML embeddings (optional enhancement)
- ❌ Semantic search (currently simple keyword matching)

### Key Success Criteria

- [ ] Migration completes successfully
- [ ] iCloud database created (~10 MB)
- [ ] Old ChromaDB still exists (backup)
- [ ] Can index new photos to iCloud
- [ ] Photo count increases correctly
- [ ] VibrantFrog Mac app still works
- [ ] Database file syncs to iCloud

---

## Next Steps After Testing

Once you confirm everything works:

1. **Report Results:**
   - How many photos migrated?
   - Any errors?
   - iCloud sync working?

2. **Ready for iOS Implementation:**
   - I'll implement PhotoSearchService in VibrantFrog Collab
   - It will read from the same iCloud database
   - Search will work immediately on iOS/Mac

3. **Future Enhancements:**
   - Convert model to CoreML (optional)
   - Semantic search with embeddings
   - Advanced filtering

---

## Quick Reference Commands

```bash
# Show stats
python shared_index.py --stats

# Migrate ChromaDB
python migrate_to_icloud.py

# Index new photos
python index_photos_icloud.py 10

# Index all new photos
python index_photos_icloud.py

# Check iCloud folder
ls -lh ~/Library/Mobile\ Documents/iCloud~com~vibrantfrog~AuthorAICollab/PhotoSearch/

# Start MCP server
python vibrant_frog_mcp.py --transport http
```

Good luck testing! Let me know what happens! 🚀
