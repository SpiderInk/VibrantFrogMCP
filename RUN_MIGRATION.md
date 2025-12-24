# Run Migration - Simple Steps

## Now it's Easy! No Permission Issues!

The migration now uses `~/VibrantFrogPhotoIndex` which works everywhere without permission problems.

## Steps:

```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# Activate venv (if using one)
source venv/bin/activate

# Run migration
python3 migrate_to_icloud.py
```

## Expected Output:

```
============================================================
VibrantFrogMCP → iCloud Migration
============================================================

✅ Created shared index directory: /Users/tpiazza/VibrantFrogPhotoIndex
   (This can be moved to iCloud Drive later for device sync)

📂 Loading existing ChromaDB from: ~/Library/Application Support/VibrantFrogMCP/photo_index
✅ Loaded ChromaDB collection: 'photos'

📊 Fetching all indexed photos from ChromaDB...
✅ Found 21,554 indexed photos

📝 Creating SQLite database at: ~/VibrantFrogPhotoIndex/photo_index.db
✅ Created SQLite schema

🔄 Migrating 21,554 photos to SQLite...
  Progress: 1000/21554 (4.6%)
  Progress: 2000/21554 (9.3%)
  ...
  Progress: 21554/21554 (100.0%)

✅ Migration complete!
   Migrated: 21,554 photos
   Database size: ~42 MB

📊 Database Statistics:
   Location: /Users/tpiazza/VibrantFrogPhotoIndex/photo_index.db
   Size: 42.1 MB
   Photos: 21,554

============================================================
Migration Complete! 🎉
============================================================
```

## Verify It Worked:

```bash
# Check the database was created
ls -lh ~/VibrantFrogPhotoIndex/

# Should show:
# photo_index.db        (~42 MB)
# indexed_photos.json   (~1 MB)

# Show stats
python3 shared_index.py --stats
```

## What This Path Means:

**~/VibrantFrogPhotoIndex**
- ✅ Works on all Macs without permission issues
- ✅ Easy for new users - no setup required
- ✅ VibrantFrog Collab (Mac) can read from here
- ❌ Won't auto-sync to iOS (yet)

## For iOS Sync (Later):

We'll add iCloud sync to VibrantFrog Collab app in a future step. The app will:
1. Read from `~/VibrantFrogPhotoIndex` on Mac
2. Sync via CloudKit to iOS (like your projects do now)
3. No manual file moving needed

This keeps it simple and working now!
