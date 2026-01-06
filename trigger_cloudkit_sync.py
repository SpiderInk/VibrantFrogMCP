#!/usr/bin/env python3
"""
Trigger CloudKit sync by creating a flag file.

This is called by VibrantFrogMCP after indexing photos.
The Mac app (Vibrant Frog Collab) watches for this file and auto-uploads to CloudKit.
"""

import os
from pathlib import Path
from datetime import datetime

# Path to shared index directory
INDEX_DIR = Path.home() / "VibrantFrogPhotoIndex"
SYNC_FLAG_FILE = INDEX_DIR / ".needs-cloudkit-sync"
DATABASE_FILE = INDEX_DIR / "photo_index.db"


def trigger_sync():
    """Create flag file to trigger CloudKit sync in Mac app."""

    # Ensure index directory exists
    INDEX_DIR.mkdir(parents=True, exist_ok=True)

    # Check if database exists
    if not DATABASE_FILE.exists():
        print(f"❌ Database not found: {DATABASE_FILE}")
        print("   Run migration or indexing first.")
        return False

    # Get database stats
    db_size = DATABASE_FILE.stat().st_size
    db_size_mb = db_size / 1024 / 1024

    # Create sync flag file with metadata
    sync_info = {
        "timestamp": datetime.now().isoformat(),
        "database_path": str(DATABASE_FILE),
        "database_size_mb": round(db_size_mb, 2),
        "triggered_by": "VibrantFrogMCP"
    }

    with open(SYNC_FLAG_FILE, "w") as f:
        f.write(f"# CloudKit Sync Needed\n")
        f.write(f"# Generated: {sync_info['timestamp']}\n")
        f.write(f"# Database: {sync_info['database_path']}\n")
        f.write(f"# Size: {sync_info['database_size_mb']} MB\n")
        f.write(f"\n")
        f.write(f"sync_needed=true\n")

    print(f"✅ CloudKit sync triggered")
    print(f"   Flag file: {SYNC_FLAG_FILE}")
    print(f"   Database: {db_size_mb:.1f} MB")
    print(f"\n📱 Vibrant Frog Collab on Mac will auto-upload to iCloud when opened.")

    return True


if __name__ == "__main__":
    trigger_sync()
