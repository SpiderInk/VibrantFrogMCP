#!/usr/bin/env python3
"""
Album Manager for Apple Photos

Provides functions to create, delete, and manage albums in Apple Photos
via AppleScript. These functions can be used by MCP tools to let Claude
create albums from search results.
"""

import subprocess
import logging
from typing import Optional

logger = logging.getLogger(__name__)


def create_album(album_name: str) -> dict:
    """
    Create a new album in Apple Photos

    Args:
        album_name: Name for the new album

    Returns:
        dict with 'success' (bool), 'status' ('created' or 'exists'), 'message' (str)
    """
    try:
        script = f'''
        tell application "Photos"
            if not (exists album "{album_name}") then
                make new album named "{album_name}"
                return "created"
            else
                return "exists"
            end if
        end tell
        '''
        result = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True, text=True, check=True, timeout=30
        )
        status = result.stdout.strip()

        if status == "created":
            logger.info(f"Created album: {album_name}")
            return {"success": True, "status": "created", "message": f"Album '{album_name}' created successfully"}
        else:
            logger.info(f"Album already exists: {album_name}")
            return {"success": True, "status": "exists", "message": f"Album '{album_name}' already exists"}

    except subprocess.TimeoutExpired:
        logger.error(f"Timeout creating album: {album_name}")
        return {"success": False, "status": "error", "message": "Operation timed out - Photos app may be unresponsive"}
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to create album: {e.stderr}")
        return {"success": False, "status": "error", "message": f"Failed to create album: {e.stderr}"}


def delete_album(album_name: str) -> dict:
    """
    Delete an album from Apple Photos (does not delete the photos themselves)

    Args:
        album_name: Name of the album to delete

    Returns:
        dict with 'success' (bool), 'status' (str), 'message' (str)
    """
    try:
        script = f'''
        tell application "Photos"
            if (exists album "{album_name}") then
                delete album "{album_name}"
                return "deleted"
            else
                return "not_found"
            end if
        end tell
        '''
        result = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True, text=True, check=True, timeout=30
        )
        status = result.stdout.strip()

        if status == "deleted":
            logger.info(f"Deleted album: {album_name}")
            return {"success": True, "status": "deleted", "message": f"Album '{album_name}' deleted successfully"}
        else:
            logger.info(f"Album not found: {album_name}")
            return {"success": False, "status": "not_found", "message": f"Album '{album_name}' not found"}

    except subprocess.TimeoutExpired:
        logger.error(f"Timeout deleting album: {album_name}")
        return {"success": False, "status": "error", "message": "Operation timed out - Photos app may be unresponsive"}
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to delete album: {e.stderr}")
        return {"success": False, "status": "error", "message": f"Failed to delete album: {e.stderr}"}


def list_albums() -> dict:
    """
    List all albums in Apple Photos

    Returns:
        dict with 'success' (bool), 'albums' (list of album names), 'count' (int)
    """
    try:
        script = '''
        tell application "Photos"
            set albumNames to {}
            repeat with a in albums
                set end of albumNames to name of a
            end repeat
            return albumNames
        end tell
        '''
        result = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True, text=True, check=True, timeout=60
        )

        # Parse AppleScript list output (comma-separated)
        output = result.stdout.strip()
        if output:
            albums = [name.strip() for name in output.split(', ')]
        else:
            albums = []

        logger.info(f"Found {len(albums)} albums")
        return {"success": True, "albums": albums, "count": len(albums)}

    except subprocess.TimeoutExpired:
        logger.error("Timeout listing albums")
        return {"success": False, "albums": [], "count": 0, "message": "Operation timed out"}
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to list albums: {e.stderr}")
        return {"success": False, "albums": [], "count": 0, "message": f"Failed to list albums: {e.stderr}"}


def get_album_photo_count(album_name: str) -> dict:
    """
    Get the number of photos in an album

    Args:
        album_name: Name of the album

    Returns:
        dict with 'success' (bool), 'count' (int), 'message' (str)
    """
    try:
        script = f'''
        tell application "Photos"
            if (exists album "{album_name}") then
                return count of media items of album "{album_name}"
            else
                return -1
            end if
        end tell
        '''
        result = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True, text=True, check=True, timeout=30
        )
        count = int(result.stdout.strip())

        if count == -1:
            return {"success": False, "count": 0, "message": f"Album '{album_name}' not found"}
        else:
            return {"success": True, "count": count, "message": f"Album '{album_name}' has {count} photos"}

    except subprocess.TimeoutExpired:
        return {"success": False, "count": 0, "message": "Operation timed out"}
    except subprocess.CalledProcessError as e:
        return {"success": False, "count": 0, "message": f"Failed to get photo count: {e.stderr}"}


def add_photos_to_album(album_name: str, photo_uuids: list[str]) -> dict:
    """
    Add photos to an album by their UUIDs

    Args:
        album_name: Name of the album (must already exist)
        photo_uuids: List of photo UUIDs to add

    Returns:
        dict with 'success' (bool), 'added_count' (int), 'message' (str)
    """
    if not photo_uuids:
        return {"success": True, "added_count": 0, "message": "No photos to add"}

    try:
        # AppleScript has limits on string length, so batch if needed
        batch_size = 50
        total_added = 0
        failed_uuids = []

        for i in range(0, len(photo_uuids), batch_size):
            batch = photo_uuids[i:i+batch_size]
            id_list = ', '.join([f'"{pid}"' for pid in batch])

            script = f'''
            tell application "Photos"
                set theAlbum to album "{album_name}"
                set addedCount to 0
                set failedIds to {{}}
                repeat with photoId in {{{id_list}}}
                    try
                        set thePhoto to media item id photoId
                        add {{thePhoto}} to theAlbum
                        set addedCount to addedCount + 1
                    on error
                        set end of failedIds to photoId
                    end try
                end repeat
                return addedCount
            end tell
            '''
            result = subprocess.run(
                ['osascript', '-e', script],
                capture_output=True, text=True, check=True, timeout=120
            )
            batch_added = int(result.stdout.strip())
            total_added += batch_added

            # Track failed UUIDs
            if batch_added < len(batch):
                failed_uuids.extend(batch[batch_added:])

        message = f"Added {total_added} of {len(photo_uuids)} photos to album '{album_name}'"
        if failed_uuids:
            message += f" ({len(failed_uuids)} photos not found)"

        logger.info(message)
        return {
            "success": True,
            "added_count": total_added,
            "requested_count": len(photo_uuids),
            "message": message
        }

    except subprocess.TimeoutExpired:
        logger.error(f"Timeout adding photos to album: {album_name}")
        return {"success": False, "added_count": 0, "message": "Operation timed out - try adding fewer photos"}
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to add photos: {e.stderr}")
        return {"success": False, "added_count": 0, "message": f"Failed to add photos: {e.stderr}"}


def remove_photos_from_album(album_name: str, photo_uuids: list[str]) -> dict:
    """
    Remove photos from an album by their UUIDs (does not delete the photos)

    Args:
        album_name: Name of the album
        photo_uuids: List of photo UUIDs to remove

    Returns:
        dict with 'success' (bool), 'removed_count' (int), 'message' (str)
    """
    if not photo_uuids:
        return {"success": True, "removed_count": 0, "message": "No photos to remove"}

    try:
        batch_size = 50
        total_removed = 0

        for i in range(0, len(photo_uuids), batch_size):
            batch = photo_uuids[i:i+batch_size]
            id_list = ', '.join([f'"{pid}"' for pid in batch])

            # Note: AppleScript 'remove' from album only removes from album, not library
            script = f'''
            tell application "Photos"
                set theAlbum to album "{album_name}"
                set removedCount to 0
                repeat with photoId in {{{id_list}}}
                    try
                        set thePhoto to media item id photoId
                        remove {{thePhoto}} from theAlbum
                        set removedCount to removedCount + 1
                    end try
                end repeat
                return removedCount
            end tell
            '''
            result = subprocess.run(
                ['osascript', '-e', script],
                capture_output=True, text=True, check=True, timeout=120
            )
            total_removed += int(result.stdout.strip())

        message = f"Removed {total_removed} of {len(photo_uuids)} photos from album '{album_name}'"
        logger.info(message)
        return {
            "success": True,
            "removed_count": total_removed,
            "requested_count": len(photo_uuids),
            "message": message
        }

    except subprocess.TimeoutExpired:
        logger.error(f"Timeout removing photos from album: {album_name}")
        return {"success": False, "removed_count": 0, "message": "Operation timed out"}
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to remove photos: {e.stderr}")
        return {"success": False, "removed_count": 0, "message": f"Failed to remove photos: {e.stderr}"}


def create_album_from_search(album_name: str, search_query: str, limit: int = 100) -> dict:
    """
    Search ChromaDB for photos and create an album with the results

    Args:
        album_name: Name for the new album
        search_query: Natural language search query
        limit: Maximum number of photos to add (default 100)

    Returns:
        dict with 'success' (bool), 'album_name' (str), 'added_count' (int), 'message' (str)
    """
    # Import here to avoid circular imports
    from photo_retrieval import search_photos_by_description

    # Search for matching photos
    logger.info(f"Searching for: '{search_query}' (limit: {limit})")
    results = search_photos_by_description(search_query, limit=limit)

    if not results:
        return {
            "success": False,
            "album_name": album_name,
            "added_count": 0,
            "message": f"No photos found matching '{search_query}'"
        }

    # Extract UUIDs from search results
    uuids = []
    for r in results:
        if isinstance(r, dict) and 'uuid' in r:
            uuids.append(r['uuid'])
        elif isinstance(r, dict) and 'metadata' in r and 'uuid' in r['metadata']:
            uuids.append(r['metadata']['uuid'])

    if not uuids:
        return {
            "success": False,
            "album_name": album_name,
            "added_count": 0,
            "message": "Search returned results but no valid UUIDs found"
        }

    logger.info(f"Found {len(uuids)} matching photos")

    # Create album
    create_result = create_album(album_name)
    if not create_result["success"] and create_result["status"] != "exists":
        return {
            "success": False,
            "album_name": album_name,
            "added_count": 0,
            "message": f"Failed to create album: {create_result['message']}"
        }

    # Add photos to album
    add_result = add_photos_to_album(album_name, uuids)

    return {
        "success": add_result["success"],
        "album_name": album_name,
        "search_query": search_query,
        "photos_found": len(uuids),
        "added_count": add_result.get("added_count", 0),
        "message": f"Created album '{album_name}' with {add_result.get('added_count', 0)} photos from search '{search_query}'"
    }


# Test functions
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    print("\n=== Album Manager Test ===\n")

    # List existing albums
    print("1. Listing albums...")
    result = list_albums()
    print(f"   Found {result['count']} albums")
    if result['albums'][:5]:
        print(f"   First 5: {result['albums'][:5]}")

    # Test create
    test_album = "VibrantFrog Test Album"
    print(f"\n2. Creating test album: '{test_album}'...")
    result = create_album(test_album)
    print(f"   {result['message']}")

    # Get photo count
    print(f"\n3. Getting photo count...")
    result = get_album_photo_count(test_album)
    print(f"   {result['message']}")

    # Delete test album
    print(f"\n4. Deleting test album...")
    result = delete_album(test_album)
    print(f"   {result['message']}")

    print("\n=== Test Complete ===\n")
