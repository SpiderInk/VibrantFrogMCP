# Photo Retrieval Guide

## How Photo Storage and Retrieval Works

### Indexing Phase

When you run `index_photos.py`, here's what happens:

1. **Photo Access**: For each photo in Apple Photos:
   - First tries to access the local file directly (fastest)
   - If photo is in iCloud and not downloaded, exports to a temporary directory

2. **Description Generation**: The photo is analyzed by LLaVA vision model

3. **Temporary Cleanup**: If the photo was exported from iCloud, the temporary file is **immediately deleted** after description generation (lines 158-164 in index_photos.py)

4. **Metadata Storage**: The following metadata is stored in ChromaDB:
   ```python
   {
       'uuid': photo.uuid,           # PRIMARY KEY - use this to retrieve photo later!
       'path': photo.path,            # Local filesystem path (None if iCloud-only)
       'path_edited': photo.path_edited,  # Edited version path (if exists)
       'filename': photo.original_filename,
       'cloud_asset': photo.iscloudasset,  # True = needs iCloud download to view
       'width': photo.width,
       'height': photo.height,
       'orientation': 'landscape|portrait|square',
       'has_adjustments': bool,       # True if photo has been edited
       # ... plus date, location, albums, keywords, etc.
   }
   ```

### Retrieval Phase

When you want to display a photo from search results:

#### Option 1: Use the Helper Module

```python
from photo_retrieval import get_photo_path_for_display, cleanup_temp_photo

# Get photo path by UUID (from search results metadata)
uuid = "68744A05-F6D2-422B-871D-42C2121731A6"
path, needs_cleanup = get_photo_path_for_display(uuid, export_if_needed=True)

if path:
    # Display/use the photo
    print(f"Photo available at: {path}")

    # Clean up if it was a temp export
    if needs_cleanup:
        cleanup_temp_photo(path)
```

#### Option 2: Manual Retrieval

```python
import osxphotos

# Get photo by UUID
photosdb = osxphotos.PhotosDB()
photos = photosdb.photos(uuid=["68744A05-F6D2-422B-871D-42C2121731A6"])

if photos:
    photo = photos[0]

    # Try local path first
    if photo.path and os.path.exists(photo.path):
        use_photo(photo.path)

    # Or export from iCloud if needed
    elif photo.iscloudasset:
        temp_dir = tempfile.mkdtemp()
        exported = photo.export(temp_dir)
        if exported:
            use_photo(exported[0])
            # Remember to clean up temp files!
            os.remove(exported[0])
            os.rmdir(temp_dir)
```

## Understanding the Metadata

### Example Metadata from ChromaDB

```
UUID: 68744A05-F6D2-422B-871D-42C2121731A6  ← Use this to retrieve photo!
Path: None  ← Photo not downloaded locally
cloud_asset: True  ← Must export from iCloud to view
filename: IMG_8948.HEIC
orientation: portrait
width: 3024
height: 4032
```

This tells you:
- ✅ The UUID is the key to retrieve the photo
- ⚠️ Photo is in iCloud (path is None, cloud_asset is True)
- 📱 You'll need to export it temporarily to view it
- 🗑️ Remember to delete the export after use

### Local Photo Example

```
UUID: ABC123-DEF456-...
Path: /Users/you/Pictures/Photos Library.photoslibrary/originals/...
cloud_asset: False
```

This tells you:
- ✅ Photo is available locally at the path shown
- 🚀 No export needed - can use directly
- 💾 No cleanup needed

## Disk Space Management

### During Indexing
- ✅ Temporary exports are **immediately deleted** after description generation
- ✅ Only the description and metadata are stored
- ✅ No permanent disk space used for photo duplicates

### During Retrieval
- ⚠️ If you export an iCloud photo for viewing, **you must clean it up**
- ⚠️ Failure to clean up will accumulate temp files over time
- ✅ Use `cleanup_temp_photo()` helper or manually delete

## Key Principles

1. **UUID is Everything**: The UUID is all you need to retrieve any photo from Apple Photos Library

2. **No Duplication**: We never store photo files themselves, only descriptions and metadata

3. **On-Demand Export**: iCloud photos are exported only when needed, then deleted

4. **Stateless**: Each retrieval is independent - export, use, delete

## Testing Photo Retrieval

Test the retrieval system:

```bash
# Test retrieving a photo by UUID
python photo_retrieval.py "68744A05-F6D2-422B-871D-42C2121731A6"
```

Expected output:
```
Looking up photo with UUID: 68744A05-F6D2-422B-871D-42C2121731A6
Found: IMG_8948.HEIC
Date: 2023-12-22 09:31:54.784000-05:00
iCloud: True
Exporting iCloud photo to temp directory...
Photo exported successfully to /tmp/xyz/IMG_8948.HEIC
Path: /tmp/xyz/IMG_8948.HEIC
Needs cleanup: True
Cleaned up temporary export
```

## Performance Notes

Based on the logging you'll see:

1. **Local photos**: Very fast (< 0.1s to access)
2. **iCloud exports**: Slow (depends on network, file size)
3. **Description generation**: VERY slow (~10+ minutes per photo with llava:13b)
4. **ChromaDB operations**: Fast (< 2s)

The bottleneck is definitely the LLaVA model inference, not photo access or storage.
