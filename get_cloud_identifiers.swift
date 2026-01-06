#!/usr/bin/env swift
import Foundation
import Photos

// Helper script to get PHCloudIdentifiers for photo UUIDs
// Usage: ./get_cloud_identifiers.swift UUID1 UUID2 UUID3...
// Output: JSON mapping {uuid: cloud_identifier_string}

func getCloudIdentifiers(for uuids: [String]) async -> [String: String] {
    var result: [String: String] = [:]

    // Request photo library access
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard status == .authorized else {
        print("{}")
        return [:]
    }

    // Fetch assets for UUIDs
    let fetchOptions = PHFetchOptions()
    let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

    // Build UUID -> localIdentifier map
    var uuidToLocalId: [String: String] = [:]
    allAssets.enumerateObjects { asset, _, _ in
        let localId = asset.localIdentifier
        let uuid = localId.components(separatedBy: "/").first ?? localId
        uuidToLocalId[uuid.uppercased()] = localId
    }

    // Get localIdentifiers for requested UUIDs
    var localIdentifiers: [String] = []
    for uuid in uuids {
        if let localId = uuidToLocalId[uuid.uppercased()] {
            localIdentifiers.append(localId)
        }
    }

    // Get cloud identifier mappings
    let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: localIdentifiers)

    for (localId, mapping) in mappings {
        switch mapping {
        case .success(let cloudIdentifier):
            let uuid = localId.components(separatedBy: "/").first ?? localId
            result[uuid.uppercased()] = cloudIdentifier.stringValue
        case .failure:
            continue
        }
    }

    return result
}

// Main
let args = CommandLine.arguments
if args.count < 2 {
    print("{}")
    exit(0)
}

let uuids = Array(args[1...])

Task {
    let mappings = await getCloudIdentifiers(for: uuids)

    // Output as JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let jsonData = try? encoder.encode(mappings),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print(jsonString)
    } else {
        print("{}")
    }

    exit(0)
}

// Keep main thread alive
RunLoop.main.run()
