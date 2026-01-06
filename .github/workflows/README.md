# GitHub Actions Workflows

Automated CI/CD workflows for VibrantFrogMCP.

## Workflows

### `build-and-release.yml`

Automatically builds and releases the macOS app when you push a version tag.

**Trigger:** Push a git tag matching `v*.*.*` (e.g., `v1.1.0`)

**What it does:**
1. ✅ Builds VibrantFrog.app on macOS Sonoma runner
2. ✅ Creates DMG and ZIP release artifacts
3. ✅ Computes SHA256 checksums
4. ✅ Creates GitHub Release with binaries attached
5. ✅ Runs automated tests (if pytest is configured)

## How to Use

### Create a New Release

```bash
# 1. Make sure all changes are committed and pushed
git push origin main

# 2. Create and push a version tag
git tag -a v1.2.0 -m "Version 1.2.0: Description of changes"
git push origin v1.2.0

# 3. GitHub Actions automatically:
#    - Builds the app
#    - Creates release artifacts
#    - Publishes GitHub Release
```

### Monitor Build Progress

1. Go to: https://github.com/SpiderInk/VibrantFrogMCP/actions
2. Click on the latest "Build and Release" workflow
3. Watch the progress (takes ~5-10 minutes)

### Download Release Artifacts

After the workflow completes:
- Go to: https://github.com/SpiderInk/VibrantFrogMCP/releases
- Find your version (e.g., v1.2.0)
- Download DMG or ZIP from the release page

## Important Notes

### Code Signing

⚠️ **The app is NOT code-signed or notarized** because GitHub Actions doesn't have access to your Apple Developer certificates.

**Implications:**
- macOS Gatekeeper will show a warning on first launch
- Users must right-click → Open to bypass the warning
- For production releases with proper code signing, you need to:
  1. Get an Apple Developer account ($99/year)
  2. Add certificates to GitHub Secrets
  3. Uncomment code signing in the workflow

### macOS Runner Costs

GitHub provides:
- **Public repos:** FREE (unlimited minutes on macOS runners)
- **Private repos:** 10x multiplier (macOS minutes count as 10 minutes)

See: https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions

### Build Time

Typical workflow duration:
- **Build job:** 5-8 minutes
- **Release job:** 1-2 minutes
- **Tests job:** 1 minute (runs in parallel)
- **Total:** ~8-10 minutes

## Advanced: Code Signing Setup

To enable proper code signing (requires Apple Developer account):

1. **Export your certificate:**
   ```bash
   # On your Mac (where you have the certificate)
   security find-identity -v -p codesigning

   # Export as .p12 file
   # Keychain Access → Right-click certificate → Export
   ```

2. **Add to GitHub Secrets:**
   - Go to: Repository Settings → Secrets and variables → Actions
   - Add secrets:
     - `MACOS_CERTIFICATE`: Base64-encoded .p12 file
     - `MACOS_CERTIFICATE_PASSWORD`: Certificate password
     - `MACOS_CERTIFICATE_NAME`: Certificate name (e.g., "Apple Development: Your Name")

3. **Update workflow:**
   ```yaml
   - name: Import certificate
     run: |
       echo "${{ secrets.MACOS_CERTIFICATE }}" | base64 --decode > certificate.p12
       security create-keychain -p actions temp.keychain
       security import certificate.p12 -k temp.keychain -P "${{ secrets.MACOS_CERTIFICATE_PASSWORD }}" -T /usr/bin/codesign
       security set-key-partition-list -S apple-tool:,apple: -k actions temp.keychain

   - name: Build (with code signing)
     run: |
       xcodebuild build \
         -project VibrantFrog.xcodeproj \
         -scheme VibrantFrog \
         -configuration Release \
         CODE_SIGN_IDENTITY="${{ secrets.MACOS_CERTIFICATE_NAME }}"
   ```

4. **Notarization (optional, requires additional setup):**
   - Add notarization step after building
   - Requires Apple Developer credentials
   - See: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution

## Troubleshooting

### Build Fails

1. Check the Actions logs for error messages
2. Common issues:
   - Xcode version mismatch (update in workflow)
   - Missing dependencies (add to workflow)
   - Build path changes (update paths in workflow)

### Release Not Created

1. Check if tag was pushed: `git ls-remote --tags origin`
2. Check workflow permissions (needs `contents: write`)
3. Verify GITHUB_TOKEN has release permissions

### Unsigned App Warning

This is expected! Without code signing:
- Users see: "App is from an unidentified developer"
- Solution: Right-click → Open (first time only)
- Or: Get Apple Developer account and add signing

## Manual Release (Fallback)

If GitHub Actions fails, you can still release manually:

1. Build locally:
   ```bash
   cd VibrantFrogApp
   xcodebuild -project VibrantFrog.xcodeproj -scheme VibrantFrog -configuration Release clean build SYMROOT=build
   ```

2. Create artifacts:
   ```bash
   cd build/Release
   zip -r ../../../release/VibrantFrog-v1.1.0.zip VibrantFrog.app
   hdiutil create -volname "VibrantFrog" -srcfolder VibrantFrog.app -ov -format UDZO ../../../release/VibrantFrog-v1.1.0.dmg
   ```

3. Create release via GitHub UI (see: `release/CREATE_RELEASE.md`)

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Building and Testing macOS Apps](https://docs.github.com/en/actions/deployment/building-and-testing-macos)
- [Creating Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [Code Signing Guide](https://developer.apple.com/documentation/security/code_signing_guide)
