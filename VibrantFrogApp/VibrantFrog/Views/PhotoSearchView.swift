//
//  PhotoSearchView.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import SwiftUI

struct PhotoSearchView: View {
    @EnvironmentObject var photoLibraryService: PhotoLibraryService
    @EnvironmentObject var llmService: LLMService

    @State private var searchText: String = ""
    @State private var searchResults: [PhotoSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var selectedPhotos: Set<String> = []
    @State private var showCreateAlbumSheet: Bool = false
    @State private var newAlbumName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search your photos...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(.background)
            .cornerRadius(8)
            .padding()

            Divider()

            // Results or placeholder
            if !photoLibraryService.isAuthorized {
                unauthorizedView
            } else if !llmService.isModelLoaded {
                modelNotLoadedView
            } else if searchResults.isEmpty && searchText.isEmpty {
                emptyStateView
            } else if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                noResultsView
            } else {
                resultsView
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if !selectedPhotos.isEmpty {
                    Button {
                        showCreateAlbumSheet = true
                    } label: {
                        Label("Create Album", systemImage: "folder.badge.plus")
                    }

                    Text("\(selectedPhotos.count) selected")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showCreateAlbumSheet) {
            createAlbumSheet
        }
    }

    // MARK: - Views

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Search Your Photos")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Type a description to find matching photos.\nFor example: \"sunset at the beach\" or \"birthday party\"")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if photoLibraryService.totalPhotoCount > 0 {
                Text("\(photoLibraryService.totalPhotoCount) photos in library")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Results")
                .font(.title2)
                .fontWeight(.semibold)

            Text("No photos found matching \"\(searchText)\".\nTry a different search term.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Photo Access Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text(photoLibraryService.authorizationMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if photoLibraryService.authorizationStatus == .denied {
                Button("Open System Settings") {
                    photoLibraryService.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)

                Text("Enable VibrantFrog under Privacy & Security → Photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Request Access") {
                    photoLibraryService.requestAuthorization()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modelNotLoadedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("AI Model Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Load the AI model in Settings to enable photo search.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Model: \(llmService.modelName)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        ScrollView {
            PhotoGridView(
                results: searchResults,
                selectedPhotos: $selectedPhotos
            )
            .padding()
        }
    }

    private var createAlbumSheet: some View {
        VStack(spacing: 20) {
            Text("Create Album")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Album Name", text: $newAlbumName)
                .textFieldStyle(.roundedBorder)

            Text("This will create an album with \(selectedPhotos.count) selected photos.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    showCreateAlbumSheet = false
                    newAlbumName = ""
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    createAlbum()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newAlbumName.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        guard llmService.isModelLoaded else { return }

        isSearching = true
        searchResults = []

        Task {
            do {
                // Generate embedding for query
                let queryEmbedding = try await llmService.generateEmbedding(for: searchText)

                // Search in embedding store
                let store = try EmbeddingStore()
                let results = try store.searchSimilar(queryEmbedding: queryEmbedding, limit: 50)

                // Convert to PhotoSearchResult
                let photos = results.compactMap { result -> PhotoSearchResult? in
                    let photo = Photo(
                        id: result.photoId,
                        description: result.description,
                        isIndexed: true
                    )
                    return PhotoSearchResult(photo: photo, score: result.score)
                }

                await MainActor.run {
                    searchResults = photos
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    // Handle error
                }
            }
        }
    }

    private func createAlbum() {
        guard !newAlbumName.isEmpty, !selectedPhotos.isEmpty else { return }

        Task {
            do {
                let albumId = try await photoLibraryService.createAlbum(named: newAlbumName)
                try await photoLibraryService.addPhotos(Array(selectedPhotos), toAlbum: albumId)

                await MainActor.run {
                    showCreateAlbumSheet = false
                    newAlbumName = ""
                    selectedPhotos = []
                }
            } catch {
                // Handle error
                print("Failed to create album: \(error)")
            }
        }
    }
}

#Preview {
    PhotoSearchView()
        .environmentObject(PhotoLibraryService())
        .environmentObject(LLMService())
}
