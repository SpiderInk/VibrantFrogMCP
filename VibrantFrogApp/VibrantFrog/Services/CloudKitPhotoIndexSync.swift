//
//  CloudKitPhotoIndexSync.swift
//  VibrantFrog
//
//  Service for syncing photo index to CloudKit
//

import Foundation
import CloudKit

/// Manages CloudKit sync for the shared photo index database
class CloudKitPhotoIndexSync {
    static let shared = CloudKitPhotoIndexSync()

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let photoIndexRecordType = "PhotoIndex"

    var isCloudKitAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private init() {
        container = CKContainer(identifier: "iCloud.com.vibrantfrog.AuthorAICollab")
        privateDatabase = container.privateCloudDatabase
    }

    // MARK: - Photo Index Sync

    /// Upload the photo index database to CloudKit
    func uploadPhotoIndex(databaseURL: URL) async throws {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.cloudKitNotAvailable
        }

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CloudKitSyncError.databaseNotFound
        }

        print("📤 Uploading photo index to CloudKit...")
        print("   Database: \(databaseURL.path)")

        let recordID = CKRecord.ID(recordName: "photoIndex")

        // Fetch existing record or create new one
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
            print("   Updating existing CloudKit record")
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: photoIndexRecordType, recordID: recordID)
            print("   Creating new CloudKit record")
        }

        // Create asset from database file
        let asset = CKAsset(fileURL: databaseURL)
        record["database"] = asset
        record["updatedAt"] = Date()

        // Get file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: databaseURL.path),
           let fileSize = attributes[.size] as? Int64 {
            record["databaseSize"] = Int(fileSize)
            print("   Size: \(Double(fileSize) / 1024 / 1024) MB")
        }

        // Save to CloudKit
        _ = try await privateDatabase.save(record)

        print("✅ Photo index uploaded to CloudKit successfully")
    }

    /// Check if there's an update available in CloudKit
    func checkForUpdate(localModifiedDate: Date?) async throws -> Bool {
        guard isCloudKitAvailable else {
            return false
        }

        let recordID = CKRecord.ID(recordName: "photoIndex")

        do {
            let record = try await privateDatabase.record(for: recordID)

            guard let cloudUpdatedAt = record["updatedAt"] as? Date else {
                return false
            }

            // If we don't have a local version, update is available
            guard let localDate = localModifiedDate else {
                return true
            }

            // Update available if cloud version is newer
            return cloudUpdatedAt > localDate
        } catch let error as CKError where error.code == .unknownItem {
            // No record in CloudKit
            return false
        }
    }

    /// Download the photo index from CloudKit
    func downloadPhotoIndex(destinationURL: URL) async throws -> Bool {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.cloudKitNotAvailable
        }

        print("📥 Downloading photo index from CloudKit...")

        let recordID = CKRecord.ID(recordName: "photoIndex")

        do {
            let record = try await privateDatabase.record(for: recordID)

            guard let asset = record["database"] as? CKAsset,
                  let assetURL = asset.fileURL else {
                throw CloudKitSyncError.assetNotFound
            }

            // Copy database to destination
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: assetURL, to: destinationURL)

            if let size = record["databaseSize"] as? Int {
                print("   Size: \(Double(size) / 1024 / 1024) MB")
            }

            print("✅ Photo index downloaded from CloudKit successfully")
            return true
        } catch let error as CKError where error.code == .unknownItem {
            print("⚠️  No photo index found in CloudKit")
            return false
        }
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
