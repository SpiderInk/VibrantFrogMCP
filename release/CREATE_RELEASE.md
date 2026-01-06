# Creating GitHub Release v1.1.0

## Option 1: Using GitHub CLI (Recommended)

If you have `gh` CLI authenticated:

```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# Create the release
gh release create v1.1.0 \
  release/VibrantFrog-v1.1.0.dmg \
  release/VibrantFrog-v1.1.0.zip \
  --title "v1.1.0 - CloudKit Cross-Device Photo Search" \
  --notes-file release/RELEASE_NOTES_v1.1.0.md \
  --latest
```

### Fix GitHub CLI Authentication

If you need to re-authenticate:

```bash
gh auth login -h github.com
```

Follow the prompts to authenticate with your GitHub account.

## Option 2: Using GitHub Web Interface

1. **Go to releases page:**
   ```
   https://github.com/SpiderInk/VibrantFrogMCP/releases/new
   ```

2. **Fill in the form:**
   - **Tag:** Select `v1.1.0` (already created and pushed)
   - **Release title:** `v1.1.0 - CloudKit Cross-Device Photo Search`
   - **Description:** Copy contents from `release/RELEASE_NOTES_v1.1.0.md`

3. **Upload binaries:**
   - Drag and drop `release/VibrantFrog-v1.1.0.dmg` (7.3 MB)
   - Drag and drop `release/VibrantFrog-v1.1.0.zip` (12 MB)

4. **Add checksums to description:**
   ```
   ## Checksums

   \`\`\`
   SHA256 (VibrantFrog-v1.1.0.dmg) = ba8c216a41a1353d7a3fd23d4d3d2929d24f7066abb72ff7ab6c0685552361d4
   SHA256 (VibrantFrog-v1.1.0.zip) = 272c42a961c2c5e1d469eea55c6bac1287053d0c73cbc29f604b1cabe2642ce3
   \`\`\`
   ```

5. **Mark as latest release:** ✅ Check "Set as the latest release"

6. **Publish:** Click "Publish release"

## Verification

After creating the release, verify:

```bash
# Check release exists
gh release view v1.1.0

# Or visit
https://github.com/SpiderInk/VibrantFrogMCP/releases/tag/v1.1.0
```

## Release Artifacts

The following files are ready in `release/` directory:

```
release/
├── VibrantFrog-v1.1.0.dmg (7.3 MB)
├── VibrantFrog-v1.1.0.zip (12 MB)
├── RELEASE_NOTES_v1.1.0.md
└── RELEASE_NOTES.md (v1.0.0 - keep for reference)
```

**IMPORTANT:** These binaries are in .gitignore and will NOT be committed to git. They're only for the GitHub Release.
