//
//  IndexingView.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import SwiftUI

struct IndexingView: View {
    @EnvironmentObject var photoLibraryService: PhotoLibraryService
    @EnvironmentObject var llmService: LLMService

    @State private var isIndexing: Bool = false
    @State private var indexingProgress: Double = 0
    @State private var indexedCount: Int = 0
    @State private var totalToIndex: Int = 0
    @State private var currentPhotoDescription: String = ""
    @State private var errorMessage: String?
    @State private var showStopConfirmation: Bool = false

    private var embeddingStore: EmbeddingStore? {
        try? EmbeddingStore()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Status card
                statusCard

                // Progress section (when indexing)
                if isIndexing {
                    progressCard
                }

                // Statistics
                statisticsCard

                // Actions
                actionsCard
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            updateStatistics()
        }
    }

    // MARK: - Views

    private var statusCard: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: photoLibraryService.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(photoLibraryService.isAuthorized ? .green : .red)
                    Text("Photo Library Access")
                    Spacer()
                    Text(photoLibraryService.isAuthorized ? "Granted" : "Not Granted")
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Image(systemName: llmService.isModelLoaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(llmService.isModelLoaded ? .green : .orange)
                    Text("AI Model")
                    Spacer()
                    Text(llmService.modelName)
                        .foregroundStyle(.secondary)
                }

                if !llmService.isModelLoaded {
                    Text("Load a model in Settings to enable indexing")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var progressCard: some View {
        GroupBox("Indexing Progress") {
            VStack(spacing: 16) {
                ProgressView(value: indexingProgress) {
                    HStack {
                        Text("Processing photos...")
                        Spacer()
                        Text("\(indexedCount) / \(totalToIndex)")
                            .monospacedDigit()
                    }
                }

                if !currentPhotoDescription.isEmpty {
                    Text("Current: \(currentPhotoDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button("Stop Indexing") {
                    showStopConfirmation = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 8)
        }
        .confirmationDialog("Stop Indexing?", isPresented: $showStopConfirmation) {
            Button("Stop", role: .destructive) {
                stopIndexing()
            }
            Button("Continue", role: .cancel) {}
        } message: {
            Text("Progress will be saved. You can resume later.")
        }
    }

    private var statisticsCard: some View {
        GroupBox("Statistics") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Total Photos", systemImage: "photo.stack")
                    Spacer()
                    Text("\(photoLibraryService.totalPhotoCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Label("Indexed Photos", systemImage: "checkmark.square.fill")
                    Spacer()
                    Text("\(embeddingStore?.getIndexedCount() ?? 0)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Label("Remaining", systemImage: "square.dashed")
                    Spacer()
                    let remaining = photoLibraryService.totalPhotoCount - (embeddingStore?.getIndexedCount() ?? 0)
                    Text("\(max(0, remaining))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Label("Database Size", systemImage: "internaldrive")
                    Spacer()
                    Text(formatBytes(embeddingStore?.databaseSize ?? 0))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var actionsCard: some View {
        GroupBox("Actions") {
            VStack(spacing: 12) {
                Button {
                    startIndexing()
                } label: {
                    Label("Start Indexing", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartIndexing)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Divider()

                Button(role: .destructive) {
                    clearIndex()
                } label: {
                    Label("Clear Index", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isIndexing)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var canStartIndexing: Bool {
        photoLibraryService.isAuthorized &&
        llmService.isModelLoaded &&
        !isIndexing
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func updateStatistics() {
        // Refresh counts
        photoLibraryService.requestAuthorization()
    }

    // MARK: - Actions

    private func startIndexing() {
        guard canStartIndexing else { return }

        isIndexing = true
        errorMessage = nil
        indexedCount = 0

        Task {
            do {
                let store = try EmbeddingStore()
                let alreadyIndexed = store.getIndexedCount()

                // Get all photos
                let photos = photoLibraryService.fetchAllPhotos()
                totalToIndex = photos.count

                for (index, photo) in photos.enumerated() {
                    // Check if already indexed
                    if store.isIndexed(photoId: photo.id) {
                        continue
                    }

                    // Check if stopped
                    if !isIndexing { break }

                    // Load image data
                    guard let imageData = await photoLibraryService.loadImageData(for: photo) else {
                        continue
                    }

                    // Generate description
                    let description = try await llmService.describeImage(imageData: imageData)

                    // Generate embedding
                    let embedding = try await llmService.generateEmbedding(for: description)

                    // Store
                    try store.storeEmbedding(
                        photoId: photo.id,
                        description: description,
                        embedding: embedding
                    )

                    await MainActor.run {
                        indexedCount = index + 1
                        indexingProgress = Double(indexedCount) / Double(totalToIndex)
                        currentPhotoDescription = description
                    }
                }

                await MainActor.run {
                    isIndexing = false
                    currentPhotoDescription = ""
                }
            } catch {
                await MainActor.run {
                    isIndexing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopIndexing() {
        isIndexing = false
    }

    private func clearIndex() {
        do {
            let store = try EmbeddingStore()
            try store.clearAll()
            updateStatistics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    IndexingView()
        .environmentObject(PhotoLibraryService())
        .environmentObject(LLMService())
        .frame(width: 500, height: 600)
}
