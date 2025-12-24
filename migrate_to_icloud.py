#!/usr/bin/env python3
"""
Migrate existing ChromaDB photo index to shared iCloud SQLite format

This script:
1. Reads your existing ChromaDB index
2. Converts to SQLite format
3. Saves to iCloud Drive for VibrantFrog Collab access
"""

import os
import sqlite3
import json
import chromadb
from pathlib import Path
from datetime import datetime
import shutil

# Paths
OLD_DB_PATH = os.path.expanduser("~/Library/Application Support/VibrantFrogMCP/photo_index")
OLD_CACHE_PATH = Path(OLD_DB_PATH).parent / "indexed_photos.json"

ICLOUD_PATH = Path.home() / "Library/Mobile Documents/iCloud~com~vibrantfrog~AuthorAICollab/PhotoSearch"
NEW_DB_PATH = ICLOUD_PATH / "photo_index.db"
NEW_CACHE_PATH = ICLOUD_PATH / "indexed_photos.json"

def wait_for_icloud(timeout=30):
    """Wait for iCloud Drive to become available"""
    import time
    start = time.time()

    print("Checking iCloud Drive availability...")
    icloud_root = ICLOUD_PATH.parent.parent

    while time.time() - start < timeout:
        if icloud_root.exists():
            print(f"✅ iCloud Drive found at: {icloud_root}")
            return True
        print("⏳ Waiting for iCloud Drive...")
        time.sleep(2)

    return False

def create_sqlite_schema(conn):
    """Create SQLite schema for shared photo index"""
    cursor = conn.cursor()

    # Main index table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS photo_index (
            uuid TEXT PRIMARY KEY,
            description TEXT NOT NULL,
            embedding BLOB NOT NULL,

            -- Metadata from Apple Photos
            filename TEXT,
            date_taken TIMESTAMP,
            location TEXT,
            albums TEXT,
            keywords TEXT,
            favorite INTEGER,
            width INTEGER,
            height INTEGER,
            orientation TEXT,
            cloud_asset INTEGER,
            has_adjustments INTEGER,

            -- Indexing metadata
            indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            indexed_by TEXT DEFAULT 'vibrantfrogmcp',
            description_source TEXT DEFAULT 'llava',
            index_version TEXT DEFAULT '1.0'
        )
    """)

    # Indexes for fast querying
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_date_taken ON photo_index(date_taken DESC)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_favorite ON photo_index(favorite)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_indexed_at ON photo_index(indexed_at DESC)")

    # Metadata table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS index_metadata (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)

    # Initialize metadata
    cursor.execute("INSERT OR REPLACE INTO index_metadata VALUES ('version', '1.0')")
    cursor.execute("INSERT OR REPLACE INTO index_metadata VALUES ('embedding_model', 'all-MiniLM-L6-v2')")
    cursor.execute("INSERT OR REPLACE INTO index_metadata VALUES ('embedding_dimensions', '384')")
    cursor.execute(f"INSERT OR REPLACE INTO index_metadata VALUES ('created_at', '{datetime.now().isoformat()}')")
    cursor.execute(f"INSERT OR REPLACE INTO index_metadata VALUES ('last_updated', '{datetime.now().isoformat()}')")

    conn.commit()
    print("✅ Created SQLite schema")

def migrate_chromadb_to_sqlite():
    """Migrate ChromaDB data to SQLite in iCloud"""

    print("=" * 60)
    print("VibrantFrogMCP → iCloud Migration")
    print("=" * 60)
    print()

    # Step 1: Check iCloud availability
    if not wait_for_icloud():
        print("❌ iCloud Drive not available. Please enable iCloud Drive and try again.")
        return False

    # Step 2: Create iCloud directory
    ICLOUD_PATH.mkdir(parents=True, exist_ok=True)
    print(f"✅ Created iCloud directory: {ICLOUD_PATH}")

    # Step 3: Connect to existing ChromaDB
    print(f"\n📂 Loading existing ChromaDB from: {OLD_DB_PATH}")
    if not Path(OLD_DB_PATH).exists():
        print(f"❌ ChromaDB not found at {OLD_DB_PATH}")
        print("   Have you indexed any photos yet?")
        return False

    try:
        chroma_client = chromadb.PersistentClient(path=OLD_DB_PATH)
        collection = chroma_client.get_collection(name="photos")
        print(f"✅ Loaded ChromaDB collection: 'photos'")
    except Exception as e:
        print(f"❌ Failed to load ChromaDB: {e}")
        return False

    # Step 4: Get all data from ChromaDB
    print("\n📊 Fetching all indexed photos from ChromaDB...")
    results = collection.get(
        include=['documents', 'metadatas', 'embeddings']
    )

    total_photos = len(results['ids'])
    print(f"✅ Found {total_photos} indexed photos")

    if total_photos == 0:
        print("⚠️  No photos to migrate. Index some photos first!")
        return False

    # Step 5: Create new SQLite database
    print(f"\n📝 Creating SQLite database at: {NEW_DB_PATH}")
    conn = sqlite3.connect(str(NEW_DB_PATH))

    # Enable WAL mode for better concurrent access
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")

    create_sqlite_schema(conn)

    # Step 6: Migrate data
    print(f"\n🔄 Migrating {total_photos} photos to SQLite...")
    cursor = conn.cursor()

    migrated_count = 0
    failed_count = 0

    for i, photo_id in enumerate(results['ids']):
        try:
            # Get data
            document = results['documents'][i]
            metadata = results['metadatas'][i]
            embedding = results['embeddings'][i]

            # Serialize embedding as JSON (for Swift compatibility)
            # Alternative: use pickle, but JSON is more portable
            embedding_json = json.dumps(embedding).encode('utf-8')

            # Extract metadata fields (with defaults for missing fields)
            cursor.execute("""
                INSERT OR REPLACE INTO photo_index (
                    uuid, description, embedding,
                    filename, date_taken, location, albums, keywords,
                    favorite, width, height, orientation,
                    cloud_asset, has_adjustments,
                    indexed_by, description_source
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                photo_id,
                metadata.get('description', document),  # Full description
                embedding_json,
                metadata.get('filename'),
                metadata.get('date'),
                metadata.get('location'),
                metadata.get('albums'),  # Already JSON string
                metadata.get('keywords'),  # Already JSON string
                metadata.get('favorite', 0),
                metadata.get('width'),
                metadata.get('height'),
                metadata.get('orientation', 'square'),
                metadata.get('cloud_asset', 0),
                metadata.get('has_adjustments', 0),
                'vibrantfrogmcp',
                'llava'
            ))

            migrated_count += 1

            # Progress update
            if (i + 1) % 100 == 0 or (i + 1) == total_photos:
                percent = (i + 1) / total_photos * 100
                print(f"  Progress: {i + 1}/{total_photos} ({percent:.1f}%)")

        except Exception as e:
            print(f"❌ Failed to migrate photo {photo_id}: {e}")
            failed_count += 1

    # Update metadata
    cursor.execute("""
        UPDATE index_metadata
        SET value = ?
        WHERE key = 'last_updated'
    """, (datetime.now().isoformat(),))

    cursor.execute("""
        INSERT OR REPLACE INTO index_metadata
        VALUES ('total_photos', ?)
    """, (str(migrated_count),))

    conn.commit()
    conn.close()

    print(f"\n✅ Migration complete!")
    print(f"   Migrated: {migrated_count} photos")
    if failed_count > 0:
        print(f"   Failed: {failed_count} photos")

    # Step 7: Copy indexed cache
    if OLD_CACHE_PATH.exists():
        print(f"\n📋 Copying indexed cache...")
        shutil.copy(OLD_CACHE_PATH, NEW_CACHE_PATH)
        print(f"✅ Cache copied to: {NEW_CACHE_PATH}")

    # Step 8: Show database info
    db_size = NEW_DB_PATH.stat().st_size / 1024 / 1024
    print(f"\n📊 Database Statistics:")
    print(f"   Location: {NEW_DB_PATH}")
    print(f"   Size: {db_size:.1f} MB")
    print(f"   Photos: {migrated_count}")
    print(f"   Format: SQLite with JSON embeddings")

    # Step 9: Verify migration
    print(f"\n🔍 Verifying migration...")
    conn = sqlite3.connect(str(NEW_DB_PATH))
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM photo_index")
    count = cursor.fetchone()[0]
    conn.close()

    if count == migrated_count:
        print(f"✅ Verification passed: {count} photos in database")
    else:
        print(f"⚠️  Count mismatch: Expected {migrated_count}, found {count}")

    print(f"\n" + "=" * 60)
    print("Migration Complete! 🎉")
    print("=" * 60)
    print(f"\n📱 Next Steps:")
    print(f"1. Wait ~30 seconds for iCloud to sync the database")
    print(f"2. Open VibrantFrog Collab on iOS/Mac")
    print(f"3. Go to Settings → Photo Search")
    print(f"4. The app should detect your {migrated_count} indexed photos")
    print(f"5. Start searching!")
    print(f"\n💡 Future Indexing:")
    print(f"   From now on, new photos will be indexed directly to iCloud")
    print(f"   Run: python index_photos.py --icloud")

    return True

def check_migration_status():
    """Check if migration has already been done"""
    if NEW_DB_PATH.exists():
        conn = sqlite3.connect(str(NEW_DB_PATH))
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM photo_index")
        count = cursor.fetchone()[0]

        cursor.execute("SELECT value FROM index_metadata WHERE key = 'last_updated'")
        last_updated = cursor.fetchone()[0]

        conn.close()

        print(f"\n📊 Existing iCloud Database Found:")
        print(f"   Photos: {count}")
        print(f"   Last Updated: {last_updated}")
        print(f"   Location: {NEW_DB_PATH}")

        response = input("\n⚠️  Database already exists. Migrate again? (y/N): ")
        return response.lower() == 'y'

    return True

if __name__ == "__main__":
    import sys

    if '--help' in sys.argv or '-h' in sys.argv:
        print("""
VibrantFrogMCP to iCloud Migration Tool
========================================

This script migrates your existing ChromaDB photo index to a shared
SQLite database in iCloud Drive, making it accessible to VibrantFrog
Collab on iOS and Mac.

Usage:
    python migrate_to_icloud.py

What it does:
    1. Reads existing ChromaDB (~/Library/Application Support/VibrantFrogMCP)
    2. Creates SQLite database in iCloud Drive
    3. Migrates all indexed photos (UUIDs, descriptions, embeddings, metadata)
    4. Copies indexed photos cache
    5. Sets up for future incremental indexing

After migration:
    - VibrantFrog Collab can search your photos
    - New photos can be indexed directly to iCloud
    - No need to migrate again (incremental updates)

Requirements:
    - iCloud Drive enabled
    - Existing ChromaDB with indexed photos
    - ~10 MB free space in iCloud

Notes:
    - Your original ChromaDB is NOT deleted (safe to keep as backup)
    - Migration is non-destructive
    - Can be re-run if needed (updates existing records)
        """)
        sys.exit(0)

    # Check if already migrated
    if not check_migration_status():
        print("Migration cancelled.")
        sys.exit(0)

    # Run migration
    try:
        success = migrate_chromadb_to_sqlite()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n❌ Migration cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Migration failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
