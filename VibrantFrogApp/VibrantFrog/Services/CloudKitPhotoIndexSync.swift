//
//  CloudKitPhotoIndexSync.swift
//  VibrantFrog
//
//  Service for syncing photo index to CloudKit as individual records
//

import Foundation
import CloudKit
import SQLite3
import Photos

/// Manages CloudKit sync for the shared photo index database
class CloudKitPhotoIndexSync {
    static let shared = CloudKitPhotoIndexSync()

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let photoRecordType = "IndexedPhoto"
    private let batchSize = 400 // CloudKit limit is 400 operations per batch

    var isCloudKitAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private init() {
        container = CKContainer(identifier: "iCloud.com.vibrantfrog.AuthorAICollab")
        privateDatabase = container.privateCloudDatabase
    }

    // MARK: - Photo Index Sync

    /// Upload the photo index database to CloudKit as individual records
    func uploadPhotoIndex(databaseURL: URL) async throws {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.cloudKitNotAvailable
        }

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CloudKitSyncError.databaseNotFound
        }

        print("📤 Uploading photo index to CloudKit as individual records...")
        print("   Database: \(databaseURL.path)")

        // Read all photos from SQLite
        var photos = try readPhotosFromDatabase(databaseURL: databaseURL)
        print("   Found \(photos.count) photos to sync")

        // Update photos with PHCloudIdentifier (for cross-device access)
        print("   Getting PHCloudIdentifiers for cross-device photo access...")
        photos = try await enrichWithCloudIdentifiers(photos: photos)
        print("   ✅ Enriched \(photos.count) photos with cloud identifiers")

        // Upload in batches
        var uploadedCount = 0
        let totalBatches = (photos.count + batchSize - 1) / batchSize

        for batchIndex in 0..<totalBatches {
            let startIndex = batchIndex * batchSize
            let endIndex = min(startIndex + batchSize, photos.count)
            let batch = Array(photos[startIndex..<endIndex])

            print("   Uploading batch \(batchIndex + 1)/\(totalBatches) (\(batch.count) photos)...")

            // Create records for this batch
            let records = batch.map { photo in
                createRecord(from: photo)
            }

            // Save batch to CloudKit
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.isAtomic = false // Continue even if some records fail

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success():
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                privateDatabase.add(operation)
            }

            uploadedCount += batch.count
            print("   Progress: \(uploadedCount)/\(photos.count)")
        }

        print("✅ Successfully uploaded \(uploadedCount) photos to CloudKit")
    }

    // MARK: - Database Reading

    private struct PhotoRecord {
        let uuid: String
        let cloudGuid: String?
        let description: String
        let embedding: Data
        let indexedAt: Date
    }

    private func readPhotosFromDatabase(databaseURL: URL) throws -> [PhotoRecord] {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw CloudKitSyncError.databaseNotFound
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT uuid, cloud_guid, description, embedding, indexed_at FROM photo_index"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CloudKitSyncError.uploadFailed("Failed to prepare query")
        }
        defer { sqlite3_finalize(statement) }

        var photos: [PhotoRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let uuidCString = sqlite3_column_text(statement, 0),
                  let descCString = sqlite3_column_text(statement, 2) else {
                continue
            }

            let uuid = String(cString: uuidCString)

            // Get cloud_guid (optional)
            let cloudGuid: String?
            if let cloudGuidCString = sqlite3_column_text(statement, 1) {
                cloudGuid = String(cString: cloudGuidCString)
            } else {
                cloudGuid = nil
            }

            let description = String(cString: descCString)

            // Get embedding blob
            guard let blobPtr = sqlite3_column_blob(statement, 3) else { continue }
            let blobSize = sqlite3_column_bytes(statement, 3)
            let embedding = Data(bytes: blobPtr, count: Int(blobSize))

            // Get timestamp
            let timestamp = sqlite3_column_double(statement, 4)
            let indexedAt = Date(timeIntervalSince1970: timestamp)

            photos.append(PhotoRecord(
                uuid: uuid,
                cloudGuid: cloudGuid,
                description: description,
                embedding: embedding,
                indexedAt: indexedAt
            ))
        }

        return photos
    }

    /// Enrich photos with PHCloudIdentifier for cross-device access
    private func enrichWithCloudIdentifiers(photos: [PhotoRecord]) async throws -> [PhotoRecord] {
        print("   Enriching photos with PHCloudIdentifier...")

        // First, let's see what format we're dealing with
        if let firstPhoto = photos.first {
            print("   🔍 Sample database UUID: \(firstPhoto.uuid)")
        }

        // Fetch ALL assets from Photos library
        let fetchOptions = PHFetchOptions()
        let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        print("   Found \(allAssets.count) total assets in Photos library")

        // Sample a few localIdentifiers to see the format
        var sampleCount = 0
        allAssets.enumerateObjects { asset, _, stop in
            if sampleCount < 3 {
                print("   🔍 Sample PHAsset.localIdentifier: \(asset.localIdentifier)")
                sampleCount += 1
            } else {
                stop.pointee = true
            }
        }

        // Build map: UUID -> full localIdentifier
        // Try both uppercase and lowercase matching
        var uuidToLocalId: [String: String] = [:]
        var localIdentifiers: [String] = []

        allAssets.enumerateObjects { asset, _, _ in
            let localId = asset.localIdentifier

            // On macOS, localIdentifier might just be the UUID
            // On iOS, it's "UUID/L0/001" format
            // Store both the full localId and the UUID portion
            let uuid = localId.components(separatedBy: "/").first ?? localId

            // Store both uppercase and lowercase versions for matching
            uuidToLocalId[uuid.uppercased()] = localId
            localIdentifiers.append(localId)
        }

        print("   Built UUID->localId map with \(uuidToLocalId.count) assets")

        // Get PHCloudIdentifier mappings for ALL assets
        print("   Fetching cloud identifiers (this may take a while for \(localIdentifiers.count) assets)...")
        let mappings = try await PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: localIdentifiers)

        print("   Received \(mappings.count) cloud identifier mappings")

        // Build map: UUID -> PHCloudIdentifier
        var uuidToCloudId: [String: String] = [:]
        var successfulMappings = 0
        var failedMappings = 0

        for (localId, result) in mappings {
            switch result {
            case .success(let cloudIdentifier):
                let uuid = localId.components(separatedBy: "/").first ?? localId
                uuidToCloudId[uuid.uppercased()] = cloudIdentifier.stringValue
                successfulMappings += 1
            case .failure:
                failedMappings += 1
            }
        }

        print("   Cloud ID mappings: \(successfulMappings) successful, \(failedMappings) failed")

        // Sample a few to see what we got
        if let firstCloudId = uuidToCloudId.first {
            print("   🔍 Sample UUID->CloudID: \(firstCloudId.key) -> \(firstCloudId.value)")
        }

        // Create enriched photo records
        var enrichedPhotos: [PhotoRecord] = []
        var successCount = 0
        var failureCount = 0
        var firstFailedUUID: String?

        for photo in photos {
            let photoUUID = photo.uuid.uppercased()
            if let cloudGuid = uuidToCloudId[photoUUID] {
                // Update with PHCloudIdentifier format
                enrichedPhotos.append(PhotoRecord(
                    uuid: photo.uuid,
                    cloudGuid: cloudGuid,
                    description: photo.description,
                    embedding: photo.embedding,
                    indexedAt: photo.indexedAt
                ))
                successCount += 1
            } else {
                // No cloud identifier found, keep original
                if firstFailedUUID == nil {
                    firstFailedUUID = photo.uuid
                }
                enrichedPhotos.append(photo)
                failureCount += 1
            }
        }

        print("   Successfully enriched \(successCount) photos")
        if failureCount > 0 {
            print("   ⚠️ Could not enrich \(failureCount) photos (kept original values)")
            if let failedUUID = firstFailedUUID {
                print("   🔍 First failed UUID: \(failedUUID)")
                print("   🔍 Is it in uuidToCloudId? \(uuidToCloudId[failedUUID.uppercased()] != nil)")
                print("   🔍 Is it in uuidToLocalId? \(uuidToLocalId[failedUUID.uppercased()] != nil)")
            }
        }

        return enrichedPhotos
    }

    private func createRecord(from photo: PhotoRecord) -> CKRecord {
        let recordID = CKRecord.ID(recordName: photo.uuid)
        let record = CKRecord(recordType: photoRecordType, recordID: recordID)

        record["uuid"] = photo.uuid
        record["cloudGuid"] = photo.cloudGuid  // iCloud identifier for cross-device photo access
        record["photoDescription"] = photo.description
        record["embedding"] = photo.embedding
        record["indexedAt"] = photo.indexedAt

        // Add searchable tokens (lowercase words) for CloudKit array searching
        // CloudKit doesn't support CONTAINS on strings, but does support CONTAINS on arrays
        let tokens = photo.description
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 } // Only words with 3+ characters
        record["searchTokens"] = tokens

        return record
    }

    // MARK: - Querying CloudKit

    /// Search for photos in CloudKit by keyword
    func searchPhotos(query: String, limit: Int = 20) async throws -> [CKRecord] {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.cloudKitNotAvailable
        }

        print("🔍 Searching CloudKit for: \(query)")

        // Create predicate for description search
        let predicate = NSPredicate(format: "photoDescription CONTAINS[cd] %@", query)
        let queryOp = CKQuery(recordType: photoRecordType, predicate: predicate)
        queryOp.sortDescriptors = [NSSortDescriptor(key: "indexedAt", ascending: false)]

        // Perform query
        let (results, _) = try await privateDatabase.records(matching: queryOp, resultsLimit: limit)

        // Extract successful records
        let records = results.compactMap { (_, result) -> CKRecord? in
            switch result {
            case .success(let record):
                return record
            case .failure:
                return nil
            }
        }

        print("   Found \(records.count) matching photos")
        return records
    }

    /// Get total count of indexed photos in CloudKit
    func getPhotoCount() async throws -> Int {
        guard isCloudKitAvailable else {
            return 0
        }

        let predicate = NSPredicate(value: true) // Match all
        let query = CKQuery(recordType: photoRecordType, predicate: predicate)

        let (results, _) = try await privateDatabase.records(matching: query, resultsLimit: 1)

        // CloudKit doesn't provide count directly, so we'd need to fetch all or use a custom counter
        // For now, return a placeholder
        return results.count
    }
}

// MARK: - Errors

enum CloudKitSyncError: LocalizedError {
    case cloudKitNotAvailable
    case databaseNotFound
    case assetNotFound
    case uploadFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .cloudKitNotAvailable:
            return "iCloud not available. Please sign in to iCloud."
        case .databaseNotFound:
            return "Photo index database not found."
        case .assetNotFound:
            return "Photo index asset not found in CloudKit record."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}
