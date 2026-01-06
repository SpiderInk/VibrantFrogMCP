# CloudKit Photo Index Sync & Cross-Device Photo Search

## Overview

This PR adds **CloudKit-based photo index synchronization** to enable cross-device photo search between Mac (VibrantFrogMCP) and iOS/iPad (VibrantFrog Collab app). Users can now index their photos once on their Mac and seamlessly search them on all their Apple devices via iCloud.

## What's New

### 🔄 CloudKit Synchronization System

- **Automatic Sync**: Photo index automatically uploads to CloudKit when indexing completes on Mac
- **Cross-Device Access**: iOS/iPad devices download and search the shared photo index
- **Incremental Updates**: Only new/changed photos are synced, not the entire database
- **Background Uploads**: Large photo index files split into 10MB chunks for reliable CloudKit uploads

### 📱 iOS/iPad Photo Search (VibrantFrog Collab)

- Search your entire photo library using natural language from iPhone/iPad
- Uses CloudKit records for photo metadata and AI descriptions
- Converts cloud identifiers to local PHAssets for seamless photo access
- Fallback to local photo library when CloudKit is unavailable

### 🗄️ SQLite Shared Index Architecture

- **Replaced ChromaDB file-based storage** with SQLite for better cross-platform compatibility
- Shared index location: `~/VibrantFrogPhotoIndex/photo_index.db`
- JSON-serialized embeddings for Swift/Python compatibility
- Optimized indexes for fast date, favorite, and recency queries

### 🔧 Migration Tools

- **One-command migration**: `python migrate_to_icloud.py` migrates existing ChromaDB to SQLite
- Preserves all photo metadata, descriptions, and embeddings
- Non-destructive migration (keeps original ChromaDB as backup)
- Automatic CloudKit sync trigger after successful migration

## Development & Debugging Tools

### CloudKit Debugging
- **Environment Detection**: Automatic detection of Development vs Production CloudKit environments
- **Upload Verification**: `verifyPhotoIndexExists()` function to confirm uploads succeeded
- **Enhanced Logging**: Detailed logging for account status, record types, and field names
- **"Verify Upload" Button**: UI button in IndexingView for manual upload verification

### Repository Cleanup
- **Improved .gitignore**: Excludes build artifacts, user-specific files, and archived scripts
- **Script Organization**: Archived old migration scripts to `scripts/archive/`
- **Reduced Repo Size**: Removed development artifacts (43 MB CoreML model can be regenerated)

## Key Features

### For Mac Users (VibrantFrogMCP)

1. **Enhanced Photo Indexing**:
   - Added `PHCloudIdentifier` extraction for cross-device photo matching
   - Stores both local UUID and cloud GUID for each photo
   - Semantic search using sentence transformers (384-dim embeddings)

2. **Automatic CloudKit Upload**:
   - Background upload of photo index after indexing completes
   - Progress tracking and error recovery
   - Chunked uploads for large databases (>10MB split into chunks)

3. **VibrantFrog Mac App Integration**:
   - New "Index Photos" view for triggering CloudKit sync
   - Visual progress indicators for upload/download status
   - iCloud account status checking

### For iOS/iPad Users (VibrantFrog Collab)

1. **Photo Search Integration**:
   - AI-powered semantic photo search
   - Downloads photo index from CloudKit on first use
   - Converts cloud identifiers to local PHAssets
   - Graceful handling when photos aren't available locally

2. **Quote Image Backgrounds**:
   - AI can search for matching photos and use them as backgrounds
   - Two-step workflow: search photo → create quote image with that photo
   - Full PHAsset.localIdentifier support for reliable photo loading

## Architecture Changes

### Before (ChromaDB-only)
```
Mac: ChromaDB → VibrantFrogMCP → Claude Desktop
```

### After (CloudKit + SQLite)
```
Mac: ChromaDB → SQLite → CloudKit → iOS/iPad
                    ↓
            VibrantFrogMCP (reads SQLite)
                    ↓
            Claude Desktop
```

### Data Flow

1. **Indexing** (Mac only):
   - `index_photos_icloud.py` extracts photo metadata and AI descriptions
   - Generates embeddings using sentence-transformers
   - Stores in SQLite with PHCloudIdentifier for each photo

2. **Upload** (Mac → CloudKit):
   - `CloudKitPhotoIndexSync.swift` uploads photo records to CloudKit
   - Each photo becomes a CKRecord with uuid, description, embedding, cloudGuid
   - Large databases split into manageable chunks

3. **Download** (CloudKit → iOS/iPad):
   - `PhotoSearchService.swift` downloads database on first launch
   - Caches locally for offline search
   - Re-downloads when index is updated

4. **Search** (iOS/iPad):
   - Mac: Direct SQLite semantic search with vector similarity
   - iOS: CloudKit query → convert cloud GUIDs to local identifiers → fetch PHAssets

## Technical Implementation

### New Files

**Python Scripts:**
- `shared_index.py` - SQLite photo index with cross-platform compatibility
- `index_photos_icloud.py` - Photo indexing with CloudKit identifier extraction
- `migrate_to_icloud.py` - ChromaDB → SQLite migration tool
- `trigger_cloudkit_sync.py` - Triggers Mac app to upload to CloudKit
- `setup_icloud_container.py` - iCloud Drive container setup helper
- `convert_to_coreml.py` - CoreML model conversion (future on-device embeddings)

**Swift Services (VibrantFrog Mac App):**
- `CloudKitPhotoIndexSync.swift` - CloudKit upload/download manager
- `IndexingView.swift` - UI for triggering photo indexing and CloudKit sync

**Swift Services (VibrantFrog Collab iOS):**
- `PhotoSearchService.swift` - Photo search with CloudKit integration
- `CloudKitSyncManager.swift` - Download photo index from CloudKit
- `PhotoSearchDatabase.swift` - SQLite query interface for photo search

**Documentation:**
- `MIGRATION_GUIDE.md` - Step-by-step migration from ChromaDB
- `CLOUDKIT_SYNC.md` - CloudKit integration architecture
- `SWIFT_INTEGRATION.md` - Using photo index from Swift/iOS
- `TESTING_GUIDE.md` - Comprehensive testing procedures
- `QUICKSTART.md` - Fast setup for new users
- `COREML_CONVERSION.md` - Future CoreML integration guide

### Modified Files

**VibrantFrogMCP:**
- `vibrant_frog_mcp.py` - Added CloudKit sync trigger after indexing

**VibrantFrog Mac App:**
- `VibrantFrogApp.swift` - Initialize CloudKit sync manager
- `ChatView.swift` - Updated default model to mistral-nemo
- `OllamaService.swift` - Better chat history parsing
- `VibrantFrog.entitlements` - Added CloudKit entitlements

**Entitlements:**
- Added `com.apple.developer.icloud-container-identifiers`
- Added `com.apple.developer.icloud-services` (CloudKit)

## Database Schema

### SQLite Photo Index Table

```sql
CREATE TABLE photo_index (
    uuid TEXT PRIMARY KEY,              -- PHAsset.localIdentifier (Mac) or CloudKit UUID (iOS)
    cloud_guid TEXT,                    -- PHCloudIdentifier.stringValue for cross-device matching
    description TEXT NOT NULL,          -- AI-generated description (LLaVA)
    embedding TEXT NOT NULL,            -- 384-dim vector (JSON array)

    -- Apple Photos Metadata
    filename TEXT,
    date_taken TIMESTAMP,
    location TEXT,
    albums TEXT,                        -- JSON array
    keywords TEXT,                      -- JSON array
    favorite INTEGER,
    width INTEGER,
    height INTEGER,
    orientation TEXT,
    cloud_asset INTEGER,
    has_adjustments INTEGER,

    -- Indexing Metadata
    indexed_at TIMESTAMP,
    indexed_by TEXT,                    -- 'vibrantfrogmcp'
    description_source TEXT,            -- 'llava'
    index_version TEXT                  -- '1.0'
);

CREATE INDEX idx_date_taken ON photo_index(date_taken DESC);
CREATE INDEX idx_favorite ON photo_index(favorite);
CREATE INDEX idx_cloud_guid ON photo_index(cloud_guid);
```

### CloudKit Record Schema

```swift
CKRecord "PhotoIndex" {
    uuid: String                        // Short CloudKit UUID
    cloudGuid: String                   // PHCloudIdentifier.stringValue
    photoDescription: String            // AI-generated description
    embedding: [Double]                 // 384-dim embedding vector
    filename: String?
    dateTaken: Date?
    location: String?
    albums: String?                     // JSON
    keywords: String?                   // JSON
    favorite: Int
    orientation: String?
}
```

## Migration Path

### For Existing ChromaDB Users

1. **Backup existing index** (optional but recommended):
   ```bash
   cp -r ~/Library/Application\ Support/VibrantFrogMCP ~/Desktop/VibrantFrogMCP-backup
   ```

2. **Run migration**:
   ```bash
   cd VibrantFrogMCP
   python migrate_to_icloud.py
   ```

3. **Verify migration**:
   ```bash
   python shared_index.py --stats
   ```

4. **Upload to CloudKit** (automatic or manual):
   - Automatic: Migration script triggers VibrantFrog Mac app
   - Manual: Open VibrantFrog Mac app → "Index Photos" → "Upload to CloudKit"

5. **Test on iOS**:
   - Open VibrantFrog Collab on iPhone/iPad
   - Navigate to photo search
   - Index should download automatically

### For New Users

1. **Index photos**:
   ```bash
   python index_photos_icloud.py
   ```

2. **Upload to CloudKit**:
   - Open VibrantFrog Mac app
   - Click "Upload to CloudKit" in Index Photos view

## Performance Improvements

- **Faster iOS search**: CloudKit queries with server-side filtering
- **Reduced storage**: SQLite more efficient than ChromaDB for this use case
- **Better concurrency**: WAL mode enabled for simultaneous reads/writes
- **Optimized queries**: Indexed columns for common search patterns

## Breaking Changes

⚠️ **None for end users** - Migration script handles ChromaDB → SQLite conversion transparently

For developers:
- Photo index location changed from `~/Library/Application Support/VibrantFrogMCP/photo_index` to `~/VibrantFrogPhotoIndex/photo_index.db`
- Embedding storage changed from ChromaDB format to JSON in SQLite BLOB
- MCP tools now read from SQLite instead of ChromaDB (transparent to Claude Desktop)

## Testing

Comprehensive testing guide added in `TESTING_GUIDE.md`:

- ✅ Mac photo indexing with CloudKit identifiers
- ✅ SQLite database creation and querying
- ✅ CloudKit upload (chunked for large files)
- ✅ iOS CloudKit download and local caching
- ✅ Cross-device photo matching using cloud GUIDs
- ✅ Migration from ChromaDB preserving all data
- ✅ Semantic search accuracy (Mac and iOS)
- ✅ Quote image creation with photo backgrounds

## Security & Privacy

- **Local-first**: Photos never leave your device; only metadata and embeddings sync
- **iCloud encryption**: CloudKit data encrypted in transit and at rest
- **Apple Photos permissions**: Standard PhotoKit permissions required
- **No third-party services**: All processing happens on-device or via Apple's CloudKit

## Future Enhancements

- [ ] On-device embedding generation using CoreML (see `COREML_CONVERSION.md`)
- [ ] Real-time sync when new photos are added to library
- [ ] Face clustering and person search
- [ ] Advanced search filters (date range, location, albums)
- [ ] Photo editing integration
- [ ] Shared photo libraries support

## Dependencies

**New Python dependencies:**
- `osxphotos` - Apple Photos library access (Mac only)
- `sentence-transformers` - Semantic embeddings
- `sqlite3` - Built-in, no install needed

**Removed dependencies:**
- ❌ ChromaDB file-based storage (still used for indexing, but not for sync)

**New iOS/Mac dependencies:**
- `CloudKit.framework` - iCloud synchronization
- `Photos.framework` - Photo library access

## Documentation

This PR includes extensive documentation:

1. **QUICKSTART.md** - Get started in 5 minutes
2. **MIGRATION_GUIDE.md** - Migrate from ChromaDB (detailed walkthrough)
3. **CLOUDKIT_SYNC.md** - CloudKit architecture and troubleshooting
4. **SWIFT_INTEGRATION.md** - Using photo index from Swift/iOS apps
5. **TESTING_GUIDE.md** - Test all functionality
6. **COREML_CONVERSION.md** - Future on-device ML models
7. **RUN_MIGRATION.md** - Quick migration reference

## Credits

This feature enables VibrantFrog to be a truly cross-platform AI writing assistant with seamless photo integration across all Apple devices.

---

**Commits in this PR:** 24 commits
**Files changed:** 29 files
**Lines of documentation:** ~2,500 lines

Ready to merge once reviewed and tested on both Mac and iOS devices.
