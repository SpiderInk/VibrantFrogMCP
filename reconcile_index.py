#!/usr/bin/env python3
"""
Reconcile photo index with Photos library

Identifies:
1. Photos in library that are missing from index
2. Photos in index that are no longer in library (deleted)
3. Why recent photos haven't been indexed
"""

import sys
from pathlib import Path
import sqlite3
from datetime import datetime, timedelta

try:
    import osxphotos
except ImportError:
    print("❌ Error: osxphotos not installed")
    print("Install with: pip3 install osxphotos")
    sys.exit(1)

from shared_index import SharedPhotoIndex


def reconcile():
    print("=" * 70)
    print("Photo Index Reconciliation")
    print("=" * 70)
    print()

    # Connect to shared index
    print("📂 Opening index database...")
    shared_index = SharedPhotoIndex()
    indexed_uuids = shared_index.get_indexed_uuids()

    # Get database stats
    stats = shared_index.get_stats()
    print(f"   ✓ Database: {stats['total_photos']} photos indexed")
    print(f"   ✓ Last indexed: {stats.get('last_updated', 'Never')}")
    print()

    # Open Photos library
    print("📷 Opening Apple Photos Library...")
    photosdb = osxphotos.PhotosDB()

    # Get all images (not videos)
    all_photos = photosdb.photos(images=True, movies=False)
    print(f"   ✓ Library: {len(all_photos)} photos (images only, no videos)")
    print()

    # Find missing photos
    library_uuids = {p.uuid for p in all_photos}
    missing_from_index = library_uuids - indexed_uuids
    missing_from_library = indexed_uuids - library_uuids

    print("=" * 70)
    print("RECONCILIATION RESULTS")
    print("=" * 70)
    print()

    # Report missing from index
    if missing_from_index:
        print(f"⚠️  {len(missing_from_index)} photos in library but NOT in index")

        # Get the missing photos and sort by date
        missing_photos = [p for p in all_photos if p.uuid in missing_from_index]
        missing_photos.sort(key=lambda p: p.date if p.date else datetime.min, reverse=True)

        # Show newest 10
        print(f"\n   📅 Newest 10 missing photos:")
        for i, photo in enumerate(missing_photos[:10], 1):
            date_str = photo.date.strftime('%Y-%m-%d %H:%M') if photo.date else 'No date'
            cloud = "☁️" if photo.iscloudasset else "💾"
            print(f"   {i:2d}. {cloud} {date_str} - {photo.original_filename}")

        # Show oldest 10
        if len(missing_photos) > 10:
            print(f"\n   📅 Oldest 10 missing photos:")
            for i, photo in enumerate(missing_photos[-10:], 1):
                date_str = photo.date.strftime('%Y-%m-%d %H:%M') if photo.date else 'No date'
                cloud = "☁️" if photo.iscloudasset else "💾"
                print(f"   {i:2d}. {cloud} {date_str} - {photo.original_filename}")

        # Count how many are recent (last 7 days)
        from datetime import timezone
        week_ago = datetime.now(timezone.utc) - timedelta(days=7)
        recent_missing = [p for p in missing_photos if p.date and p.date.replace(tzinfo=timezone.utc) > week_ago]
        if recent_missing:
            print(f"\n   🔔 {len(recent_missing)} missing photos are from the last 7 days!")
            print(f"      This explains why recent photos don't appear in search.")
    else:
        print("✅ All library photos are indexed!")

    print()

    # Report orphaned entries
    if missing_from_library:
        print(f"🗑️  {len(missing_from_library)} photos in index but NOT in library")
        print(f"    These photos may have been deleted from Photos.")
    else:
        print("✅ No orphaned entries in index!")

    print()
    print("=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"Photos in library:      {len(library_uuids):,}")
    print(f"Photos in index:        {len(indexed_uuids):,}")
    print(f"Missing from index:     {len(missing_from_index):,}")
    print(f"Orphaned in index:      {len(missing_from_library):,}")
    print()

    # Recommendations
    if missing_from_index:
        print("💡 RECOMMENDATIONS:")
        print()
        print("   To index all missing photos:")
        print("   $ python3 index_photos_icloud.py")
        print()
        print("   To index just the newest 100:")
        print("   $ python3 index_photos_icloud.py 100")
        print()
        print("   To index just the oldest missing:")
        print("   $ python3 index_photos_icloud.py 100 --oldest-first")
        print()

    if missing_from_library:
        print("   To clean up orphaned entries, you could:")
        print("   1. Keep them (no harm, just wasted space)")
        print("   2. Write a cleanup script to remove them")
        print()

    print("=" * 70)


if __name__ == "__main__":
    try:
        reconcile()
    except KeyboardInterrupt:
        print("\n\n❌ Cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
