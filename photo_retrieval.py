#!/usr/bin/env python3
"""
Helper functions for retrieving photos from Apple Photos Library by UUID
"""
import os
import tempfile
import osxphotos
from pathlib import Path
import logging

logger = logging.getLogger(__name__)


def get_photo_by_uuid(uuid: str):
    """
    Retrieve a photo object from Apple Photos Library by UUID

    Args:
        uuid: The photo UUID from metadata

    Returns:
        PhotoInfo object or None if not found
    """
    photosdb = osxphotos.PhotosDB()
    photos = photosdb.photos(uuid=[uuid])

    if not photos:
        logger.warning(f"Photo with UUID {uuid} not found in library")
        return None

    return photos[0]


def get_photo_path_for_display(uuid: str, export_if_needed=True):
    """
    Get an accessible file path for a photo by UUID.
    If the photo is in iCloud and not downloaded, optionally export it.

    Args:
        uuid: The photo UUID from metadata
        export_if_needed: If True, export iCloud photos to temp directory

    Returns:
        tuple: (path, needs_cleanup)
            - path: Accessible file path or None
            - needs_cleanup: True if path is a temp file that should be deleted after use
    """
    photo = get_photo_by_uuid(uuid)
    if not photo:
        return None, False

    # Try direct path first (fastest if available)
    if photo.path and os.path.exists(photo.path):
        logger.debug(f"Using direct path for {uuid}")
        return photo.path, False

    # Try edited version
    if photo.path_edited and os.path.exists(photo.path_edited):
        logger.debug(f"Using edited version for {uuid}")
        return photo.path_edited, False

    # Try derivatives
    if photo.path_derivatives:
        for deriv_path in photo.path_derivatives:
            if os.path.exists(deriv_path):
                logger.debug(f"Using derivative path for {uuid}")
                return deriv_path, False

    # Export from iCloud if requested
    if export_if_needed and photo.iscloudasset:
        try:
            logger.info(f"Exporting iCloud photo {uuid} to temp directory...")
            temp_dir = tempfile.mkdtemp()
            exported = photo.export(temp_dir, timeout=30)
            if exported:
                logger.info(f"Photo exported successfully to {exported[0]}")
                return exported[0], True  # (path, needs_cleanup)
        except Exception as e:
            logger.error(f"Failed to export photo {uuid}: {e}")
            return None, False

    logger.warning(f"No accessible path found for photo {uuid}")
    return None, False


def cleanup_temp_photo(photo_path: str):
    """
    Clean up a temporary photo export

    Args:
        photo_path: Path to temporary photo file
    """
    try:
        if os.path.exists(photo_path):
            os.remove(photo_path)
            # Try to remove parent directory if empty
            parent_dir = os.path.dirname(photo_path)
            if os.path.exists(parent_dir) and not os.listdir(parent_dir):
                os.rmdir(parent_dir)
            logger.debug(f"Cleaned up temp file: {photo_path}")
    except Exception as e:
        logger.warning(f"Failed to cleanup temp file {photo_path}: {e}")


# Example usage
if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python photo_retrieval.py <UUID>")
        sys.exit(1)

    uuid = sys.argv[1]
    print(f"Looking up photo with UUID: {uuid}")

    photo = get_photo_by_uuid(uuid)
    if photo:
        print(f"Found: {photo.original_filename}")
        print(f"Date: {photo.date}")
        print(f"iCloud: {photo.iscloudasset}")

        path, needs_cleanup = get_photo_path_for_display(uuid)
        if path:
            print(f"Path: {path}")
            print(f"Needs cleanup: {needs_cleanup}")

            if needs_cleanup:
                cleanup_temp_photo(path)
                print("Cleaned up temporary export")
    else:
        print("Photo not found in library")
