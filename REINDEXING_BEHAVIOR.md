# Reindexing Behavior Guide

## What Happens When You Reindex an Existing Photo?

### Before the Fix (Old Behavior)
- ❌ **ChromaDB would error**: `collection.add()` throws `IDAlreadyExistsError` if UUID exists
- ✅ **Script had protection**: Cache system (`indexed_photos.json`) prevented reprocessing by default
- ⚠️ **Problem**: If you wanted to force reindex (e.g., after changing the prompt), you couldn't

### After the Fix (New Behavior)
- ✅ **Graceful updates**: `collection.upsert()` updates existing entries or adds new ones
- ✅ **Cache still works**: Skip already-indexed photos by default (saves time)
- ✅ **Force reindex option**: You can now safely reindex if needed

## How to Control Indexing Behavior

### 1. Normal Operation (Skip Already Indexed)
```bash
# Only index NEW photos (default behavior)
python index_photos.py

# This uses the cache in:
# ~/Library/Application Support/VibrantFrogMCP/indexed_photos.json
```

**What happens:**
- ✅ Checks cache for already-indexed UUIDs
- ⏭️ Skips photos already in cache
- 🚀 Only processes new photos
- ⏱️ Fast - no wasted LLaVA calls

### 2. Force Reindex Specific Photos
```bash
# Edit the cache file to remove specific UUIDs
code ~/Library/Application\ Support/VibrantFrogMCP/indexed_photos.json

# Remove the UUID(s) you want to reindex, then run:
python index_photos.py
```

**What happens:**
- 🔄 Photo with removed UUID will be reprocessed
- 📝 New description generated (uses updated LLaVA prompt)
- ♻️ ChromaDB entry updated with new data via `upsert()`
- ✅ No errors even though UUID already exists in ChromaDB

### 3. Force Reindex ALL Photos
```bash
# Delete the entire cache file
rm ~/Library/Application\ Support/VibrantFrogMCP/indexed_photos.json

# Then run indexing
python index_photos.py
```

**What happens:**
- 🔄 ALL photos will be reprocessed
- ⏰ This will take a VERY long time (10+ min per photo)
- ♻️ All ChromaDB entries updated with fresh descriptions
- 💡 Useful if you changed the LLaVA prompt and want better descriptions

### 4. Reindex WITHOUT Skipping (Advanced)

You could modify the code to add a command-line flag:

```python
# In index_photos.py, around line 300
if arg == '--force-reindex':
    skip_indexed = False
```

Then run:
```bash
python index_photos.py --force-reindex
```

## Why Use Upsert?

### Scenarios Where Reindexing is Useful

1. **Improved Prompts**: You enhanced the LLaVA prompt to ask for orientation/quality
   - Existing photos have old descriptions
   - Reindex to get richer descriptions

2. **Metadata Changes**: Photo albums, keywords, or location updated in Apple Photos
   - Reindex to update metadata in ChromaDB

3. **Bug Fixes**: You fixed a bug in metadata extraction
   - Reindex affected photos to correct the data

4. **Model Upgrades**: You switch from `llava:7b` to `llava:13b`
   - Reindex for higher-quality descriptions

### Performance Impact

**With upsert:**
- Same speed as add for new photos
- Slightly slower for updates (delete old + add new)
- No errors or crashes

**Memory impact:**
- Minimal - same as before
- Old embeddings replaced by new ones
- No accumulation of duplicates

## Best Practices

### ✅ DO:
- Keep the cache file for normal operation
- Remove specific UUIDs from cache when you need to reindex individual photos
- Document why you're reindexing (e.g., "updated prompt to include quality")

### ❌ DON'T:
- Don't delete the cache file casually (reindexing is expensive)
- Don't reindex just to "refresh" - only when you have a specific reason
- Don't forget how long reindexing takes (10+ min per photo with llava:13b)

## Checking What's in ChromaDB

```bash
# View all indexed photos in the web browser
python browse_chromadb_web.py
# Then open http://localhost:8080
```

Compare the count:
- **ChromaDB count**: Number of photos in the database
- **Cache file count**: Number of UUIDs in `indexed_photos.json`

These should match! If not:
- Cache has more → some photos failed to index
- ChromaDB has more → cache file was deleted/corrupted

## Example: Reindexing One Photo

```bash
# 1. Find the photo's UUID in the web browser
python browse_chromadb_web.py
# Note the UUID, e.g., "68744A05-F6D2-422B-871D-42C2121731A6"

# 2. Edit the cache file
code ~/Library/Application\ Support/VibrantFrogMCP/indexed_photos.json

# 3. Remove that UUID from the JSON array

# 4. Save and run indexing
python index_photos.py

# 5. The photo will be reprocessed and updated in ChromaDB
```

The entry in ChromaDB will be updated with the new description and metadata!
