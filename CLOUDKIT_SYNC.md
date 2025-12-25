# CloudKit Sync Integration

VibrantFrogMCP now automatically triggers CloudKit sync for seamless iOS integration!

## How It Works

```
VibrantFrogMCP → Flag File → Mac App → CloudKit → iOS App
```

### Workflow

1. **Index Photos** (VibrantFrogMCP)
   ```bash
   python3 index_photos_icloud.py 10
   ```
   - Indexes 10 new photos to `~/VibrantFrogPhotoIndex/photo_index.db`
   - Creates `.needs-cloudkit-sync` flag file

2. **Auto-Upload** (Mac App)
   - Open Vibrant Frog Collab on Mac
   - App detects flag file
   - Automatically uploads database to iCloud (219 MB)
   - Removes flag file after success

3. **Auto-Download** (iOS App)
   - Open Vibrant Frog Collab on iPhone/iPad
   - App checks for updates on launch
   - Downloads database from iCloud if newer version available
   - Search works identically to Mac

## For Users

**One-Time Setup:**
1. Install VibrantFrogMCP on your Mac
2. Run migration: `python3 migrate_to_icloud.py`
3. Open Vibrant Frog Collab on Mac (auto-uploads to iCloud)
4. Open Vibrant Frog Collab on iPhone (auto-downloads from iCloud)

**Ongoing Use:**
- Just run `python3 index_photos_icloud.py` when you have new photos
- Next time you open the Mac app, it auto-syncs
- iPhone/iPad get the update automatically

**No manual sync buttons needed!**

## For Developers

### Trigger File

**Location**: `~/VibrantFrogPhotoIndex/.needs-cloudkit-sync`

**Format**:
```
# CloudKit Sync Needed
# Generated: 2025-12-24T21:00:00
# Database: /Users/user/VibrantFrogPhotoIndex/photo_index.db
# Size: 218.7 MB

sync_needed=true
```

### Python API

```python
from trigger_cloudkit_sync import trigger_sync

# After indexing or migration
trigger_sync()  # Creates flag file
```

### Integration Points

1. **index_photos_icloud.py**: Triggers sync after successful indexing
2. **migrate_to_icloud.py**: Triggers sync after migration
3. **Your custom scripts**: Call `trigger_sync()` after updating the database

### Mac App Integration

The Mac app (`PhotoSearchService.swift`) checks for the flag file on launch:

```swift
private func checkForAutoUpload() async {
    let flagFile = homeDir.appendingPathComponent(
        "VibrantFrogPhotoIndex/.needs-cloudkit-sync"
    )

    if FileManager.default.fileExists(atPath: flagFile.path) {
        try await uploadToCloud()  // Auto-upload
        try? FileManager.default.removeItem(at: flagFile)  // Remove flag
    }
}
```

## Manual Override

If auto-sync fails, users can still manually upload:
- Mac: "Upload to iCloud" button in photo search
- iOS: "Sync from iCloud" button in photo search

## Troubleshooting

### Flag file not being created
- Check permissions on `~/VibrantFrogPhotoIndex/`
- Ensure `trigger_cloudkit_sync.py` is in VibrantFrogMCP directory

### Mac app not auto-uploading
- Check Console.app for "CloudKit sync" messages
- Ensure iCloud is signed in (System Settings → Apple ID)
- Try manual "Upload to iCloud" button

### iOS not downloading
- Check iCloud signed in on device
- Ensure WiFi connection (large download)
- Try manual "Sync from iCloud" button

## Benefits

- **Zero manual intervention**: Just run VibrantFrogMCP
- **Automatic propagation**: Updates reach all devices
- **Reliable**: Falls back to manual sync if auto-sync fails
- **User-friendly**: No technical knowledge required

## Future Enhancements

- Real-time file watching (instead of on-launch detection)
- Incremental sync (delta updates instead of full database)
- Background sync without opening app
- Conflict resolution for concurrent updates
