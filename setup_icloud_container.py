#!/usr/bin/env python3
"""
Setup iCloud container for VibrantFrog photo index

This script creates the iCloud container directory if it doesn't exist.
Run this before migrate_to_icloud.py if you get permission errors.
"""

import os
from pathlib import Path
import subprocess
import sys

# iCloud container path
ICLOUD_CONTAINER = "iCloud~com~vibrantfrog~AuthorAICollab"
MOBILE_DOCS = Path.home() / "Library" / "Mobile Documents"
CONTAINER_PATH = MOBILE_DOCS / ICLOUD_CONTAINER
PHOTO_SEARCH_PATH = CONTAINER_PATH / "PhotoSearch"

def check_icloud_status():
    """Check if iCloud Drive is enabled"""
    try:
        # Check if Mobile Documents exists
        if not MOBILE_DOCS.exists():
            print("❌ iCloud Drive not found")
            print("\nPlease enable iCloud Drive:")
            print("1. Open System Settings")
            print("2. Click on your Apple ID")
            print("3. Click iCloud")
            print("4. Enable 'iCloud Drive'")
            return False

        print(f"✅ iCloud Drive found at: {MOBILE_DOCS}")
        return True

    except Exception as e:
        print(f"❌ Error checking iCloud: {e}")
        return False

def create_container_via_defaults():
    """Create container using macOS defaults/CloudKit"""
    print(f"\n📁 Creating iCloud container: {ICLOUD_CONTAINER}")

    try:
        # Method 1: Create directory with proper permissions
        # We need to create it in a way that iCloud recognizes it

        # First, check if any VibrantFrog container exists
        vibrant_containers = list(MOBILE_DOCS.glob("*vibrant*"))

        if vibrant_containers:
            print(f"\n✅ Found existing VibrantFrog container:")
            for container in vibrant_containers:
                print(f"   {container.name}")

            # Use the first one
            existing_container = vibrant_containers[0]
            photo_search = existing_container / "PhotoSearch"
            photo_search.mkdir(parents=True, exist_ok=True)

            print(f"\n✅ Created PhotoSearch folder in existing container")
            print(f"   Path: {photo_search}")
            return str(photo_search)

        # No existing container - need to create it
        # This is tricky - iCloud containers are usually created by the app
        print("\n⚠️  No existing VibrantFrog iCloud container found")
        print("\nOptions:")
        print("1. Run VibrantFrog Collab app once (creates container automatically)")
        print("2. Use local folder temporarily (for testing)")
        print("3. Manually create container (advanced)")

        choice = input("\nChoose option (1/2/3): ").strip()

        if choice == "1":
            print("\n📱 Please:")
            print("1. Open VibrantFrog Collab app on Mac or iOS")
            print("2. Wait a few seconds for iCloud container to initialize")
            print("3. Close the app")
            print("4. Run this script again")
            return None

        elif choice == "2":
            # Create local folder for testing
            local_path = Path.home() / "VibrantFrogPhotoIndex"
            local_path.mkdir(parents=True, exist_ok=True)
            print(f"\n✅ Created local folder: {local_path}")
            print("\n⚠️  This is a LOCAL folder (not synced via iCloud)")
            print("   Good for testing, but won't sync to iOS")
            return str(local_path)

        elif choice == "3":
            # Advanced: try to create it manually
            print("\n🔧 Attempting manual container creation...")
            try:
                CONTAINER_PATH.mkdir(parents=True, exist_ok=True)
                PHOTO_SEARCH_PATH.mkdir(parents=True, exist_ok=True)

                # Set extended attributes to mark as iCloud
                subprocess.run([
                    'xattr', '-w',
                    'com.apple.clouddocs.private.shared-database-allowed',
                    '1',
                    str(CONTAINER_PATH)
                ], check=False)

                print(f"✅ Created container: {CONTAINER_PATH}")
                print(f"✅ Created PhotoSearch: {PHOTO_SEARCH_PATH}")
                print("\n⚠️  If this doesn't sync, use option 1 instead")
                return str(PHOTO_SEARCH_PATH)

            except PermissionError as e:
                print(f"\n❌ Permission denied: {e}")
                print("Please use option 1 (run VibrantFrog Collab app)")
                return None

        else:
            print("Invalid choice")
            return None

    except Exception as e:
        print(f"❌ Error creating container: {e}")
        import traceback
        traceback.print_exc()
        return None

def verify_container():
    """Verify the container is accessible"""
    if PHOTO_SEARCH_PATH.exists():
        print(f"\n✅ PhotoSearch folder exists: {PHOTO_SEARCH_PATH}")

        # Try to write a test file
        test_file = PHOTO_SEARCH_PATH / ".test"
        try:
            test_file.write_text("test")
            test_file.unlink()
            print("✅ Write permissions confirmed")
            return True
        except Exception as e:
            print(f"❌ Cannot write to folder: {e}")
            return False
    else:
        print(f"\n❌ PhotoSearch folder not found: {PHOTO_SEARCH_PATH}")
        return False

def main():
    print("="*60)
    print("VibrantFrog iCloud Container Setup")
    print("="*60)

    # Check iCloud status
    if not check_icloud_status():
        sys.exit(1)

    # Check if container already exists
    if PHOTO_SEARCH_PATH.exists():
        print(f"\n✅ Container already exists: {PHOTO_SEARCH_PATH}")
        if verify_container():
            print("\n🎉 Setup complete! You can now run migrate_to_icloud.py")
            sys.exit(0)

    # Create container
    result = create_container_via_defaults()

    if result:
        print(f"\n✅ Setup complete!")
        print(f"   PhotoSearch path: {result}")
        print("\nNext step:")
        print("   python migrate_to_icloud.py")
    else:
        print("\n❌ Setup incomplete")
        print("\nPlease run VibrantFrog Collab app first to create the iCloud container")

if __name__ == "__main__":
    main()
