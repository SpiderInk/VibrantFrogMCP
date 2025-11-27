//
//  PhotoLibraryService.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import Foundation
import Photos
import AppKit
import Combine

/// Service for interacting with the user's photo library via PhotoKit
@MainActor
class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var totalPhotoCount: Int = 0
    @Published var indexedPhotoCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var photoAssets: PHFetchResult<PHAsset>?

    init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Authorization

    func requestAuthorization() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run {
                self.authorizationStatus = status
                if status == .authorized || status == .limited {
                    self.loadPhotoCount()
                }
            }
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var authorizationMessage: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Photo library access not yet requested"
        case .restricted:
            return "Photo library access is restricted"
        case .denied:
            return "Photo library access denied. Please enable in System Settings > Privacy & Security > Photos"
        case .authorized:
            return "Full photo library access granted"
        case .limited:
            return "Limited photo library access granted"
        @unknown default:
            return "Unknown authorization status"
        }
    }

    // MARK: - Photo Fetching

    private func loadPhotoCount() {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        self.photoAssets = fetchResult
        self.totalPhotoCount = fetchResult.count
    }

    /// Fetch all photos from the library
    func fetchAllPhotos() -> [Photo] {
        guard isAuthorized else { return [] }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var photos: [Photo] = []

        fetchResult.enumerateObjects { asset, _, _ in
            photos.append(Photo(from: asset))
        }

        return photos
    }

    /// Fetch photos in batches for indexing
    func fetchPhotosBatch(offset: Int, limit: Int) -> [Photo] {
        guard isAuthorized else { return [] }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var photos: [Photo] = []

        let endIndex = min(offset + limit, fetchResult.count)
        guard offset < fetchResult.count else { return [] }

        for i in offset..<endIndex {
            let asset = fetchResult.object(at: i)
            photos.append(Photo(from: asset))
        }

        return photos
    }

    /// Get PHAsset by local identifier
    func getAsset(byId id: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        return result.firstObject
    }

    // MARK: - Image Loading

    /// Load thumbnail by UUID (for LLM tool calling)
    func loadThumbnailByUUID(_ uuid: String, targetSize: CGSize = CGSize(width: 200, height: 200)) async -> NSImage? {
        print("📸 PhotoLibraryService: Loading thumbnail for UUID: \(uuid)")
        guard let asset = getAsset(byId: uuid) else {
            print("❌ PhotoLibraryService: Asset not found for UUID: \(uuid)")
            return nil
        }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if image != nil {
                    print("✅ PhotoLibraryService: Got thumbnail for \(uuid)")
                } else {
                    print("❌ PhotoLibraryService: Failed to get thumbnail for \(uuid)")
                }
                continuation.resume(returning: image)
            }
        }
    }

    /// Load multiple thumbnails by UUIDs
    func loadThumbnailsByUUIDs(_ uuids: [String], targetSize: CGSize = CGSize(width: 200, height: 200)) async -> [String: NSImage] {
        print("📸 PhotoLibraryService: Loading \(uuids.count) thumbnails")
        var results: [String: NSImage] = [:]

        for uuid in uuids {
            if let image = await loadThumbnailByUUID(uuid, targetSize: targetSize) {
                results[uuid] = image
            }
        }

        print("✅ PhotoLibraryService: Loaded \(results.count)/\(uuids.count) thumbnails")
        return results
    }

    /// Load thumbnail image for a photo
    func loadThumbnail(for photo: Photo, targetSize: CGSize = CGSize(width: 200, height: 200)) async -> NSImage? {
        return await loadThumbnailByUUID(photo.id, targetSize: targetSize)
    }

    /// Load full-resolution image for a photo
    func loadFullImage(for photo: Photo) async -> NSImage? {
        guard let asset = getAsset(byId: photo.id) else { return nil }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Load image data for LLM processing (JPEG format)
    func loadImageData(for photo: Photo, maxDimension: Int = 1024) async -> Data? {
        guard let asset = getAsset(byId: photo.id) else { return nil }

        let targetSize = CGSize(width: maxDimension, height: maxDimension)

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                guard let image = image else {
                    continuation.resume(returning: nil)
                    return
                }

                // Convert to JPEG data
                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: jpegData)
            }
        }
    }

    // MARK: - Album Management

    /// Fetch all user albums
    func fetchAlbums() -> [PhotoAlbum] {
        guard isAuthorized else { return [] }

        var albums: [PhotoAlbum] = []

        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )

        userAlbums.enumerateObjects { collection, _, _ in
            albums.append(PhotoAlbum(from: collection))
        }

        return albums.sorted { $0.title < $1.title }
    }

    /// Create a new album
    func createAlbum(named name: String) async throws -> String {
        var placeholder: PHObjectPlaceholder?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        }

        guard let localIdentifier = placeholder?.localIdentifier else {
            throw PhotoLibraryError.albumCreationFailed
        }

        return localIdentifier
    }

    /// Add photos to an album
    func addPhotos(_ photoIds: [String], toAlbum albumId: String) async throws {
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumId],
            options: nil
        ).firstObject else {
            throw PhotoLibraryError.albumNotFound
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: photoIds, options: nil)

        try await PHPhotoLibrary.shared().performChanges {
            guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else {
                return
            }
            albumChangeRequest.addAssets(assets)
        }
    }

    /// Delete an album (does not delete photos)
    func deleteAlbum(_ albumId: String) async throws {
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumId],
            options: nil
        ).firstObject else {
            throw PhotoLibraryError.albumNotFound
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSFastEnumeration)
        }
    }
}

// MARK: - Errors

enum PhotoLibraryError: LocalizedError {
    case notAuthorized
    case albumNotFound
    case albumCreationFailed
    case photoNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo library access not authorized"
        case .albumNotFound:
            return "Album not found"
        case .albumCreationFailed:
            return "Failed to create album"
        case .photoNotFound:
            return "Photo not found"
        }
    }
}
