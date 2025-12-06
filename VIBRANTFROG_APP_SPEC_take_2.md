# VibrantFrog.app Product Specification (Take 2)

**Version:** 2.0 Draft
**Last Updated:** 2025-11-23
**Author:** Claude + Tony Piazza

---

## Executive Summary

VibrantFrog.app is a **Mac App Store** native application that provides AI-powered photo library search, organization, and management. It features an embedded LLM (via llama.cpp), native PhotoKit integration, and an extensible architecture that allows power users to add MCP server capabilities, face recognition, and remote access via optional extensions.

### Key Differentiators from Take 1

| Aspect | Take 1 (Original) | Take 2 (App Store Friendly) |
|--------|-------------------|----------------------------|
| Distribution | DMG only | **Mac App Store** + Extensions |
| LLM | Requires Ollama | **Embedded llama.cpp** |
| Photos Access | osxphotos (unsandboxed) | **PhotoKit** (sandboxed) |
| MCP Server | Built-in | **Optional Extension** |
| Marketing | Website only | **App Store discoverability** |

### Reusable Code Assets

We have significant existing code to leverage:
- **PhotoOrganizerPro** (`/Users/tpiazza/git/FrogTeamMCP/PhotoOrganizerPro`) - Complete macOS photo services
- **FrogTeamMCP** (`/Users/tpiazza/git/FrogTeamMCP`) - MCP implementation, local tools
- **llama.cpp** (`/Users/tpiazza/git/llama.cpp`) - Swift bindings, xcframework
- **VibrantFrogMCP** (`/Users/tpiazza/git/VibrantFrogMCP`) - Python MCP server, indexer

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [App Store Core App](#2-app-store-core-app)
3. [VibrantFrog SDK](#3-vibrantfrog-sdk)
4. [Extension System](#4-extension-system)
5. [Embedded LLM Integration](#5-embedded-llm-integration)
6. [PhotoKit Integration](#6-photokit-integration)
7. [Chat Interface](#7-chat-interface)
8. [MCP Extension](#8-mcp-extension)
9. [Claude Desktop Integration](#9-claude-desktop-integration)
10. [Remote Access Extension](#10-remote-access-extension)
11. [Data Storage & Privacy](#11-data-storage--privacy)
12. [Monetization Strategy](#12-monetization-strategy)
13. [Development Roadmap](#13-development-roadmap)
14. [Technical Implementation](#14-technical-implementation)
15. [Reusable Code Reference](#15-reusable-code-reference)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    VibrantFrog.app (Mac App Store)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         Core App (Sandboxed)                           │ │
│  ├────────────────────────────────────────────────────────────────────────┤ │
│  │                                                                         │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐   │ │
│  │  │  Chat UI    │  │  Embedded   │  │  PhotoKit   │  │  VibrantFrog │   │ │
│  │  │  (SwiftUI)  │  │  LLM        │  │  Service    │  │  SDK         │   │ │
│  │  │             │  │             │  │             │  │              │   │ │
│  │  │  Native     │  │ llama.cpp   │  │ PHAsset     │  │  - Search    │   │ │
│  │  │  macOS      │  │ xcframework │  │ PHAlbum     │  │  - Albums    │   │ │
│  │  │  Menu Bar   │  │             │  │ PHFetch     │  │  - Index     │   │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └──────────────┘   │ │
│  │                                                                         │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │  Embedding Store (SQLite/ChromaDB-lite - Sandboxed)             │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                    Extensions Discovery UI                             │ │
│  ├────────────────────────────────────────────────────────────────────────┤ │
│  │                                                                         │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │  │ 🔌 MCP Server   │  │ 👤 Face Recog   │  │ 🌐 Remote Access│        │ │
│  │  │ Extension       │  │ Extension       │  │ Extension       │        │ │
│  │  │                 │  │                 │  │                 │        │ │
│  │  │ [Get Free]      │  │ [Get Free]      │  │ [Get Free]      │        │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │ │
│  │                                                                         │ │
│  │  → Opens vibrantfrog.app/extensions or GitHub                          │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

          Extensions (Downloaded from Website - Notarized DMGs)
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐ │
│  │ VibrantFrog     │  │ VibrantFrog     │  │ VibrantFrog                 │ │
│  │ MCP Helper      │  │ Face Recog      │  │ Remote Access               │ │
│  │                 │  │                 │  │                             │ │
│  │ - MCP Server    │  │ - InsightFace   │  │ - Cloudflare Tunnel         │ │
│  │ - HTTP :5050    │  │ - Face Cluster  │  │ - Authentication            │ │
│  │ - Claude Config │  │ - Person Labels │  │ - iOS/Remote MCP            │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────┘ │
│                                                                              │
│  Uses VibrantFrog SDK (shared library with main app)                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌───────────────────────────┐   ┌───────────────────────────────────────────┐
│  VibrantFrog SDK          │   │  External Clients                         │
│  (Open Source)            │   │                                           │
├───────────────────────────┤   │  ┌─────────────┐  ┌─────────────────────┐ │
│                           │   │  │ Claude      │  │ Claude iOS          │ │
│  Swift Package:           │   │  │ Desktop     │  │ (via Cloudflare)    │ │
│  - VibrantFrogSDK         │   │  │             │  │                     │ │
│  - VibrantFrogMCP         │   │  │ localhost   │  │ https://tunnel.url  │ │
│                           │   │  │ :5050       │  │                     │ │
│  Python Package:          │   │  └─────────────┘  └─────────────────────┘ │
│  - vibrantfrog            │   │                                           │
│  - vibrantfrog.mcp        │   │                                           │
│                           │   │                                           │
└───────────────────────────┘   └───────────────────────────────────────────┘
```

---

## 2. App Store Core App

### 2.1 App Store Compliance

| Requirement | Implementation |
|-------------|----------------|
| Sandboxing | Full sandbox with Photos entitlement |
| Photos Access | PhotoKit (PHPhotoLibrary) |
| No External Dependencies | Embedded llama.cpp, bundled model |
| No Config File Modification | Extensions handle Claude config |
| Self-Contained | All features work without internet |

### 2.2 Core Features (App Store Version)

| Feature | Included | Implementation |
|---------|----------|----------------|
| Natural language photo search | ✅ | Embedded LLM + embeddings |
| Album creation/management | ✅ | PhotoKit PHAssetCollection |
| Photo browsing with thumbnails | ✅ | PHImageManager |
| Chat interface | ✅ | SwiftUI + llama.cpp |
| Background indexing | ✅ | BGTaskScheduler |
| Menu bar presence | ✅ | NSStatusItem |
| Embedding storage | ✅ | SQLite (sandbox-safe) |
| MCP Server | ❌ | Extension |
| Face recognition | ❌ | Extension |
| Remote access | ❌ | Extension |
| Claude Desktop config | ❌ | Extension |

### 2.3 App Bundle Structure

```
VibrantFrog.app/
├── Contents/
│   ├── MacOS/
│   │   └── VibrantFrog              # Main executable
│   ├── Frameworks/
│   │   └── llama.framework/         # Embedded LLM framework
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   ├── Models/
│   │   │   └── phi-3-vision-q4.gguf # ~2GB bundled model
│   │   └── Embeddings/
│   │       └── all-MiniLM-L6-v2/    # Sentence transformer
│   ├── Info.plist
│   └── Entitlements/
│       └── VibrantFrog.entitlements
├── VibrantFrogSDK.framework/        # Shared SDK
└── _CodeSignature/
```

### 2.4 Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- App Sandbox (required for App Store) -->
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- Photos Library Access -->
    <key>com.apple.security.personal-information.photos-library</key>
    <true/>

    <!-- Allow read/write to app's container -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

---

## 3. VibrantFrog SDK

### 3.1 Overview

Open-source SDK shared between:
- Main App Store app
- MCP Extension
- Face Recognition Extension
- Third-party developers

### 3.2 Swift Package Structure

```
VibrantFrogSDK/
├── Package.swift
├── Sources/
│   ├── VibrantFrogSDK/
│   │   ├── Core/
│   │   │   ├── VibrantFrog.swift           # Main entry point
│   │   │   ├── Configuration.swift         # SDK configuration
│   │   │   └── Errors.swift                # Error types
│   │   ├── Services/
│   │   │   ├── PhotoLibraryService.swift   # FROM: PhotoOrganizerPro
│   │   │   ├── AlbumGenerationService.swift # FROM: PhotoOrganizerPro
│   │   │   ├── VisionAnalysisService.swift  # FROM: PhotoOrganizerPro
│   │   │   ├── EmbeddingService.swift       # Vector embeddings
│   │   │   └── SearchService.swift          # Semantic search
│   │   ├── Models/
│   │   │   ├── Photo.swift
│   │   │   ├── PhotoAnalysis.swift         # FROM: PhotoOrganizerPro
│   │   │   ├── Album.swift
│   │   │   ├── AlbumSuggestion.swift       # FROM: PhotoOrganizerPro
│   │   │   └── SearchResult.swift
│   │   ├── Storage/
│   │   │   ├── EmbeddingStore.swift        # SQLite-based
│   │   │   └── AnalysisCache.swift
│   │   └── LLM/
│   │       ├── LlamaContext.swift          # FROM: llama.cpp examples
│   │       ├── LlamaState.swift            # FROM: llama.cpp examples
│   │       └── VisionLLM.swift             # Image understanding
│   │
│   └── VibrantFrogMCP/
│       ├── MCPServer.swift                 # HTTP server
│       ├── MCPProtocol.swift               # FROM: FrogTeamMCP
│       ├── MCPTools.swift                  # Tool definitions
│       └── MCPTransport.swift              # Streamable HTTP
│
├── Tests/
└── README.md
```

### 3.3 Core API

```swift
import VibrantFrogSDK

// Initialize SDK
let vibrantFrog = VibrantFrog(configuration: .default)

// Search photos
let results = try await vibrantFrog.search("beach sunset vacation")
for result in results {
    print("\(result.photo.filename) - \(result.relevance)")
}

// Create album from search
let album = try await vibrantFrog.createAlbum(
    name: "Beach Vacation 2024",
    fromSearch: "beach sunset vacation",
    limit: 50
)

// Get photo analysis
let analysis = try await vibrantFrog.analyzePhoto(assetId: "ABC123")
print(analysis.description)
print(analysis.categories)
print(analysis.detectedObjects)

// Index library (background)
try await vibrantFrog.indexLibrary(
    progressHandler: { progress in
        print("Indexed: \(progress.completed)/\(progress.total)")
    }
)
```

### 3.4 Python Package (for Extensions)

```python
# vibrantfrog/__init__.py
from .sdk import VibrantFrog
from .mcp import MCPServer, create_mcp_server

# Usage
from vibrantfrog import VibrantFrog

vf = VibrantFrog()
results = vf.search("beach sunset")
album = vf.create_album("Beach Photos", results[:50])

# MCP Server
from vibrantfrog import create_mcp_server
server = create_mcp_server(vf)
server.run(port=5050)
```

---

## 4. Extension System

### 4.1 Extension Discovery UI

```
┌─────────────────────────────────────────────────────────────────┐
│  Extend VibrantFrog                                    [×]      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Add powerful features to VibrantFrog with free extensions.     │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  🔌 MCP Server Extension                                    ││
│  │                                                              ││
│  │  Connect Claude Desktop to search and organize your         ││
│  │  photos using natural language.                             ││
│  │                                                              ││
│  │  • Expose VibrantFrog tools via MCP protocol                ││
│  │  • Works with Claude Desktop and other MCP clients          ││
│  │  • One-click Claude Desktop configuration                   ││
│  │                                                              ││
│  │  Status: Not Installed          [Download Extension]        ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  👤 Face Recognition Extension                              ││
│  │                                                              ││
│  │  Identify and search for people in your photos.             ││
│  │                                                              ││
│  │  • Automatic face detection and clustering                  ││
│  │  • Label faces with names                                   ││
│  │  • Search: "photos with Mom and Dad"                        ││
│  │                                                              ││
│  │  Status: Not Installed          [Download Extension]        ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  🌐 Remote Access Extension                                 ││
│  │                                                              ││
│  │  Access VibrantFrog from your iPhone or anywhere.           ││
│  │                                                              ││
│  │  • Secure Cloudflare Tunnel                                 ││
│  │  • Works with Claude iOS (when MCP supported)               ││
│  │  • Token-based authentication                               ││
│  │                                                              ││
│  │  Status: Not Installed          [Download Extension]        ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ────────────────────────────────────────────────────────────── │
│                                                                  │
│  🔧 For Developers                                              │
│                                                                  │
│  Build your own extensions with the VibrantFrog SDK:            │
│  github.com/vibrantfrog/sdk                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Extension Communication

Extensions communicate with the main app via:

1. **Shared App Group** (for data access)
   ```swift
   // Main app writes to shared container
   let sharedURL = FileManager.default.containerURL(
       forSecurityApplicationGroupIdentifier: "group.com.vibrantfrog"
   )
   ```

2. **XPC Services** (for method calls)
   ```swift
   // Extension calls main app's XPC service
   let connection = NSXPCConnection(serviceName: "com.vibrantfrog.sdk")
   connection.remoteObjectInterface = NSXPCInterface(with: VibrantFrogProtocol.self)
   ```

3. **URL Schemes** (for launching)
   ```swift
   // Extension can open main app
   NSWorkspace.shared.open(URL(string: "vibrantfrog://search?q=beach")!)
   ```

### 4.3 Extension Distribution

| Extension | Size | Download |
|-----------|------|----------|
| MCP Server | ~5MB | vibrantfrog.app/extensions/mcp |
| Face Recognition | ~50MB | vibrantfrog.app/extensions/faces |
| Remote Access | ~10MB | vibrantfrog.app/extensions/remote |

All extensions are:
- **Free** (open source on GitHub)
- **Notarized** (no Gatekeeper warnings)
- **Signed** with Developer ID
- **Auto-updating** via Sparkle

---

## 5. Embedded LLM Integration

### 5.1 Model Selection

| Model | Size | Quality | Speed (M2) | Recommendation |
|-------|------|---------|------------|----------------|
| Phi-3 Vision (Q4) | ~2GB | Good | ~25 tok/s | **Default** |
| LLaVA 7B (Q4) | ~4GB | Better | ~15 tok/s | Optional download |
| MiniCPM-V (Q4) | ~3GB | Good | ~20 tok/s | Alternative |

### 5.2 llama.cpp Integration

**Reuse from:** `/Users/tpiazza/git/llama.cpp/examples/llama.swiftui/`

```swift
// LlamaContext.swift (from llama.cpp examples)
actor LlamaContext {
    private var model: OpaquePointer
    private var context: OpaquePointer

    init(modelPath: String) throws {
        // Load model with Metal acceleration
        var params = llama_model_default_params()
        params.n_gpu_layers = 99  // Use GPU for all layers

        self.model = llama_load_model_from_file(modelPath, params)
        // ...
    }

    func complete(prompt: String) async throws -> String {
        // Token generation with sampling
    }

    func describeImage(imageData: Data, prompt: String) async throws -> String {
        // Vision model inference
    }
}
```

### 5.3 Model Management

```swift
@MainActor
class ModelManager: ObservableObject {
    @Published var currentModel: ModelInfo?
    @Published var availableModels: [ModelInfo] = []
    @Published var downloadProgress: Float = 0

    private var llamaContext: LlamaContext?

    // Bundled model (always available)
    let bundledModel = ModelInfo(
        name: "Phi-3 Vision",
        filename: "phi-3-vision-q4.gguf",
        size: 2_000_000_000,
        isBundled: true
    )

    // Downloadable models
    let downloadableModels = [
        ModelInfo(
            name: "LLaVA 7B",
            filename: "llava-7b-q4.gguf",
            url: "https://huggingface.co/.../llava-7b-q4.gguf",
            size: 4_000_000_000,
            isBundled: false
        )
    ]

    func loadModel(_ model: ModelInfo) async throws {
        let path = model.isBundled
            ? Bundle.main.path(forResource: model.filename, ofType: nil)!
            : getDownloadedModelPath(model)

        llamaContext = try LlamaContext(modelPath: path)
        currentModel = model
    }

    func downloadModel(_ model: ModelInfo) async throws {
        // Download with progress updates
    }
}
```

---

## 6. PhotoKit Integration

### 6.1 PhotoLibraryService

**Reuse from:** `/Users/tpiazza/git/FrogTeamMCP/PhotoOrganizerPro/PhotoOrganizerPro/Services/PhotoLibraryService.swift`

```swift
@MainActor
class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var totalPhotoCount: Int = 0

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
        }
        return status == .authorized || status == .limited
    }

    // MARK: - Fetching

    func getAllPhotoAssets() -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)

        let results = PHAsset.fetchAssets(with: fetchOptions)
        return results.objects(at: IndexSet(0..<results.count))
    }

    func getPhotoAssets(limit: Int?, offset: Int = 0) -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        if let limit = limit {
            fetchOptions.fetchLimit = offset + limit
        }

        let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let endIndex = min(offset + (limit ?? results.count), results.count)

        guard offset < endIndex else { return [] }
        return results.objects(at: IndexSet(offset..<endIndex))
    }

    // MARK: - Album Management

    func createAlbum(name: String, assetIdentifiers: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
            albumRequest.addAssets(assets)
        }
    }

    func addAssetsToAlbum(album: PHAssetCollection, assetIdentifiers: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else {
                throw PhotoLibraryError.failedToAddAssets
            }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
            albumChangeRequest.addAssets(assets)
        }
    }

    func deleteAlbum(_ album: PHAssetCollection) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSFastEnumeration)
        }
    }

    func getExistingAlbums() -> [PHAssetCollection] {
        let fetchOptions = PHFetchOptions()
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        return albums.objects(at: IndexSet(0..<albums.count))
    }

    // MARK: - Image Retrieval

    func requestImage(for asset: PHAsset, targetSize: CGSize) async throws -> NSImage {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.failedToLoadImage)
                }
            }
        }
    }
}

enum PhotoLibraryError: Error, LocalizedError {
    case accessDenied
    case failedToCreateAlbum
    case failedToAddAssets
    case failedToLoadImage
    case analysisError(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Photos access denied"
        case .failedToCreateAlbum: return "Failed to create album"
        case .failedToAddAssets: return "Failed to add photos to album"
        case .failedToLoadImage: return "Failed to load image"
        case .analysisError(let msg): return "Analysis error: \(msg)"
        }
    }
}
```

### 6.2 Photo Analysis Models

**Reuse from:** `/Users/tpiazza/git/FrogTeamMCP/PhotoOrganizerPro/PhotoOrganizerPro/Models/`

```swift
// PhotoAnalysis.swift
struct PhotoAnalysis: Codable, Identifiable {
    let id: UUID
    let assetIdentifier: String
    let timestamp: Date

    // LLM-generated description
    let description: String

    // Vision framework results
    let classifications: [ImageClassification]
    let detectedText: [String]
    let dominantColors: [String]
    let faces: [FaceDetection]

    // Computed categories
    let categories: [PhotoCategory]
    let semanticTags: [String]

    // Quality metrics
    let confidence: Float
}

struct ImageClassification: Codable {
    let identifier: String
    let confidence: Float
}

struct FaceDetection: Codable {
    let boundingBox: CGRect
    let confidence: Float
    let landmarks: [String: CGPoint]?
}

enum PhotoCategory: String, CaseIterable, Codable {
    case people
    case animals
    case nature
    case food
    case vehicles
    case architecture
    case events
    case activities
    case objects
    case documents
    case screenshots
}

// AlbumSuggestion.swift
struct AlbumSuggestion: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let assetIdentifiers: [String]
    let confidence: Float
    let category: AlbumCategory
    let creationDate: Date
    var isUserApproved: Bool = false
}

enum AlbumCategory: String, CaseIterable, Codable {
    case people
    case events
    case activities
    case locations
    case temporal
    case visual
    case custom
}
```

---

## 7. Chat Interface

### 7.1 Chat Window Design

```
┌─────────────────────────────────────────────────────────────────┐
│  VibrantFrog                                         ─  □  ×    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                                                             │ │
│  │  🐸 Hi! I can help you search and organize your photos.    │ │
│  │     What would you like to find?                           │ │
│  │                                                             │ │
│  │  👤 Show me photos from my beach vacation last summer      │ │
│  │                                                             │ │
│  │  🐸 Searching for beach vacation photos...                 │ │
│  │                                                             │ │
│  │     Found 47 photos:                                       │ │
│  │                                                             │ │
│  │     ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐     │ │
│  │     │       │ │       │ │       │ │       │ │       │     │ │
│  │     │  📷   │ │  📷   │ │  📷   │ │  📷   │ │  📷   │     │ │
│  │     │       │ │       │ │       │ │       │ │       │     │ │
│  │     └───────┘ └───────┘ └───────┘ └───────┘ └───────┘     │ │
│  │      Jun 15    Jun 15    Jun 16    Jun 16    Jun 17       │ │
│  │                                                             │ │
│  │     ┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐               │ │
│  │     │       │ │       │ │       │ │       │  +38 more     │ │
│  │     │  📷   │ │  📷   │ │  📷   │ │  📷   │               │ │
│  │     │       │ │       │ │       │ │       │               │ │
│  │     └───────┘ └───────┘ └───────┘ └───────┘               │ │
│  │                                                             │ │
│  │     Would you like me to create an album with these?       │ │
│  │                                                             │ │
│  │  👤 Yes, call it "Beach Vacation 2024"                     │ │
│  │                                                             │ │
│  │  🐸 ✓ Created album "Beach Vacation 2024" with 47 photos   │ │
│  │                                                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Ask me anything about your photos...                   [→] │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  Model: Phi-3 Vision ▼  │ 📊 18,432 indexed │ ⚙️ Extensions    │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Agent Implementation

```swift
@MainActor
class ChatAgent: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false

    private let llm: LlamaContext
    private let sdk: VibrantFrog

    private let systemPrompt = """
    You are VibrantFrog, a helpful assistant for managing photos in Apple Photos.

    You have access to these tools:
    - search_photos(query: String, limit: Int) -> [Photo]
    - create_album(name: String, photoIds: [String]) -> Album
    - add_to_album(albumName: String, photoIds: [String]) -> Bool
    - list_albums() -> [Album]
    - get_photo_info(photoId: String) -> PhotoInfo

    When users ask about photos, use search_photos to find relevant images.
    When they want to organize photos, offer to create albums.
    Be concise and helpful.

    To use a tool, respond with:
    <tool>tool_name</tool>
    <params>{"param": "value"}</params>
    """

    func send(_ message: String) async {
        messages.append(ChatMessage(role: .user, content: message))
        isProcessing = true

        defer { isProcessing = false }

        // Build conversation context
        let context = buildContext()

        // Get LLM response
        let response = try await llm.complete(prompt: context)

        // Parse for tool calls
        if let toolCall = parseToolCall(response) {
            let result = try await executeToolCall(toolCall)

            // Format response with results
            let formattedResponse = formatResponse(toolCall, result)
            messages.append(ChatMessage(role: .assistant, content: formattedResponse, toolResult: result))
        } else {
            messages.append(ChatMessage(role: .assistant, content: response))
        }
    }

    private func executeToolCall(_ call: ToolCall) async throws -> ToolResult {
        switch call.name {
        case "search_photos":
            let query = call.params["query"] as! String
            let limit = call.params["limit"] as? Int ?? 20
            let results = try await sdk.search(query, limit: limit)
            return .photos(results)

        case "create_album":
            let name = call.params["name"] as! String
            let photoIds = call.params["photoIds"] as! [String]
            let album = try await sdk.createAlbum(name: name, photoIds: photoIds)
            return .album(album)

        // ... other tools

        default:
            throw ToolError.unknownTool(call.name)
        }
    }
}
```

### 7.3 Menu Bar Interface

```swift
@main
struct VibrantFrogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main chat window
        WindowGroup {
            ChatView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 800)

        // Settings window
        Settings {
            SettingsView()
        }

        // Menu bar
        MenuBarExtra("VibrantFrog", systemImage: "photo.artframe") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var indexer: IndexerService
    @EnvironmentObject var mcpStatus: MCPStatusService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Circle()
                    .fill(mcpStatus.isRunning ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(mcpStatus.isRunning ? "MCP Server Running" : "MCP Server Off")
            }

            Divider()

            // Indexing progress
            VStack(alignment: .leading) {
                Text("Indexed: \(indexer.indexedCount) / \(indexer.totalCount)")
                if indexer.isIndexing {
                    ProgressView(value: indexer.progress)
                }
            }

            Divider()

            // Quick actions
            Button("🔍 Quick Search...") {
                NSApp.sendAction(#selector(AppDelegate.openSearch), to: nil, from: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("💬 Open Chat") {
                NSApp.sendAction(#selector(AppDelegate.openChat), to: nil, from: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("⚙️ Settings...") {
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("📦 Extensions...") {
                NSApp.sendAction(#selector(AppDelegate.openExtensions), to: nil, from: nil)
            }

            Divider()

            Button("Quit VibrantFrog") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 250)
    }
}
```

---

## 8. MCP Extension

### 8.1 MCP Helper App

Separate notarized app (not sandboxed) that:
- Runs MCP server on localhost:5050
- Modifies Claude Desktop config
- Uses shared VibrantFrog SDK

```
VibrantFrog MCP Helper.app/
├── Contents/
│   ├── MacOS/
│   │   └── VibrantFrog MCP Helper
│   ├── Frameworks/
│   │   └── VibrantFrogSDK.framework
│   ├── Resources/
│   │   └── mcp_server.py           # Python MCP server (bundled)
│   └── Info.plist
```

### 8.2 MCP Server Implementation

**Transport:** Streamable HTTP (SSE) for compatibility with Claude Desktop

```swift
// MCPServer.swift
import Vapor

class MCPServer {
    let app: Application
    let sdk: VibrantFrog

    init(sdk: VibrantFrog) throws {
        self.sdk = sdk
        self.app = Application(.development)

        configureRoutes()
    }

    private func configureRoutes() {
        // MCP endpoint with SSE
        app.post("mcp") { req async throws -> Response in
            let body = try req.content.decode(MCPRequest.self)

            let response = Response(status: .ok)
            response.headers.contentType = .init(type: "text", subType: "event-stream")

            response.body = .init(asyncStream: { writer in
                let result = try await self.handleRequest(body)
                let event = "data: \(result.toJSON())\n\n"
                try await writer.write(.buffer(ByteBuffer(string: event)))
                try await writer.write(.end)
            })

            return response
        }
    }

    private func handleRequest(_ request: MCPRequest) async throws -> MCPResponse {
        switch request.method {
        case "initialize":
            return MCPResponse(result: InitializeResult(
                protocolVersion: "1.0",
                capabilities: Capabilities(tools: true)
            ))

        case "tools/list":
            return MCPResponse(result: ToolsListResult(tools: availableTools))

        case "tools/call":
            let params = request.params as! ToolCallParams
            let result = try await executeToolCall(params)
            return MCPResponse(result: result)

        default:
            throw MCPError.unknownMethod(request.method)
        }
    }

    func start(port: Int = 5050) throws {
        app.http.server.configuration.port = port
        try app.start()
    }
}
```

### 8.3 Available MCP Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `search_photos` | Search by natural language | `query: string, limit?: number` |
| `get_photo` | Get photo details + thumbnail | `uuid: string` |
| `create_album` | Create new album | `name: string` |
| `delete_album` | Delete album | `name: string` |
| `list_albums` | List all albums | none |
| `create_album_from_search` | Search + create in one step | `name: string, query: string, limit?: number` |
| `add_photos_to_album` | Add photos to album | `album_name: string, photo_uuids: string[]` |
| `remove_photos_from_album` | Remove from album | `album_name: string, photo_uuids: string[]` |
| `get_library_stats` | Library statistics | none |

---

## 9. Claude Desktop Integration

### 9.1 One-Click Setup

The MCP Extension provides a "Configure Claude Desktop" button:

```swift
func configureClaudeDesktop() throws {
    let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")

    // Read existing config
    var config: [String: Any]
    if FileManager.default.fileExists(atPath: configPath.path) {
        let data = try Data(contentsOf: configPath)
        config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    } else {
        config = [:]
    }

    // Add VibrantFrog server
    var mcpServers = config["mcpServers"] as? [String: Any] ?? [:]
    mcpServers["vibrant-frog"] = [
        "transport": "streamable-http",
        "url": "http://localhost:5050/mcp"
    ]
    config["mcpServers"] = mcpServers

    // Write back
    let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
    try data.write(to: configPath)

    // Prompt to restart Claude Desktop
    showRestartPrompt()
}
```

### 9.2 Manual Configuration

For users who prefer manual setup:

```json
// ~/Library/Application Support/Claude/claude_desktop_config.json
{
  "mcpServers": {
    "vibrant-frog": {
      "transport": "streamable-http",
      "url": "http://localhost:5050/mcp"
    }
  }
}
```

---

## 10. Remote Access Extension

### 10.1 Cloudflare Tunnel Integration

```swift
class CloudflareManager: ObservableObject {
    @Published var tunnelURL: String?
    @Published var isRunning = false

    private var process: Process?

    func startTunnel() async throws {
        // Use cloudflared binary (bundled)
        let cloudflared = Bundle.main.path(forResource: "cloudflared", ofType: nil)!

        process = Process()
        process?.executableURL = URL(fileURLWithPath: cloudflared)
        process?.arguments = ["tunnel", "--url", "http://localhost:5050"]

        let pipe = Pipe()
        process?.standardOutput = pipe

        try process?.run()

        // Parse tunnel URL from output
        for try await line in pipe.fileHandleForReading.bytes.lines {
            if line.contains("trycloudflare.com") {
                tunnelURL = extractURL(from: line)
                isRunning = true
                break
            }
        }
    }

    func stopTunnel() {
        process?.terminate()
        isRunning = false
        tunnelURL = nil
    }
}
```

### 10.2 Authentication

When remote access is enabled, require bearer token:

```swift
// MCPServer.swift
app.grouped(AuthMiddleware()).post("mcp") { req in
    // ... handle request
}

struct AuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token,
              token == Settings.shared.authToken else {
            throw Abort(.unauthorized)
        }
        return try await next.respond(to: request)
    }
}
```

### 10.3 Remote Claude Desktop Config

```json
{
  "mcpServers": {
    "vibrant-frog-remote": {
      "transport": "streamable-http",
      "url": "https://random-words.trycloudflare.com/mcp",
      "headers": {
        "Authorization": "Bearer your-auth-token-here"
      }
    }
  }
}
```

---

## 11. Data Storage & Privacy

### 11.1 Storage Locations

| Data | Location | Sandboxed |
|------|----------|-----------|
| Photo embeddings | `~/Library/Containers/com.vibrantfrog.app/Data/embeddings.db` | ✅ |
| Analysis cache | `~/Library/Containers/com.vibrantfrog.app/Data/analysis/` | ✅ |
| Settings | `~/Library/Containers/com.vibrantfrog.app/Data/settings.json` | ✅ |
| Downloaded models | `~/Library/Containers/com.vibrantfrog.app/Data/models/` | ✅ |
| Extension data | `~/Library/Application Support/VibrantFrog/` | ❌ (extensions) |

### 11.2 Privacy Principles

1. **All AI processing is local** - No cloud APIs
2. **Photos never leave device** - Only embeddings stored
3. **No telemetry** - Zero analytics or tracking
4. **User controls data** - Easy deletion from Settings
5. **Transparent storage** - Can inspect all stored data

### 11.3 App Privacy Labels (App Store)

- **Data Not Collected** - We don't collect any data
- **Data Not Linked to You** - No user identification
- **Data Used to Track You** - None

---

## 12. Monetization Strategy

### 12.1 Options

| Model | App Store | Extensions | Revenue |
|-------|-----------|------------|---------|
| **Free + Free Extensions** | Free | Free (Open Source) | None (hobby) |
| **Paid App** | $9.99 | Free | One-time purchase |
| **Free + Paid Extensions** | Free | $4.99 each | Extension sales |
| **Freemium** | Free (1K photos) | Full unlock $9.99 | In-app purchase |
| **Subscription** | Free | $2.99/month | Recurring |

### 12.2 Recommended: Freemium

- **Free tier**: 1,000 photo index limit, basic search, 3 albums
- **Pro ($9.99 one-time)**: Unlimited photos, all features
- **Extensions**: Always free (open source community)

---

## 13. Development Roadmap

### Phase 1: Core App (v1.0) - 8 weeks

- [ ] Swift project setup with VibrantFrogSDK
- [ ] PhotoKit integration (PhotoLibraryService)
- [ ] Embedded llama.cpp with Phi-3 Vision
- [ ] SQLite embedding storage
- [ ] Basic chat interface
- [ ] Menu bar app
- [ ] Background indexing
- [ ] App Store submission

### Phase 2: Extensions (v1.1) - 4 weeks

- [ ] MCP Helper app
- [ ] Streamable HTTP server
- [ ] Claude Desktop auto-config
- [ ] Extension discovery UI

### Phase 3: Face Recognition (v1.2) - 4 weeks

- [ ] Face detection (Vision framework or InsightFace)
- [ ] Face clustering
- [ ] Person labeling UI
- [ ] "Photos with [person]" search

### Phase 4: Remote Access (v1.3) - 2 weeks

- [ ] Cloudflare Tunnel integration
- [ ] Authentication system
- [ ] Remote MCP documentation

### Phase 5: Polish & Marketing (v2.0) - 4 weeks

- [ ] Performance optimization
- [ ] Additional models
- [ ] Marketing website
- [ ] Tutorial videos
- [ ] App Store optimization

---

## 14. Technical Implementation

### 14.1 Build System

```bash
# Xcode project with SPM dependencies
VibrantFrog.xcodeproj
├── VibrantFrog (macOS app target)
├── VibrantFrogSDK (framework target)
├── VibrantFrog MCP Helper (separate app target)
└── VibrantFrogTests
```

### 14.2 Dependencies

**Swift Packages:**
- llama.cpp (local path or SPM)
- SQLite.swift (embedding storage)
- Sparkle (auto-updates for extensions)

**No external runtime dependencies** - Everything bundled.

### 14.3 Code Signing

```bash
# Main app (App Store)
codesign --sign "3rd Party Mac Developer Application: ..." \
    --entitlements VibrantFrog.entitlements \
    VibrantFrog.app

# Extensions (Developer ID)
codesign --sign "Developer ID Application: ..." \
    --options runtime \
    "VibrantFrog MCP Helper.app"

# Notarize extensions
xcrun notarytool submit "VibrantFrog MCP Helper.dmg" ...
```

---

## 15. Reusable Code Reference

### 15.1 Direct Copy (90%+ reusable)

| File | Source | Lines | Purpose |
|------|--------|-------|---------|
| PhotoLibraryService.swift | PhotoOrganizerPro | ~230 | Photo/album access |
| AlbumGenerationService.swift | PhotoOrganizerPro | ~615 | Album generation |
| PhotoAnalysis.swift | PhotoOrganizerPro | ~90 | Data model |
| AlbumSuggestion.swift | PhotoOrganizerPro | ~110 | Data model |
| VisionAnalysisService.swift | PhotoOrganizerPro | ~200 | Vision framework |

### 15.2 Template/Adapt (70% reusable)

| File | Source | Purpose |
|------|--------|---------|
| LlamaState.swift | llama.cpp/examples | Observable LLM state |
| LibLlama.swift | llama.cpp/examples | llama.cpp Swift bindings |
| MCPClientImplementation.swift | FrogTeamMCP | MCP protocol patterns |
| LocalTools.swift | FrogTeamMCP | Tool registry pattern |

### 15.3 Reference (Architecture patterns)

| File | Source | Purpose |
|------|--------|---------|
| vibrant_frog_mcp.py | VibrantFrogMCP | MCP tool definitions |
| index_photos.py | VibrantFrogMCP | Indexing workflow |
| album_manager.py | VibrantFrogMCP | Album operations |

### 15.4 Pre-built Assets

| Asset | Location | Notes |
|-------|----------|-------|
| llama.xcframework | FrogTeamMCP/llama.xcframework | macOS Universal slice ready |

---

## Appendix A: File Paths Quick Reference

```
# Reusable Services
/Users/tpiazza/git/FrogTeamMCP/PhotoOrganizerPro/PhotoOrganizerPro/Services/PhotoLibraryService.swift
/Users/tpiazza/git/FrogTeamMCP/PhotoOrganizerPro/PhotoOrganizerPro/Services/AlbumGenerationService.swift
/Users/tpiazza/git/FrogTeamMCP/PhotoOrganizerPro/PhotoOrganizerPro/Services/VisionAnalysisService.swift

# Reusable Models
/Users/tpiazza/git/FrogTeamMCP/PhotoOrganizerPro/PhotoOrganizerPro/Models/PhotoAnalysis.swift
/Users/tpiazza/git/FrogTeamMCP/PhotoOrganizerPro/PhotoOrganizerPro/Models/AlbumSuggestion.swift

# LLM Integration
/Users/tpiazza/git/llama.cpp/examples/llama.swiftui/llama.swiftui/Models/LlamaState.swift
/Users/tpiazza/git/llama.cpp/examples/llama.swiftui/llama.swiftui/LibLlama.swift
/Users/tpiazza/git/FrogTeamMCP/llama.xcframework/

# MCP Patterns
/Users/tpiazza/git/FrogTeamMCP/FrogTeamMCP/MCPClientImplementation.swift
/Users/tpiazza/git/FrogTeamMCP/FrogTeamMCP/MCPProtocol.swift
/Users/tpiazza/git/FrogTeamMCP/FrogTeamMCP/LocalTools.swift

# Python MCP Server (reference)
/Users/tpiazza/git/VibrantFrogMCP/vibrant_frog_mcp.py
/Users/tpiazza/git/VibrantFrogMCP/album_manager.py
/Users/tpiazza/git/VibrantFrogMCP/photo_retrieval.py
```

---

## Appendix B: App Store Checklist

- [ ] Sandbox enabled
- [ ] Only Photos entitlement
- [ ] No network entitlements (not needed for core)
- [ ] Privacy labels configured
- [ ] Screenshots (5 required)
- [ ] App preview video
- [ ] Description and keywords
- [ ] Support URL
- [ ] Privacy policy URL
- [ ] Age rating
- [ ] Price tier

---

*Document Version: 2.0 Draft*
*Last Updated: 2025-11-23*
