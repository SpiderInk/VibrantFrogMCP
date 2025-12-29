//
//  CloudKitPhotoIndexSync.swift
//  VibrantFrog
//
//  Service for syncing photo index database to CloudKit as a single file
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

    var isCloudKitAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private init() {
        container = CKContainer(identifier: "iCloud.com.vibrantfrog.AuthorAICollab")
        privateDatabase = container.privateCloudDatabase
    }

    // MARK: - Photo Index Sync

    /// Enrich database with cloud identifiers (does NOT upload to CloudKit)
    func enrichDatabaseWithCloudGuids(databaseURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CloudKitSyncError.databaseNotFound
        }

        print("🔧 Enriching database with cloud identifiers...")
        print("   Database: \(databaseURL.path)")

        // Read all photos from SQLite
        var photos = try readPhotosFromDatabase(databaseURL: databaseURL)
        print("   Found \(photos.count) photos")

        // Update photos with PHCloudIdentifier (for cross-device access)
        print("   Getting PHCloudIdentifiers for cross-device photo access...")
        photos = try await enrichWithCloudIdentifiers(photos: photos)
        print("   ✅ Enriched \(photos.count) photos with cloud identifiers")

        // Write cloud_guids back to local database
        print("   Writing cloud identifiers back to local database...")
        try updateDatabaseWithCloudGuids(databaseURL: databaseURL, photos: photos)
        print("   ✅ Updated local database with cloud identifiers")
    }

    /// Upload the photo index database to CloudKit as a single database file
    func uploadPhotoIndex(databaseURL: URL) async throws {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.cloudKitNotAvailable
        }

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CloudKitSyncError.databaseNotFound
        }

        print("📤 Uploading photo index database to CloudKit...")

        // First, enrich the database with cloud identifiers if needed
        print("   Step 1: Enriching database with cloud identifiers...")
        try await enrichDatabaseWithCloudGuids(databaseURL: databaseURL)

        // Then upload the database file
        print("   Step 2: Uploading database file to CloudKit...")
        try await uploadDatabaseFile(databaseURL: databaseURL)

        print("✅ Successfully uploaded photo index to CloudKit")
    }

    /// Upload the database file as a CKAsset for direct download on iOS
    func uploadDatabaseFile(databaseURL: URL) async throws {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.cloudKitNotAvailable
        }

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CloudKitSyncError.databaseNotFound
        }

        print("📤 Uploading database file to CloudKit as CKAsset...")
        print("   Database: \(databaseURL.path)")

        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        print("   File size: \(formatBytes(Int(fileSize)))")

        // Create CKAsset from database file
        let asset = CKAsset(fileURL: databaseURL)

        // Create or update the photoIndex record
        let recordID = CKRecord.ID(recordName: "photoIndex")

        do {
            // Try to fetch existing record first
            let existingRecord = try await privateDatabase.record(for: recordID)
            existingRecord["database"] = asset
            existingRecord["lastUpdated"] = Date()
            existingRecord["fileSize"] = fileSize

            let savedRecord = try await privateDatabase.save(existingRecord)
            print("✅ Updated existing database record in CloudKit")
            print("   Record ID: \(savedRecord.recordID.recordName)")

        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create new one
            let record = CKRecord(recordType: "PhotoIndexDatabase", recordID: recordID)
            record["database"] = asset
            record["lastUpdated"] = Date()
            record["fileSize"] = fileSize

            let savedRecord = try await privateDatabase.save(record)
            print("✅ Created new database record in CloudKit")
            print("   Record ID: \(savedRecord.recordID.recordName)")

        } catch {
            print("❌ Failed to upload database: \(error.localizedDescription)")
            throw error
        }
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
        let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: localIdentifiers)

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

    /// Update local SQLite database with cloud_guid values
    private func updateDatabaseWithCloudGuids(databaseURL: URL, photos: [PhotoRecord]) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CloudKitSyncError.databaseNotFound
        }

        // Open database
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw CloudKitSyncError.uploadFailed("Failed to open database")
        }
        defer { sqlite3_close(db) }

        var updatedCount = 0
        var skippedCount = 0

        for photo in photos {
            // Only update if we have a cloud_guid
            guard let cloudGuid = photo.cloudGuid, !cloudGuid.isEmpty else {
                skippedCount += 1
                continue
            }

            // Update the record
            var statement: OpaquePointer?
            let updateSQL = "UPDATE photo_index SET cloud_guid = ? WHERE uuid = ?"

            if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (cloudGuid as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (photo.uuid as NSString).utf8String, -1, nil)

                if sqlite3_step(statement) == SQLITE_DONE {
                    updatedCount += 1
                }
                sqlite3_finalize(statement)
            }
        }

        print("      Updated \(updatedCount) records, skipped \(skippedCount) without cloud_guid")
    }

    // MARK: - Auto-Upload from Flag File

    /// Check for .needs-cloudkit-sync flag and upload if present
    func checkForAutoUpload() async {
        let indexPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("VibrantFrogPhotoIndex")
        let flagPath = indexPath.appendingPathComponent(".needs-cloudkit-sync")
        let dbPath = indexPath.appendingPathComponent("photo_index.db")

        guard FileManager.default.fileExists(atPath: flagPath.path) else {
            print("📋 No sync flag found, skipping auto-upload")
            return
        }

        print("🔔 Sync flag detected! Starting auto-upload...")

        do {
            // Read flag data
            let flagData = try Data(contentsOf: flagPath)
            let flagInfo = try JSONDecoder().decode(CloudKitSyncFlag.self, from: flagData)

            print("   Flag info: \(flagInfo.photo_count) photos, \(formatBytes(flagInfo.database_size))")

            // Check if database exists
            guard FileManager.default.fileExists(atPath: dbPath.path) else {
                print("   ⚠️  Database not found at \(dbPath.path)")
                return
            }

            // Trigger database file upload (not individual records)
            try await uploadDatabaseFile(databaseURL: dbPath)

            // Remove flag on success
            try FileManager.default.removeItem(at: flagPath)
            print("✅ Auto-upload completed successfully!")
            print("   Flag file removed: \(flagPath.path)")

        } catch {
            print("❌ Auto-upload failed: \(error.localizedDescription)")
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct CloudKitSyncFlag: Codable {
    let database_path: String
    let database_size: Int
    let timestamp: String
    let photo_count: Int
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
