//
//  CloudKitPhotoIndexSync.swift
//  VibrantFrog
//
//  Service for syncing photo index to CloudKit as individual records
//

import Foundation
import CloudKit
import SQLite3

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
        let photos = try readPhotosFromDatabase(databaseURL: databaseURL)
        print("   Found \(photos.count) photos to sync")

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

        let sql = "SELECT uuid, description, embedding, indexed_at FROM photo_index"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CloudKitSyncError.uploadFailed("Failed to prepare query")
        }
        defer { sqlite3_finalize(statement) }

        var photos: [PhotoRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let uuidCString = sqlite3_column_text(statement, 0),
                  let descCString = sqlite3_column_text(statement, 1) else {
                continue
            }

            let uuid = String(cString: uuidCString)
            let description = String(cString: descCString)

            // Get embedding blob
            guard let blobPtr = sqlite3_column_blob(statement, 2) else { continue }
            let blobSize = sqlite3_column_bytes(statement, 2)
            let embedding = Data(bytes: blobPtr, count: Int(blobSize))

            // Get timestamp
            let timestamp = sqlite3_column_double(statement, 3)
            let indexedAt = Date(timeIntervalSince1970: timestamp)

            photos.append(PhotoRecord(
                uuid: uuid,
                description: description,
                embedding: embedding,
                indexedAt: indexedAt
            ))
        }

        return photos
    }

    private func createRecord(from photo: PhotoRecord) -> CKRecord {
        let recordID = CKRecord.ID(recordName: photo.uuid)
        let record = CKRecord(recordType: photoRecordType, recordID: recordID)

        record["uuid"] = photo.uuid
        record["photoDescription"] = photo.description
        record["embedding"] = photo.embedding
        record["indexedAt"] = photo.indexedAt

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
