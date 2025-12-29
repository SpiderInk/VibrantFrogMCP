#!/bin/bash
# Simple reconciliation without osxphotos dependency

echo "======================================================================"
echo "Photo Index Reconciliation"
echo "======================================================================"
echo ""

# Get index stats
echo "📂 Index Database:"
INDEX_COUNT=$(sqlite3 ~/VibrantFrogPhotoIndex/photo_index.db "SELECT COUNT(*) FROM photo_index")
LAST_INDEXED=$(sqlite3 ~/VibrantFrogPhotoIndex/photo_index.db "SELECT MAX(indexed_at) FROM photo_index")
WITH_CLOUD=$(sqlite3 ~/VibrantFrogPhotoIndex/photo_index.db "SELECT COUNT(*) FROM photo_index WHERE cloud_guid IS NOT NULL AND cloud_guid != ''")
WITHOUT_CLOUD=$(sqlite3 ~/VibrantFrogPhotoIndex/photo_index.db "SELECT COUNT(*) FROM photo_index WHERE cloud_guid IS NULL OR cloud_guid = ''")

echo "   Photos indexed:       $INDEX_COUNT"
echo "   With cloud_guid:      $WITH_CLOUD"
echo "   Without cloud_guid:   $WITHOUT_CLOUD"
echo "   Last indexed:         $LAST_INDEXED"
echo ""

# Get Photos library stats
echo "📷 Photos Library:"
TOTAL_MEDIA=$(osascript -e 'tell application "Photos" to count of media items' 2>/dev/null || echo "Unable to count")

# Get the Photos database location
PHOTOS_DB_DIR="$HOME/Pictures/Photos Library.photoslibrary/database"
if [ -d "$PHOTOS_DB_DIR" ]; then
    # Try to count photos in the library (this is approximate)
    PHOTOS_DB="$PHOTOS_DB_DIR/photos.db"
    if [ -f "$PHOTOS_DB" ]; then
        # Query the Photos database (read-only)
        PHOTO_COUNT=$(sqlite3 "$PHOTOS_DB" "SELECT COUNT(*) FROM ZASSET WHERE ZKIND = 0" 2>/dev/null || echo "Unable to query")
        echo "   Total media items:    $TOTAL_MEDIA"
        echo "   Photos (kind=0):      $PHOTO_COUNT"
    else
        echo "   Total media items:    $TOTAL_MEDIA"
    fi
else
    echo "   Total media items:    $TOTAL_MEDIA"
fi

echo ""
echo "======================================================================"
echo "ANALYSIS"
echo "======================================================================"
echo ""

# Calculate difference
if [ "$PHOTO_COUNT" != "Unable to query" ] && [ -n "$PHOTO_COUNT" ]; then
    DIFF=$((PHOTO_COUNT - INDEX_COUNT))
    echo "Photos in library:        $PHOTO_COUNT"
    echo "Photos in index:          $INDEX_COUNT"
    echo "Difference:               $DIFF"
    echo ""

    if [ $DIFF -gt 0 ]; then
        echo "⚠️  There are $DIFF photos in your library that are NOT in the index."
        echo ""
        echo "   This includes photos added after: $LAST_INDEXED"
        echo ""
    elif [ $DIFF -lt 0 ]; then
        ORPHANED=$((-DIFF))
        echo "🗑️  There are $ORPHANED entries in the index for deleted photos."
        echo ""
    else
        echo "✅ Index is up to date!"
        echo ""
    fi
fi

# Check for recent photos
DAYS_SINCE_INDEX=$(( ($(date +%s) - $(date -j -f "%Y-%m-%d %H:%M:%S" "$LAST_INDEXED" +%s 2>/dev/null || echo 0)) / 86400 ))
if [ $DAYS_SINCE_INDEX -gt 1 ]; then
    echo "⚠️  Index is $DAYS_SINCE_INDEX days old!"
    echo "   Photos added in the last $DAYS_SINCE_INDEX days are NOT searchable."
    echo ""
fi

# Check cloud_guid coverage
if [ $WITHOUT_CLOUD -gt 0 ]; then
    echo "⚠️  $WITHOUT_CLOUD photos are missing cloud_guid!"
    echo "   These photos may not resolve correctly on iOS devices."
    echo ""
fi

echo "======================================================================"
echo "RECOMMENDATIONS"
echo "======================================================================"
echo ""

if [ $DIFF -gt 0 ] || [ $DAYS_SINCE_INDEX -gt 1 ]; then
    echo "To index missing photos:"
    echo ""
    echo "  # Index all new photos (may take hours if many are missing)"
    echo "  cd /Users/tpiazza/git/VibrantFrogMCP"
    echo "  python3 index_photos_icloud.py"
    echo ""
    echo "  # Or just index the newest 100"
    echo "  python3 index_photos_icloud.py 100"
    echo ""
fi

if [ $WITHOUT_CLOUD -gt 0 ]; then
    echo "To enrich database with cloud_guid:"
    echo ""
    echo "  # Run from VibrantFrogApp (Mac app with Photos access)"
    echo "  # Click 'Enrich & Upload to iCloud' button"
    echo ""
fi

echo "======================================================================"
