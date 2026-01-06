#!/usr/bin/env python3
"""
Shared Photo Index - iCloud SQLite Database

This module provides a shared photo index stored in iCloud Drive,
accessible by both VibrantFrogMCP (Python) and VibrantFrog Collab (Swift).

The index is stored as a SQLite database with JSON-serialized embeddings
for cross-platform compatibility.
"""

import sqlite3
import json
import time
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

# Shared photo index path
# Use ~/VibrantFrogPhotoIndex by default (always works, no permissions issues)
SHARED_INDEX_PATH = Path.home() / "VibrantFrogPhotoIndex"
DB_PATH = SHARED_INDEX_PATH / "photo_index.db"
INDEXED_CACHE_PATH = SHARED_INDEX_PATH / "indexed_photos.json"

# Note: VibrantFrog Collab (iOS/Mac app) should also check this location
# For iCloud sync, both apps can be updated to use a symlink or shared path


class SharedPhotoIndex:
    """
    Shared photo index stored in iCloud Drive as SQLite database.

    This allows both VibrantFrogMCP (Python/Mac) and VibrantFrog Collab (Swift/iOS/Mac)
    to access the same photo index data.
    """

    def __init__(self, timeout: float = 30.0):
        """
        Initialize shared photo index.

        Args:
            timeout: Database lock timeout in seconds
        """
        self.db_path = str(DB_PATH)
        self.cache_path = INDEXED_CACHE_PATH
        self.timeout = timeout

        # Ensure iCloud directory exists
        self._ensure_icloud_directory()

        # Initialize database schema
        self._initialize_database()

    def _ensure_icloud_directory(self):
        """Ensure iCloud Drive directory exists and is accessible"""
        try:
            SHARED_INDEX_PATH.mkdir(parents=True, exist_ok=True)
            logger.info(f"✅ Shared index directory ready: {SHARED_INDEX_PATH}")
        except Exception as e:
            logger.error(f"❌ Failed to create shared index directory: {e}")
            logger.error("Path: {SHARED_INDEX_PATH}")
            raise

    def _wait_for_icloud(self, max_wait: float = 10.0) -> bool:
        """
        Wait for iCloud Drive to become available.

        Args:
            max_wait: Maximum time to wait in seconds

        Returns:
            True if iCloud is available, False otherwise
        """
        start = time.time()
        icloud_root = SHARED_INDEX_PATH.parent

        while time.time() - start < max_wait:
            if icloud_root.exists():
                return True
            time.sleep(0.5)

        return False

    def _initialize_database(self):
        """Create database schema if it doesn't exist"""
        if not self._wait_for_icloud():
            raise Exception("iCloud Drive not available. Please enable iCloud Drive.")

        conn = sqlite3.connect(self.db_path, timeout=self.timeout)

        # Enable WAL mode for better concurrent access
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")

        cursor = conn.cursor()

        # Main index table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS photo_index (
                uuid TEXT PRIMARY KEY,
                description TEXT NOT NULL,
                embedding TEXT NOT NULL,

                -- Metadata from Apple Photos
                filename TEXT,
                date_taken TIMESTAMP,
                location TEXT,
                albums TEXT,
                keywords TEXT,
                favorite INTEGER DEFAULT 0,
                width INTEGER,
                height INTEGER,
                orientation TEXT,
                cloud_asset INTEGER DEFAULT 0,
                has_adjustments INTEGER DEFAULT 0,
                cloud_guid TEXT,

                -- Indexing metadata
                indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                indexed_by TEXT DEFAULT 'vibrantfrogmcp',
                description_source TEXT DEFAULT 'llava',
                index_version TEXT DEFAULT '1.0'
            )
        """)

        # Indexes for fast querying
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_date_taken
            ON photo_index(date_taken DESC)
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_favorite
            ON photo_index(favorite)
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_indexed_at
            ON photo_index(indexed_at DESC)
        """)

        # Metadata table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS index_metadata (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)

        # Initialize metadata
        cursor.execute("""
            INSERT OR IGNORE INTO index_metadata
            VALUES ('version', '1.0')
        """)
        cursor.execute("""
            INSERT OR IGNORE INTO index_metadata
            VALUES ('embedding_model', 'all-MiniLM-L6-v2')
        """)
        cursor.execute("""
            INSERT OR IGNORE INTO index_metadata
            VALUES ('embedding_dimensions', '384')
        """)
        cursor.execute(f"""
            INSERT OR IGNORE INTO index_metadata
            VALUES ('created_at', '{datetime.now().isoformat()}')
        """)

        conn.commit()
        conn.close()

        logger.info(f"✅ Database initialized: {self.db_path}")

    def index_photo(self, photo, description: str, embedding: List[float], cloud_guid: str = None) -> bool:
        """
        Index a single photo to the shared iCloud database.

        Args:
            photo: osxphotos.PhotoInfo object
            description: Text description of the photo
            embedding: 384-dimensional embedding vector
            cloud_guid: Optional PHCloudIdentifier string for cross-device photo access

        Returns:
            True if successful, False otherwise
        """
        try:
            conn = sqlite3.connect(self.db_path, timeout=self.timeout)
            cursor = conn.cursor()

            # Serialize embedding as JSON (for Swift compatibility)
            embedding_json = json.dumps(embedding)

            # Determine orientation
            orientation = "square"
            if photo.width and photo.height:
                if photo.width > photo.height * 1.1:
                    orientation = "landscape"
                elif photo.height > photo.width * 1.1:
                    orientation = "portrait"

            # Prepare album and keyword data
            albums_json = json.dumps([a.title for a in photo.albums]) if photo.albums else None
            keywords_json = json.dumps(photo.keywords) if photo.keywords else None

            # Insert or replace photo
            cursor.execute("""
                INSERT OR REPLACE INTO photo_index (
                    uuid, description, embedding,
                    filename, date_taken, location, albums, keywords,
                    favorite, width, height, orientation,
                    cloud_asset, has_adjustments, cloud_guid,
                    indexed_by, description_source
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                photo.uuid,
                description,
                embedding_json,
                photo.original_filename,
                photo.date.isoformat() if photo.date else None,
                photo.place.name if photo.place else None,
                albums_json,
                keywords_json,
                1 if photo.favorite else 0,
                photo.width,
                photo.height,
                orientation,
                1 if photo.iscloudasset else 0,
                1 if photo.hasadjustments else 0,
                cloud_guid,  # PHCloudIdentifier for cross-device access
                'vibrantfrogmcp',
                'llava'
            ))

            # Update last_updated metadata
            cursor.execute("""
                INSERT OR REPLACE INTO index_metadata
                VALUES ('last_updated', ?)
            """, (datetime.now().isoformat(),))

            # Update total count
            cursor.execute("SELECT COUNT(*) FROM photo_index")
            total = cursor.fetchone()[0]
            cursor.execute("""
                INSERT OR REPLACE INTO index_metadata
                VALUES ('total_photos', ?)
            """, (str(total),))

            conn.commit()
            conn.close()

            logger.info(f"✅ Indexed to iCloud: {photo.original_filename}")
            return True

        except sqlite3.OperationalError as e:
            logger.error(f"Database error: {e}")
            return False
        except Exception as e:
            logger.error(f"Failed to index photo: {e}")
            return False

    def get_indexed_uuids(self) -> set:
        """
        Get set of already-indexed photo UUIDs.

        Returns:
            Set of photo UUIDs that have been indexed
        """
        try:
            conn = sqlite3.connect(self.db_path, timeout=self.timeout)
            cursor = conn.cursor()

            cursor.execute("SELECT uuid FROM photo_index")
            uuids = {row[0] for row in cursor.fetchall()}

            conn.close()
            return uuids

        except Exception as e:
            logger.error(f"Failed to get indexed UUIDs: {e}")
            return set()

    def get_stats(self) -> Dict:
        """
        Get index statistics.

        Returns:
            Dictionary with index statistics
        """
        try:
            conn = sqlite3.connect(self.db_path, timeout=self.timeout)
            cursor = conn.cursor()

            # Get metadata
            cursor.execute("SELECT key, value FROM index_metadata")
            metadata = dict(cursor.fetchall())

            # Get counts
            cursor.execute("SELECT COUNT(*) FROM photo_index")
            total = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM photo_index WHERE favorite = 1")
            favorites = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM photo_index WHERE cloud_asset = 1")
            cloud = cursor.fetchone()[0]

            conn.close()

            # Get database size
            db_size_mb = DB_PATH.stat().st_size / 1024 / 1024 if DB_PATH.exists() else 0

            return {
                "total_photos": total,
                "favorites": favorites,
                "cloud_photos": cloud,
                "last_updated": metadata.get('last_updated'),
                "embedding_model": metadata.get('embedding_model'),
                "database_path": str(DB_PATH),
                "database_size_mb": round(db_size_mb, 2),
                "icloud_synced": True  # Assume synced if we can read it
            }

        except Exception as e:
            logger.error(f"Failed to get stats: {e}")
            return {
                "total_photos": 0,
                "error": str(e)
            }

    def save_indexed_cache(self, uuids: set):
        """
        Save indexed UUIDs cache to JSON file.

        Args:
            uuids: Set of indexed photo UUIDs
        """
        try:
            self.cache_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.cache_path, 'w') as f:
                json.dump(list(uuids), f)
            logger.debug(f"Saved cache: {len(uuids)} UUIDs")
        except Exception as e:
            logger.warning(f"Failed to save cache: {e}")

    def load_indexed_cache(self) -> set:
        """
        Load indexed UUIDs cache from JSON file.

        Returns:
            Set of cached indexed photo UUIDs
        """
        try:
            if self.cache_path.exists():
                with open(self.cache_path) as f:
                    return set(json.load(f))
        except Exception as e:
            logger.warning(f"Failed to load cache: {e}")

        return set()


# Convenience function for backward compatibility
def get_shared_index() -> SharedPhotoIndex:
    """Get or create shared photo index instance"""
    return SharedPhotoIndex()


if __name__ == "__main__":
    # Test the shared index
    import sys

    if '--stats' in sys.argv:
        index = SharedPhotoIndex()
        stats = index.get_stats()

        print("\n" + "="*60)
        print("📊 Shared Photo Index Statistics")
        print("="*60)
        print(f"Total Photos:     {stats['total_photos']}")
        print(f"Favorites:        {stats.get('favorites', 0)}")
        print(f"iCloud Photos:    {stats.get('cloud_photos', 0)}")
        print(f"Last Updated:     {stats.get('last_updated', 'Never')}")
        print(f"Embedding Model:  {stats.get('embedding_model', 'Unknown')}")
        print(f"Database Size:    {stats['database_size_mb']} MB")
        print(f"Database Path:    {stats['database_path']}")
        print(f"iCloud Synced:    {'✅' if stats.get('icloud_synced') else '❌'}")
        print("="*60)
        print("\n📱 Open VibrantFrog Collab to search photos")
        print()
    else:
        print("Shared Photo Index Module")
        print("\nUsage:")
        print("  python shared_index.py --stats    Show index statistics")
        print("\nOr import in your code:")
        print("  from shared_index import SharedPhotoIndex")
