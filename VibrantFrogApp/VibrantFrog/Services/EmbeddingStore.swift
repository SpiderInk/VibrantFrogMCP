//
//  EmbeddingStore.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import Foundation
import SQLite3

/// Stores photo embeddings and descriptions in SQLite for fast similarity search
class EmbeddingStore {
    private var db: OpaquePointer?
    private let dbPath: URL

    // Embedding dimension (depends on model)
    private let embeddingDimension = 384

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("VibrantFrog", isDirectory: true)

        // Create directory if needed
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        dbPath = appDir.appendingPathComponent("embeddings.sqlite")

        try openDatabase()
        try createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() throws {
        let result = sqlite3_open(dbPath.path, &db)
        guard result == SQLITE_OK else {
            throw EmbeddingStoreError.databaseOpenFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func createTables() throws {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS photo_embeddings (
                photo_id TEXT PRIMARY KEY,
                description TEXT,
                embedding BLOB,
                created_at REAL,
                model_version TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_created_at ON photo_embeddings(created_at);
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, createTableSQL, nil, nil, &errMsg)

        if result != SQLITE_OK {
            let error = errMsg != nil ? String(cString: errMsg!) : "Unknown error"
            sqlite3_free(errMsg)
            throw EmbeddingStoreError.tableCreationFailed(error)
        }
    }

    // MARK: - CRUD Operations

    /// Store an embedding for a photo
    func storeEmbedding(photoId: String, description: String, embedding: [Float], modelVersion: String = "1.0") throws {
        let sql = """
            INSERT OR REPLACE INTO photo_embeddings (photo_id, description, embedding, created_at, model_version)
            VALUES (?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw EmbeddingStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        // Bind values
        sqlite3_bind_text(stmt, 1, photoId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, description, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        // Convert embedding to blob
        let embeddingData = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
        _ = embeddingData.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(embeddingData.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 5, modelVersion, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw EmbeddingStoreError.insertFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Get embedding for a photo
    func getEmbedding(photoId: String) throws -> (description: String, embedding: [Float])? {
        let sql = "SELECT description, embedding FROM photo_embeddings WHERE photo_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw EmbeddingStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, photoId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        let description = String(cString: sqlite3_column_text(stmt, 0))

        guard let blobPtr = sqlite3_column_blob(stmt, 1) else {
            return nil
        }
        let blobSize = sqlite3_column_bytes(stmt, 1)
        let embedding = Array(UnsafeBufferPointer(
            start: blobPtr.assumingMemoryBound(to: Float.self),
            count: Int(blobSize) / MemoryLayout<Float>.size
        ))

        return (description, embedding)
    }

    /// Check if a photo is indexed
    func isIndexed(photoId: String) -> Bool {
        let sql = "SELECT 1 FROM photo_embeddings WHERE photo_id = ? LIMIT 1"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, photoId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Get total count of indexed photos
    func getIndexedCount() -> Int {
        let sql = "SELECT COUNT(*) FROM photo_embeddings"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Delete embedding for a photo
    func deleteEmbedding(photoId: String) throws {
        let sql = "DELETE FROM photo_embeddings WHERE photo_id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw EmbeddingStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, photoId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw EmbeddingStoreError.deleteFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Search

    /// Search for similar photos using cosine similarity
    func searchSimilar(queryEmbedding: [Float], limit: Int = 20) throws -> [(photoId: String, description: String, score: Float)] {
        let sql = "SELECT photo_id, description, embedding FROM photo_embeddings"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw EmbeddingStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [(photoId: String, description: String, score: Float)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let photoId = String(cString: sqlite3_column_text(stmt, 0))
            let description = String(cString: sqlite3_column_text(stmt, 1))

            guard let blobPtr = sqlite3_column_blob(stmt, 2) else {
                continue
            }
            let blobSize = sqlite3_column_bytes(stmt, 2)
            let embedding = Array(UnsafeBufferPointer(
                start: blobPtr.assumingMemoryBound(to: Float.self),
                count: Int(blobSize) / MemoryLayout<Float>.size
            ))

            let score = cosineSimilarity(queryEmbedding, embedding)
            results.append((photoId, description, score))
        }

        // Sort by score descending and limit
        return results
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    // MARK: - Maintenance

    /// Clear all embeddings
    func clearAll() throws {
        let sql = "DELETE FROM photo_embeddings"

        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)

        if result != SQLITE_OK {
            let error = errMsg != nil ? String(cString: errMsg!) : "Unknown error"
            sqlite3_free(errMsg)
            throw EmbeddingStoreError.deleteFailed(error)
        }
    }

    /// Get database file size
    var databaseSize: Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }
}

// MARK: - Errors

enum EmbeddingStoreError: LocalizedError {
    case databaseOpenFailed(String)
    case tableCreationFailed(String)
    case prepareFailed(String)
    case insertFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let msg):
            return "Failed to open database: \(msg)"
        case .tableCreationFailed(let msg):
            return "Failed to create tables: \(msg)"
        case .prepareFailed(let msg):
            return "Failed to prepare statement: \(msg)"
        case .insertFailed(let msg):
            return "Failed to insert: \(msg)"
        case .deleteFailed(let msg):
            return "Failed to delete: \(msg)"
        }
    }
}
