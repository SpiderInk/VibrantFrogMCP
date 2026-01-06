#!/usr/bin/env swift
import Foundation
import Photos

func testPhotoLookup() async {
    // Request access
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    print("Authorization status: \(status.rawValue)")

    guard status == .authorized else {
        print("Not authorized")
        return
    }

    // Fetch all photos
    let fetchOptions = PHFetchOptions()
    fetchOptions.fetchLimit = 10
    let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

    print("\nFound \(assets.count) assets")
    print("\nFirst 5 assets:")

    assets.enumerateObjects { asset, idx, stop in
        if idx < 5 {
            print("\n Asset \(idx):")
            print("   localIdentifier: \(asset.localIdentifier)")

            // Extract UUID
            let uuid = asset.localIdentifier.components(separatedBy: "/").first ?? asset.localIdentifier
            print("   UUID: \(uuid)")

            // Get cloud identifier
            let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: [asset.localIdentifier])
            if let mapping = mappings[asset.localIdentifier] {
                switch mapping {
                case .success(let cloudId):
                    print("   cloudIdentifier: \(cloudId.stringValue)")
                case .failure(let error):
                    print("   cloudIdentifier error: \(error)")
                }
            }
        } else {
            stop.pointee = true
        }
    }
}

Task {
    await testPhotoLookup()
    exit(0)
}

RunLoop.main.run()
