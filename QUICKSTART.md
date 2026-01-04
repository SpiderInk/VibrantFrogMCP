# Quick Start: Migrate Your Photos to Shared Index

## The iCloud Container Issue

macOS protects the `Mobile Documents/iCloud~...` folders with special permissions. Python can't create them directly.

## Simple Solution: Two Options

### Option 1: Create Container via Finder (Recommended - 30 seconds)

The easiest way is to create the folder using Finder, which has the right permissions:

1. **Open Finder**
2. **Press `Cmd+Shift+G`** (Go to Folder)
3. **Paste this path:**
   ```
   ~/Library/Mobile Documents/
   ```
4. **Create new folder** (Right-click → New Folder)
5. **Name it exactly:**
   ```
   iCloud~com~vibrantfrog~AuthorAICollab
   ```
6. **Inside that folder, create another folder:**
   ```
   PhotoSearch
   ```

Now you have:
```
~/Library/Mobile Documents/
└── iCloud~com~vibrantfrog~AuthorAICollab/
    └── PhotoSearch/              ← Ready for migration!
```

**Then run:**
```bash
cd VibrantFrogMCP
python3 migrate_to_icloud.py
```

---

### Option 2: Use Documents Folder (Quick Test - 10 seconds)

For quick testing, just put it in your Documents folder instead:

**Edit `migrate_to_icloud.py` line 24:**
```python
# OLD:
ICLOUD_CONTAINER = Path.home() / "Library/Mobile Documents/iCloud~com~vibrantfrog~AuthorAICollab"

# NEW (temporary):
ICLOUD_CONTAINER = Path.home() / "Documents/VibrantFrogPhotoIndex"
```

**Then run:**
```bash
python3 migrate_to_icloud.py
```

**Result:**
- Your 21,554 photos will be migrated to `~/Documents/VibrantFrogPhotoIndex/`
- Won't sync via iCloud (local only)
- Good for testing
- Can move to iCloud later

---

### Option 3: Python Creates It (If Permissions Allow)

**Try this command:**
```bash
cd VibrantFrogMCP
python3 -c "
from pathlib import Path
import os

container = Path.home() / 'Library/Mobile Documents/iCloud~com~vibrantfrog~AuthorAICollab'
photo_search = container / 'PhotoSearch'

try:
    # Try to create it
    photo_search.mkdir(parents=True, exist_ok=True)
    print(f'✅ Created: {photo_search}')
except PermissionError as e:
    print(f'❌ Permission denied. Please use Option 1 (Finder) instead.')
    print(f'   Or use Option 2 (Documents folder)')
"
```

If this works, great! If not, use Option 1.

---

## After Container is Created

Once the folder exists (via any method), run migration:

```bash
cd VibrantFrogMCP
python3 migrate_to_icloud.py
```

**Expected output:**
```
============================================================
VibrantFrogMCP → iCloud Migration
============================================================

Checking iCloud Drive availability...
✅ iCloud Drive found
✅ Created iCloud container
✅ Created PhotoSearch directory

📂 Loading existing ChromaDB...
✅ Found 21,554 indexed photos

🔄 Migrating 21,554 photos to SQLite...
  Progress: 1000/21554 (4.6%)
  Progress: 2000/21554 (9.3%)
  ...
  Progress: 21554/21554 (100.0%)

✅ Migration complete!
   Migrated: 21,554 photos
   Database size: ~42 MB
```

---

## Verification

After migration, check it worked:

```bash
# Show stats
python3 shared_index.py --stats

# Should show:
# Total Photos: 21,554
# Database Path: .../PhotoSearch/photo_index.db
```

---

## Recommendation

**Use Option 1 (Finder)** - it's the cleanest and most reliable.

Creating the folder via Finder ensures macOS sets up the right permissions and iCloud metadata.
