//
//  SettingsView.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var photoLibraryService: PhotoLibraryService
    @EnvironmentObject var llmService: LLMService

    @State private var selectedTab: SettingsTab = .model

    enum SettingsTab: String, CaseIterable {
        case model = "Model"
        case storage = "Storage"
        case about = "About"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            modelSettingsTab
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }
                .tag(SettingsTab.model)

            storageSettingsTab
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }
                .tag(SettingsTab.storage)

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .padding()
        .frame(width: 500, height: 400)
    }

    // MARK: - Model Settings

    private var modelSettingsTab: some View {
        Form {
            Section("AI Model") {
                HStack {
                    Text("Current Model:")
                    Spacer()
                    Text(llmService.modelName)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Status:")
                    Spacer()
                    if llmService.isModelLoaded {
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not Loaded", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if llmService.isProcessing {
                    ProgressView(value: llmService.loadingProgress) {
                        Text("Loading model...")
                    }
                }

                HStack {
                    Button("Load Model") {
                        Task {
                            try? await llmService.loadModel()
                        }
                    }
                    .disabled(llmService.isModelLoaded || llmService.isProcessing)

                    Button("Unload Model") {
                        llmService.unloadModel()
                    }
                    .disabled(!llmService.isModelLoaded || llmService.isProcessing)
                }
            }

            Section("Available Models") {
                let models = llmService.listAvailableModels()
                if models.isEmpty {
                    Text("No models found")
                        .foregroundStyle(.secondary)

                    Text("Add .gguf model files to:")
                        .font(.caption)
                    Text(llmService.modelsDirectory.path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(models, id: \.path) { modelURL in
                        HStack {
                            Image(systemName: "doc.fill")
                            Text(modelURL.lastPathComponent)
                            Spacer()
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
                               let size = attrs[.size] as? Int64 {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Button("Open Models Folder") {
                    NSWorkspace.shared.open(llmService.modelsDirectory)
                }
            }

            if let error = llmService.errorMessage {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Storage Settings

    private var storageSettingsTab: some View {
        Form {
            Section("Photo Library") {
                HStack {
                    Text("Authorization:")
                    Spacer()
                    Text(photoLibraryService.authorizationMessage)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total Photos:")
                    Spacer()
                    Text("\(photoLibraryService.totalPhotoCount)")
                        .foregroundStyle(.secondary)
                }

                Button("Request Photo Access") {
                    photoLibraryService.requestAuthorization()
                }
                .disabled(photoLibraryService.isAuthorized)
            }

            Section("Embedding Database") {
                if let store = try? EmbeddingStore() {
                    HStack {
                        Text("Indexed Photos:")
                        Spacer()
                        Text("\(store.getIndexedCount())")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Database Size:")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: store.databaseSize, countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Unable to access database")
                        .foregroundStyle(.red)
                }
            }

            Section("Data Location") {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let dataDir = appSupport.appendingPathComponent("VibrantFrog")

                Text(dataDir.path)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                Button("Open in Finder") {
                    NSWorkspace.shared.open(dataDir)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.artframe")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("VibrantFrog")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI-Powered Photo Search")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Version 1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 8) {
                Text("Search your photo library using natural language.")
                Text("Powered by embedded AI - your photos stay private.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Spacer()

            Text("Copyright 2025 Tony Piazza")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(PhotoLibraryService())
        .environmentObject(LLMService())
}
