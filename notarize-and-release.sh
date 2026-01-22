#!/bin/bash
# Quick script to notarize and release VibrantFrog
# Run this tomorrow morning when Apple's servers are faster

set -e

echo "🔐 Starting notarization process..."

cd /Users/tpiazza/git/VibrantFrogMCP/VibrantFrogApp

# Clean and rebuild in Release mode without debug entitlements
echo "🔨 Building Release version with Developer ID certificate..."
xcodebuild clean -scheme VibrantFrog -configuration Release
xcodebuild build -scheme VibrantFrog -configuration Release \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_IDENTITY="Developer ID Application: Anthony Piazza (D7P5JN33ZJ)" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=D7P5JN33ZJ \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  -derivedDataPath ./build

# Create ZIP for notarization
echo "📦 Creating notarization ZIP..."
rm -f VibrantFrog-notarization.zip
ditto -c -k --keepParent ./build/Build/Products/Release/VibrantFrog.app VibrantFrog-notarization.zip

# Submit for notarization
echo "🚀 Submitting to Apple (this will wait for completion)..."
xcrun notarytool submit VibrantFrog-notarization.zip \
  --keychain-profile "vibrantfrog-notary" \
  --wait

# Get submission ID from output
SUBMISSION_ID=$(xcrun notarytool history --keychain-profile "vibrantfrog-notary" | grep -m1 "Accepted" | awk '{print $1}')

if [ -z "$SUBMISSION_ID" ]; then
  echo "❌ Notarization failed or timed out"
  echo "Check status with: xcrun notarytool history --keychain-profile vibrantfrog-notary"
  exit 1
fi

echo "✅ Notarization accepted! Submission ID: $SUBMISSION_ID"

# Staple the ticket
echo "📎 Stapling notarization ticket to app..."
xcrun stapler staple ./build/Build/Products/Release/VibrantFrog.app

# Verify
echo "🔍 Verifying notarization..."
spctl -a -vv ./build/Build/Products/Release/VibrantFrog.app

# Create new distributions
echo "📦 Creating notarized DMG and ZIP..."
cd /Users/tpiazza/git/VibrantFrogMCP

# Get version from Info.plist
VERSION=$(defaults read "$(pwd)/VibrantFrogApp/VibrantFrog/Info.plist" CFBundleShortVersionString)
echo "   Version: $VERSION"

rm -f release/VibrantFrog-v${VERSION}-notarized.*

# Create DMG
cp -R VibrantFrogApp/build/Build/Products/Release/VibrantFrog.app release/
hdiutil create -volname "VibrantFrog" -srcfolder release/VibrantFrog.app -ov -format UDZO release/VibrantFrog-v${VERSION}-notarized.dmg
rm -rf release/VibrantFrog.app

# Create ZIP
ditto -c -k --keepParent VibrantFrogApp/build/Build/Products/Release/VibrantFrog.app release/VibrantFrog-v${VERSION}-notarized.zip

echo "✅ Notarized binaries ready:"
ls -lh release/VibrantFrog-v${VERSION}-notarized.*

echo ""
echo "🎉 SUCCESS! Next steps:"
echo "1. Test the notarized app on another Mac (should open without security dialog)"
echo "2. Create v${VERSION} release: gh release create v${VERSION} --title 'VibrantFrog v${VERSION}' --notes 'Release notes here'"
echo "3. Upload binaries: gh release upload v${VERSION} release/VibrantFrog-v${VERSION}-notarized.*"
