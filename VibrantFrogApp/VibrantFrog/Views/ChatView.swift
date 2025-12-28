//
//  ChatView.swift
//  VibrantFrog
//
//  Chat interface for interacting with photos via MCP tools
//

import SwiftUI
import Photos

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date
    var toolResult: ToolResult?

    enum MessageRole {
        case user
        case assistant
        case system
    }

    struct ToolResult: Equatable {
        let toolName: String
        let photos: [PhotoResult]?
        let albums: [String]?
        let text: String?

        struct PhotoResult: Equatable, Identifiable {
            let id = UUID()
            let uuid: String
            let filename: String
            let description: String
            let relevance: Double
        }
    }
}

enum ChatError: LocalizedError {
    case noResults
    case toolFailed
    case imageFetchFailed

    var errorDescription: String? {
        switch self {
        case .noResults:
            return "No results found"
        case .toolFailed:
            return "Tool execution failed"
        case .imageFetchFailed:
            return "Failed to fetch image"
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var mcpClient: MCPClientHTTP
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if isProcessing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                TextField("Ask about your photos...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isInputFocused)
                    .onSubmit {
                        Task {
                            await sendMessage()
                        }
                    }
                    .disabled(isProcessing || !mcpClient.isConnected)

                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.isEmpty || !mcpClient.isConnected ? .secondary : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isProcessing || !mcpClient.isConnected)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            // Connection status
            if !mcpClient.isConnected {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Not connected to MCP server")
                    Button("Connect") {
                        Task {
                            try? await mcpClient.connect()
                        }
                    }
                }
                .font(.caption)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }
        }
        .navigationTitle("Chat")
        .onAppear {
            // Add welcome message on first load
            if messages.isEmpty {
                messages.append(ChatMessage(
                    role: .system,
                    content: "Welcome to VibrantFrog! I can help you search and organize your photos. Try asking me to:\n\n• Search for photos (e.g., \"show me beach photos\")\n• Create albums (e.g., \"create an album from sunset photos\")\n• List your albums\n• Get photo details",
                    timestamp: Date()
                ))
            }

            // Auto-connect if not connected
            if !mcpClient.isConnected {
                Task {
                    try? await mcpClient.connect()
                }
            }

            isInputFocused = true
        }
    }

    // MARK: - Message Handling

    private func sendMessage() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = inputText
        inputText = ""

        // Add user message
        messages.append(ChatMessage(
            role: .user,
            content: userMessage,
            timestamp: Date()
        ))

        isProcessing = true
        errorMessage = nil

        defer {
            isProcessing = false
        }

        do {
            // Simple intent detection
            let intent = detectIntent(userMessage)
            let response = try await handleIntent(intent, query: userMessage)

            messages.append(response)

        } catch {
            errorMessage = error.localizedDescription
            messages.append(ChatMessage(
                role: .assistant,
                content: "I encountered an error: \(error.localizedDescription)",
                timestamp: Date()
            ))
        }
    }

    private func detectIntent(_ message: String) -> Intent {
        let lower = message.lowercased()

        if lower.contains("search") || lower.contains("find") || lower.contains("show me") {
            return .search
        } else if lower.contains("create album") || lower.contains("make album") {
            return .createAlbum
        } else if lower.contains("list album") || lower.contains("show album") || lower.contains("my albums") {
            return .listAlbums
        } else if lower.contains("help") {
            return .help
        } else {
            // Default to search
            return .search
        }
    }

    private func handleIntent(_ intent: Intent, query: String) async throws -> ChatMessage {
        switch intent {
        case .search:
            return try await performSearch(query: query)

        case .createAlbum:
            return try await createAlbumFromSearch(query: query)

        case .listAlbums:
            return try await listAlbums()

        case .help:
            return ChatMessage(
                role: .assistant,
                content: """
                I can help you with:

                📸 **Search Photos**
                "Show me beach photos"
                "Find sunset pictures"
                "Search for dogs"

                📁 **Create Albums**
                "Create an album from beach photos"
                "Make an album of sunset pictures"

                📋 **List Albums**
                "List my albums"
                "Show all albums"

                Just ask naturally and I'll do my best to help!
                """,
                timestamp: Date()
            )
        }
    }

    private func performSearch(query: String) async throws -> ChatMessage {
        // Extract search terms from query
        let searchTerms = extractSearchTerms(from: query)

        // Call MCP search_photos tool
        let result = try await mcpClient.callTool(
            name: "search_photos",
            arguments: [
                "query": searchTerms,
                "n_results": 10
            ]
        )

        // Parse results
        guard let textContent = result.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw ChatError.noResults
        }

        // DEBUG: Print the raw text
        print("=== SEARCH RESULTS RAW TEXT ===")
        print(text)
        print("=== END RAW TEXT ===")

        // Parse photo results from text
        let photos = parseSearchResults(text)

        // DEBUG: Print parsed photos
        print("=== PARSED PHOTOS ===")
        print("Found \(photos.count) photos")
        for photo in photos.prefix(3) {
            print("  UUID: \(photo.uuid)")
            print("  Filename: \(photo.filename)")
            print("  Relevance: \(photo.relevance)")
        }
        print("=== END PARSED ===")


        let toolResult = ChatMessage.ToolResult(
            toolName: "search_photos",
            photos: photos,
            albums: nil,
            text: text
        )

        let responseText = if photos.isEmpty {
            "I couldn't find any photos matching '\(searchTerms)'. Try a different search term."
        } else {
            "I found \(photos.count) photos matching '\(searchTerms)':"
        }

        return ChatMessage(
            role: .assistant,
            content: responseText,
            timestamp: Date(),
            toolResult: toolResult
        )
    }

    private func createAlbumFromSearch(query: String) async throws -> ChatMessage {
        // Extract album name and search terms
        let (albumName, searchTerms) = extractAlbumNameAndSearch(from: query)

        // Call MCP create_album_from_search tool
        let result = try await mcpClient.callTool(
            name: "create_album_from_search",
            arguments: [
                "album_name": albumName,
                "search_query": searchTerms,
                "limit": 50
            ]
        )

        guard let textContent = result.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw ChatError.toolFailed
        }

        return ChatMessage(
            role: .assistant,
            content: "✓ \(text)",
            timestamp: Date()
        )
    }

    private func listAlbums() async throws -> ChatMessage {
        // Call MCP list_albums tool
        let result = try await mcpClient.callTool(
            name: "list_albums",
            arguments: [:]
        )

        guard let textContent = result.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw ChatError.toolFailed
        }

        // Parse album names
        let albumNames = parseAlbumList(text)

        let toolResult = ChatMessage.ToolResult(
            toolName: "list_albums",
            photos: nil,
            albums: albumNames,
            text: text
        )

        return ChatMessage(
            role: .assistant,
            content: text,
            timestamp: Date(),
            toolResult: toolResult
        )
    }

    // MARK: - Helper Methods

    private func extractSearchTerms(from query: String) -> String {
        let lower = query.lowercased()

        // Remove common prefixes
        let terms = lower
            .replacingOccurrences(of: "show me ", with: "")
            .replacingOccurrences(of: "find ", with: "")
            .replacingOccurrences(of: "search for ", with: "")
            .replacingOccurrences(of: "search ", with: "")
            .replacingOccurrences(of: "photos of ", with: "")
            .replacingOccurrences(of: "pictures of ", with: "")
            .replacingOccurrences(of: "images of ", with: "")

        return terms.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractAlbumNameAndSearch(from query: String) -> (String, String) {
        let lower = query.lowercased()

        // Try to extract album name from patterns like "create an album called X from Y"
        if let range = lower.range(of: "called ") ?? lower.range(of: "named ") {
            let afterCalled = String(lower[range.upperBound...])
            if let fromRange = afterCalled.range(of: " from ") {
                let albumName = String(afterCalled[..<fromRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let searchTerms = String(afterCalled[fromRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (albumName, searchTerms)
            }
        }

        // Default: extract search terms and generate name
        let searchTerms = extractSearchTerms(from: query)
        let albumName = searchTerms.capitalized + " Album"
        return (albumName, searchTerms)
    }

    private func parseSearchResults(_ text: String) -> [ChatMessage.ToolResult.PhotoResult] {
        var photos: [ChatMessage.ToolResult.PhotoResult] = []

        // Parse the text format from search_photos tool
        let lines = text.split(separator: "\n")

        // Accumulate fields for current photo
        var uuid = ""
        var filename = ""
        var description = ""
        var relevance = 0.0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.starts(with: "UUID:") {
                uuid = String(trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces))
            } else if trimmed.starts(with: "Description:") {
                description = String(trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces))
            } else if trimmed.starts(with: "Relevance:") {
                if let relevanceStr = trimmed.split(separator: ":").last,
                   let rel = Double(relevanceStr.trimmingCharacters(in: .whitespaces)) {
                    relevance = rel

                    // All fields collected, create PhotoResult
                    // Allow missing filename - use UUID as fallback
                    if !uuid.isEmpty {
                        photos.append(ChatMessage.ToolResult.PhotoResult(
                            uuid: uuid,
                            filename: filename.isEmpty ? "Photo \(uuid.prefix(8))" : filename,
                            description: description,
                            relevance: relevance
                        ))
                    }

                    // Reset for next photo
                    uuid = ""
                    filename = ""
                    description = ""
                    relevance = 0.0
                }
            } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                // This is a numbered line like "1. photo.jpg"
                // Extract filename after "1. "
                filename = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        return photos
    }

    private func parseAlbumList(_ text: String) -> [String] {
        let lines = text.split(separator: "\n")
        return lines
            .filter { $0.trimmingCharacters(in: .whitespaces).starts(with: "-") }
            .map { String($0.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces)) }
    }

    enum Intent {
        case search
        case createAlbum
        case listAlbums
        case help
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(message.role == .user ? .blue : .green)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 8) {
                // Message content
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)

                // Tool results
                if let toolResult = message.toolResult {
                    ToolResultView(toolResult: toolResult)
                }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ToolResultView: View {
    let toolResult: ChatMessage.ToolResult
    @State private var loadedImages: [String: NSImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Photos grid
            if let photos = toolResult.photos, !photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(photos.prefix(12)) { photo in
                        ChatPhotoThumbnail(photo: photo)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)

                if photos.count > 12 {
                    Text("+ \(photos.count - 12) more photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Albums list
            if let albums = toolResult.albums, !albums.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(albums.prefix(10), id: \.self) { album in
                        HStack {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                            Text(album)
                                .font(.body)
                        }
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
}

struct ChatPhotoThumbnail: View {
    let photo: ChatMessage.ToolResult.PhotoResult
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Thumbnail
            Group {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if isLoading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .onTapGesture {
                openInPhotos()
            }
            .help("Click to open in Photos")

            // Filename
            Text(photo.filename)
                .font(.caption2)
                .lineLimit(1)

            // Relevance score
            if photo.relevance > 0 {
                Text(String(format: "%.0f%%", photo.relevance * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        isLoading = true
        defer { isLoading = false }

        // Use PhotoKit to load the photo
        guard !photo.uuid.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photo.uuid], options: nil)
        guard let asset = fetchResult.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if let image = image {
                    self.image = image
                }
                continuation.resume()
            }
        }
    }

    private func openInPhotos() {
        guard !photo.uuid.isEmpty else { return }

        // Open photo in Photos.app using the photos:// URL scheme
        if let url = URL(string: "photos://asset?uuid=\(photo.uuid)") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(MCPClientHTTP())
        .frame(width: 600, height: 800)
}
