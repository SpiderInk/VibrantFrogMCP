//
//  Photo.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import Foundation
import Photos
import AppKit

/// Represents a photo from the library with its metadata and AI-generated description
struct Photo: Identifiable, Hashable {
    let id: String  // PHAsset localIdentifier
    let creationDate: Date?
    let modificationDate: Date?
    let mediaType: PHAssetMediaType
    let pixelWidth: Int
    let pixelHeight: Int
    let isFavorite: Bool
    let location: CLLocation?

    // AI-generated fields (populated after indexing)
    var description: String?
    var embedding: [Float]?
    var isIndexed: Bool = false

    // Computed properties
    var aspectRatio: CGFloat {
        guard pixelHeight > 0 else { return 1.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    var formattedDate: String {
        guard let date = creationDate else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // Initialize from PHAsset
    init(from asset: PHAsset) {
        self.id = asset.localIdentifier
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.mediaType = asset.mediaType
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.isFavorite = asset.isFavorite
        self.location = asset.location
    }

    // Manual initializer for testing/previews
    init(
        id: String,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        mediaType: PHAssetMediaType = .image,
        pixelWidth: Int = 1920,
        pixelHeight: Int = 1080,
        isFavorite: Bool = false,
        location: CLLocation? = nil,
        description: String? = nil,
        embedding: [Float]? = nil,
        isIndexed: Bool = false
    ) {
        self.id = id
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.mediaType = mediaType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
        self.location = location
        self.description = description
        self.embedding = embedding
        self.isIndexed = isIndexed
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Photo, rhs: Photo) -> Bool {
        lhs.id == rhs.id
    }
}

/// Search result with similarity score
struct PhotoSearchResult: Identifiable {
    let photo: Photo
    let score: Float  // Cosine similarity score (0-1)

    var id: String { photo.id }

    var formattedScore: String {
        String(format: "%.1f%%", score * 100)
    }
}

/// Album representation
struct PhotoAlbum: Identifiable {
    let id: String  // PHAssetCollection localIdentifier
    let title: String
    let count: Int
    let type: PHAssetCollectionType

    init(from collection: PHAssetCollection) {
        self.id = collection.localIdentifier
        self.title = collection.localizedTitle ?? "Untitled"
        self.count = PHAsset.fetchAssets(in: collection, options: nil).count
        self.type = collection.assetCollectionType
    }
}
