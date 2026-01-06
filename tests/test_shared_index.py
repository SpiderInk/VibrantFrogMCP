#!/usr/bin/env python3
"""
Unit tests for shared_index.py

Tests the core SQLite photo index functionality.
"""

import pytest
import json
import tempfile
import shutil
from pathlib import Path
from datetime import datetime

# Import the module we're testing
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from shared_index import SharedPhotoIndex


class TestSharedPhotoIndex:
    """Test suite for SharedPhotoIndex class"""

    @pytest.fixture
    def temp_index(self):
        """Create a temporary photo index for testing"""
        # Create temporary directory
        temp_dir = tempfile.mkdtemp()

        # Temporarily override the SHARED_INDEX_PATH
        import shared_index
        original_path = shared_index.SHARED_INDEX_PATH
        original_db_path = shared_index.DB_PATH

        shared_index.SHARED_INDEX_PATH = Path(temp_dir)
        shared_index.DB_PATH = Path(temp_dir) / "photo_index.db"

        # Create index
        index = SharedPhotoIndex()

        yield index

        # Cleanup
        shared_index.SHARED_INDEX_PATH = original_path
        shared_index.DB_PATH = original_db_path
        shutil.rmtree(temp_dir)

    def test_database_creation(self, temp_index):
        """Test that database and table are created correctly"""
        # Database should be initialized
        assert temp_index.db_path.exists()

        # Table should exist
        conn = temp_index._get_connection()
        cursor = conn.cursor()
        cursor.execute("""
            SELECT name FROM sqlite_master
            WHERE type='table' AND name='photo_index'
        """)
        assert cursor.fetchone() is not None
        conn.close()

    def test_embedding_serialization(self, temp_index):
        """Test JSON serialization of embedding vectors"""
        # Create a sample embedding (384-dim simplified to 10)
        embedding = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

        # Serialize to JSON
        embedding_json = json.dumps(embedding)

        # Deserialize
        deserialized = json.loads(embedding_json)

        # Should match original
        assert deserialized == embedding
        assert len(deserialized) == 10
        assert isinstance(deserialized, list)

    def test_get_stats_empty_database(self, temp_index):
        """Test stats on empty database"""
        stats = temp_index.get_stats()

        assert stats['total_photos'] == 0
        assert stats['database_size'] == 0
        assert 'database_path' in stats

    def test_database_wal_mode_enabled(self, temp_index):
        """Test that WAL mode is enabled for concurrent access"""
        conn = temp_index._get_connection()
        cursor = conn.cursor()

        # Check journal mode
        cursor.execute("PRAGMA journal_mode")
        journal_mode = cursor.fetchone()[0]

        assert journal_mode.upper() == 'WAL'
        conn.close()

    def test_schema_has_required_columns(self, temp_index):
        """Test that schema has all required columns"""
        conn = temp_index._get_connection()
        cursor = conn.cursor()

        # Get table info
        cursor.execute("PRAGMA table_info(photo_index)")
        columns = {row[1] for row in cursor.fetchall()}

        # Required columns
        required = {
            'uuid', 'cloud_guid', 'description', 'embedding',
            'filename', 'date_taken', 'indexed_at'
        }

        assert required.issubset(columns)
        conn.close()


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
