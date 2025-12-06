# Batch Indexing Guide

## Why Index Newest Photos First?

**Problem:** You have 21,251 photos. At 2-3 minutes per photo, indexing everything would take weeks.

**Solution:** Index newest photos first, in manageable batches.

### Benefits:
- ✅ Get useful results immediately (recent photos are most relevant)
- ✅ Can start searching while older photos index in background
- ✅ Stop anytime - progress is saved
- ✅ Resume later exactly where you left off

---

## Recommended Workflow

### Step 1: Index First Batch (500 newest photos)

```bash
python index_photos.py 500
```

**What happens:**
```
📷 Opening Apple Photos Library...
📊 Found 5 already indexed photos
📊 Total photos in library: 21251
📊 Sorted by date (newest first)
   Newest: 2025-11-16 - IMG_9999.jpg
   Oldest: 2020-01-01 - IMG_1234.jpg
📊 New photos to index: 21246
📊 Processing batch of 500 photos (out of 21246 remaining)

[1/500] Starting photo processing
...
```

**Expected time:** 16-25 hours (run overnight)

### Step 2: Test Your Indexed Photos

While the next batch runs, test what you've indexed:

```bash
# Browse indexed photos
python browse_chromadb_web.py
# Open http://localhost:8080

# Or test MCP server in Claude Desktop
# (if configured)
```

### Step 3: Continue with More Batches

```bash
# Another 500 photos (continues from where batch 1 left off)
python index_photos.py 500

# After that completes, another 500
python index_photos.py 500

# And so on...
```

**Each run automatically:**
- Skips already-indexed photos
- Processes next 500 oldest unindexed photos (newest first)
- Saves progress after each photo

---

## Command Reference

### Basic Commands

```bash
# Index 500 newest unindexed photos
python index_photos.py 500

# Index 1000 newest unindexed photos
python index_photos.py 1000

# Index ALL remaining photos (could take weeks!)
python index_photos.py

# Show help
python index_photos.py --help
```

### Advanced Options

```bash
# Index only local photos (no iCloud downloads)
python index_photos.py 500 --local-only

# Start with oldest photos instead (not recommended)
python index_photos.py 500 --oldest-first

# Combine options
python index_photos.py 100 --local-only --oldest-first
```

---

## Time Estimates

Based on **2-3 minutes per photo** with llava:7b:

| Photos | Time (Min) | Time (Max) | Recommended |
|--------|-----------|-----------|-------------|
| 10 | 20 min | 30 min | Quick test |
| 50 | 1.7 hrs | 2.5 hrs | Short session |
| 100 | 3.3 hrs | 5 hrs | Half-day run |
| 500 | 16.7 hrs | 25 hrs | **Overnight batch** ✅ |
| 1000 | 33 hrs | 50 hrs | Weekend run |
| 5000 | 7 days | 10 days | Run in 10x batches of 500 |
| 21251 | 29 days | 44 days | Run in 43x batches of 500 |

**Recommendation:** Batches of 500 are perfect for overnight indexing sessions.

---

## Managing Long-Running Indexing

### Option 1: Run Overnight in Terminal

```bash
# Start before bed
python index_photos.py 500

# Wake up to 500 new indexed photos!
```

### Option 2: Run in Background (Advanced)

```bash
# Run in background, output to log file
nohup python index_photos.py 500 > indexing.log 2>&1 &

# Check progress
tail -f indexing.log

# Check if still running
ps aux | grep index_photos
```

### Option 3: Use tmux/screen (Recommended for SSH)

```bash
# Create tmux session
tmux new -s indexing

# Inside tmux, start indexing
python index_photos.py 500

# Detach from tmux (Ctrl+B, then D)
# Session keeps running!

# Later, reattach to check progress
tmux attach -t indexing
```

---

## Progress Tracking

### Check How Many Photos Are Indexed

```bash
# Count entries in cache file
cat ~/Library/Application\ Support/VibrantFrogMCP/indexed_photos.json | jq '. | length'

# Or check ChromaDB count via web browser
python browse_chromadb_web.py
# Open http://localhost:8080 - shows total count
```

### Monitor Live Progress

The script logs progress every photo:

```
[245/500] Starting photo processing
🔍 Processing: IMG_7890.jpeg
  ├─ Photo path resolution: 0.00s
  ├─ Description generation: 145.32s
  ├─ Metadata preparation: 0.01s
  ├─ ChromaDB upsert: 1.87s
  └─ Total time: 147.20s
💾 Cache saved - 750 total indexed
✅ Indexed: IMG_7890.jpeg
Photo 245 completed in 147.20s
Average time per photo: 152.34s
Estimated time remaining: 64.8 minutes  ← Very useful!
```

---

## Interrupting and Resuming

### Safe Interruption

Press **Ctrl+C** at any time:

```
^C
2025-11-16 23:45:12 - INFO - ✨ Done! Indexed 87 new photos
2025-11-16 23:45:12 - INFO - 📊 Total indexed: 592
```

**Everything is saved!** No work is lost.

### Resuming

Just run the same command again:

```bash
# Same command as before
python index_photos.py 500
```

**What happens:**
```
📊 Found 592 already indexed photos  ← Picks up where you left off!
📊 New photos to index: 20659
📊 Processing batch of 500 photos
```

It automatically:
- Loads cache of 592 indexed photos
- Skips those 592
- Processes next 500 unindexed (newest remaining)

---

## Example: Indexing 5000 Photos Over 2 Weeks

**Goal:** Index 5000 newest photos

**Strategy:** 10 batches of 500, running overnight

### Week 1:
```bash
# Monday night
python index_photos.py 500  # → 500 indexed

# Tuesday night
python index_photos.py 500  # → 1000 total

# Wednesday night
python index_photos.py 500  # → 1500 total

# Thursday night
python index_photos.py 500  # → 2000 total

# Friday night
python index_photos.py 500  # → 2500 total
```

### Week 2:
```bash
# Monday through Friday (same pattern)
# → 5000 total indexed!
```

**Result:** Searchable library of 5000 most recent photos!

---

## Monitoring Performance

### If Indexing Seems Slow

Check actual per-photo time in logs:

```
Average time per photo: 152.34s  ← ~2.5 minutes (good!)
```

If > 300s (5 minutes):
- Check if Mac went to sleep (disable sleep in System Preferences)
- Check if Ollama is running: `ps aux | grep ollama`
- Check if GPU is being used properly

### If Indexing Fails

Common issues:

1. **"Photo not found"** - Photo deleted from library
   - Script skips it automatically

2. **"Could not access photo"** - iCloud photo not downloaded
   - Use `--local-only` flag to skip iCloud photos

3. **"Ollama error"** - Ollama crashed
   - Restart Ollama: `killall ollama && ollama serve`
   - Resume indexing with same command

---

## Best Practices

### ✅ DO:
- Start with 500-photo batches
- Run overnight when you won't need your Mac
- Let complete batches finish before interrupting
- Check progress periodically via web browser
- Test search after first 100-500 photos

### ❌ DON'T:
- Don't start with all 21,251 photos at once
- Don't let your Mac go to sleep during indexing
- Don't delete cache file unless you want to start over
- Don't run multiple indexing processes simultaneously

---

## Quick Start: Your First 500 Photos

```bash
# 1. Start indexing 500 newest photos
python index_photos.py 500

# 2. Let it run overnight (~16-25 hours)

# 3. Next day: check results
python browse_chromadb_web.py

# 4. Continue with next batch when ready
python index_photos.py 500
```

That's it! You're now indexing your library efficiently, newest photos first, in manageable batches.
