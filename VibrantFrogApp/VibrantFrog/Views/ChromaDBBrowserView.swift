//
//  ChromaDBBrowserView.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import SwiftUI

struct PhotoIndexEntry: Identifiable {
    let id: String
    let description: String
    let createdAt: Date
    let modelVersion: String
    let relevanceScore: Float?
}

struct ChromaDBBrowserView: View {
    @State private var searchQuery: String = ""
    @State private var entries: [PhotoIndexEntry] = []
    @State private var totalCount: Int = 0
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation: Bool = false
    @State private var entryToDelete: PhotoIndexEntry?

    private var embeddingStore: EmbeddingStore? {
        try? EmbeddingStore()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with statistics
            headerView

            Divider()

            // Search bar
            searchBar

            Divider()

            // Content area
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            } else if entries.isEmpty {
                emptyView
            } else {
                entriesList
            }
        }
        .onAppear {
            loadAllEntries()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Photo Index Browser")
                    .font(.headline)
                Text("\(totalCount) indexed photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: loadAllEntries) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search indexed photos...", text: $searchQuery)
                .textFieldStyle(.plain)
                .onSubmit {
                    performSearch()
                }

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    loadAllEntries()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Search") {
                performSearch()
            }
            .buttonStyle(.borderedProminent)
            .disabled(searchQuery.isEmpty)

            Button("Show All") {
                searchQuery = ""
                loadAllEntries()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var entriesList: some View {
        List {
            ForEach(entries) { entry in
                entryRow(entry)
            }
        }
        .listStyle(.inset)
    }

    private func entryRow(_ entry: PhotoIndexEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photo ID: \(entry.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let score = entry.relevanceScore {
                    Text("Relevance: \(String(format: "%.2f", score))")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            Text(entry.description)
                .font(.body)
                .lineLimit(3)

            HStack {
                Label(entry.createdAt.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Model: \(entry.modelVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(action: {
                    entryToDelete = entry
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Photos Indexed")
                .font(.title3)

            Text("Index your photos in the Indexing tab to see them here")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Error Loading Index")
                .font(.title3)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                loadAllEntries()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadAllEntries() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let store = embeddingStore else {
                    await MainActor.run {
                        errorMessage = "Failed to initialize embedding store"
                        isLoading = false
                    }
                    return
                }

                let count = store.getIndexedCount()
                let loadedEntries = try await loadEntriesFromStore(store: store)

                await MainActor.run {
                    totalCount = count
                    entries = loadedEntries
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else {
            loadAllEntries()
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let store = embeddingStore else {
                    await MainActor.run {
                        errorMessage = "Failed to initialize embedding store"
                        isLoading = false
                    }
                    return
                }

                // Search using the query - this will need embeddings
                let searchedEntries = try await searchEntriesInStore(store: store, query: searchQuery)

                await MainActor.run {
                    entries = searchedEntries
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func deleteEntry(_ entry: PhotoIndexEntry) {
        Task {
            do {
                guard let store = embeddingStore else { return }
                try store.deleteEmbedding(photoId: entry.id)

                await MainActor.run {
                    entries.removeAll { $0.id == entry.id }
                    totalCount -= 1
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Database Operations

    private func loadEntriesFromStore(store: EmbeddingStore) async throws -> [PhotoIndexEntry] {
        let results = try store.getAllEntries(limit: 100)

        return results.map { result in
            PhotoIndexEntry(
                id: result.photoId,
                description: result.description,
                createdAt: result.createdAt,
                modelVersion: result.modelVersion,
                relevanceScore: nil
            )
        }
    }

    private func searchEntriesInStore(store: EmbeddingStore, query: String) async throws -> [PhotoIndexEntry] {
        // Get all entries and filter by description containing the query
        let allResults = try store.getAllEntries(limit: 500)

        let filtered = allResults.filter { result in
            result.description.localizedCaseInsensitiveContains(query)
        }

        return filtered.map { result in
            PhotoIndexEntry(
                id: result.photoId,
                description: result.description,
                createdAt: result.createdAt,
                modelVersion: result.modelVersion,
                relevanceScore: nil
            )
        }
    }
}

#Preview {
    ChromaDBBrowserView()
        .frame(width: 600, height: 500)
}
