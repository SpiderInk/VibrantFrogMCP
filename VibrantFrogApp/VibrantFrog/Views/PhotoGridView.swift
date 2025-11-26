//
//  PhotoGridView.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import SwiftUI

struct PhotoGridView: View {
    let results: [PhotoSearchResult]
    @Binding var selectedPhotos: Set<String>

    @EnvironmentObject var photoLibraryService: PhotoLibraryService

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(results) { result in
                PhotoThumbnailView(
                    result: result,
                    isSelected: selectedPhotos.contains(result.photo.id),
                    onTap: {
                        toggleSelection(result.photo.id)
                    }
                )
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedPhotos.contains(id) {
            selectedPhotos.remove(id)
        } else {
            selectedPhotos.insert(id)
        }
    }
}

struct PhotoThumbnailView: View {
    let result: PhotoSearchResult
    let isSelected: Bool
    let onTap: () -> Void

    @EnvironmentObject var photoLibraryService: PhotoLibraryService
    @State private var thumbnail: NSImage?
    @State private var isHovering: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Photo thumbnail
            Group {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }

            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(6)
            }

            // Score badge on hover
            if isHovering {
                VStack {
                    Spacer()
                    HStack {
                        Text(result.formattedScore)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                        Spacer()
                    }
                    .padding(6)
                }
            }
        }
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .task {
            await loadThumbnail()
        }
        .help(result.photo.description ?? "No description")
    }

    private func loadThumbnail() async {
        thumbnail = await photoLibraryService.loadThumbnail(
            for: result.photo,
            targetSize: CGSize(width: 300, height: 300)
        )
    }
}

// MARK: - Preview

#Preview {
    let mockResults = [
        PhotoSearchResult(
            photo: Photo(id: "1", description: "A beautiful sunset"),
            score: 0.95
        ),
        PhotoSearchResult(
            photo: Photo(id: "2", description: "Mountain landscape"),
            score: 0.87
        ),
        PhotoSearchResult(
            photo: Photo(id: "3", description: "City at night"),
            score: 0.72
        )
    ]

    return PhotoGridView(results: mockResults, selectedPhotos: .constant([]))
        .environmentObject(PhotoLibraryService())
        .frame(width: 600, height: 400)
}
