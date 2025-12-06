# Chat Interface Implementation Guide

## What Was Added

✅ **ChatView.swift** - Complete chat interface with MCP integration

### Features Implemented:

1. **Chat Interface**
   - Message bubbles for user/assistant/system messages
   - Scrollable conversation history
   - Text input with send button
   - Auto-scroll to latest message

2. **Natural Language Understanding**
   - Intent detection (search, create album, list albums, help)
   - Query parsing to extract search terms and album names
   - Flexible command understanding

3. **MCP Tool Integration**
   - **search_photos** - Search for photos by query
   - **create_album_from_search** - Create album from search results
   - **list_albums** - List all Apple Photos albums

4. **Rich Result Display**
   - Photo grid preview (up to 6 photos)
   - Album list display
   - Relevance scores
   - Tool execution feedback

5. **Connection Management**
   - Auto-connect to MCP server on launch
   - Connection status indicator
   - Reconnect button when disconnected

---

## How to Use

### 1. Start the MCP Server

```bash
cd /Users/tpiazza/git/VibrantFrogMCP
./restart_http_server.sh
```

Server will start on `http://127.0.0.1:5050`

### 2. Open VibrantFrog App in Xcode

```bash
cd VibrantFrogApp
open VibrantFrog.xcodeproj
```

### 3. Run the App

Click the Run button (or Cmd+R) in Xcode

### 4. Use the Chat

The chat interface will automatically:
- Connect to the MCP server
- Show a welcome message
- Be ready for your queries

---

## Example Conversations

### Search for Photos

**User:** "Show me beach photos"

**Assistant:** "I found 12 photos matching 'beach':"
[Photo grid with thumbnails]

### Create an Album

**User:** "Create an album called Summer 2024 from beach photos"

**Assistant:** "✓ Created album 'Summer 2024' with 12 photos"

### List Albums

**User:** "List my albums"

**Assistant:** "Found 25 albums:"
- Summer 2024
- Vacation Photos
- Family Events
- ...

### Get Help

**User:** "help"

**Assistant:** Shows list of available commands

---

## Architecture

```
ChatView
    │
    ├─ ChatViewModel (ObservableObject)
    │    │
    │    ├─ MCPClientHTTP (connection to Python server)
    │    │
    │    ├─ Intent Detection
    │    │   ├─ .search → search_photos tool
    │    │   ├─ .createAlbum → create_album_from_search tool
    │    │   ├─ .listAlbums → list_albums tool
    │    │   └─ .help → Show help message
    │    │
    │    └─ Message Management
    │        ├─ User messages
    │        ├─ Assistant responses
    │        └─ Tool results
    │
    ├─ MessageBubble (Display component)
    │   ├─ Avatar (user/assistant icon)
    │   ├─ Text content
    │   ├─ ToolResultView (if applicable)
    │   └─ Timestamp
    │
    └─ Input Area
        ├─ TextField
        ├─ Send button
        └─ Connection status
```

---

## Current Limitations & Next Steps

### Currently Implemented ✅

- [x] Search photos via natural language
- [x] Create albums from search queries
- [x] List albums
- [x] Parse tool results
- [x] Display photo metadata
- [x] Connection management

### Not Yet Implemented 🔲

- [ ] **Photo thumbnails** - Currently showing placeholder icons
- [ ] **get_photo tool** - Retrieve and display actual images
- [ ] **Conversation history** - Save/restore chat sessions
- [ ] **More tools** - add_photos_to_album, remove_photos, etc.
- [ ] **Streaming responses** - Currently waits for full response
- [ ] **Error recovery** - Better error handling and retry

---

## Adding Photo Thumbnails

To show actual photo thumbnails instead of placeholders:

### 1. Implement Photo Fetching

Add to ChatViewModel:

```swift
func fetchPhotoThumbnail(uuid: String) async throws -> NSImage {
    let result = try await mcpClient.callTool(
        name: "get_photo",
        arguments: ["uuid": uuid]
    )

    // Extract image data from result
    guard let imageContent = result.content.first(where: { $0.type == "image" }),
          let imageData = imageContent.data,
          let data = Data(base64Encoded: imageData),
          let image = NSImage(data: data) else {
        throw ChatError.imageFetchFailed
    }

    return image
}
```

### 2. Update PhotoResult Model

```swift
struct PhotoResult: Equatable, Identifiable {
    let id = UUID()
    let uuid: String
    let filename: String
    let description: String
    let relevance: Double
    var thumbnail: NSImage? = nil  // Add this
}
```

### 3. Load Thumbnails Asynchronously

In ToolResultView:

```swift
AsyncImage(uuid: photo.uuid) { phase in
    switch phase {
    case .success(let image):
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
    case .failure:
        Image(systemName: "photo")
    case .empty:
        ProgressView()
    @unknown default:
        EmptyView()
    }
}
.frame(width: 100, height: 100)
.clipShape(RoundedRectangle(cornerRadius: 8))
```

---

## Adding More Intents

To add support for more commands:

### 1. Add Intent Type

```swift
enum Intent {
    case search
    case createAlbum
    case listAlbums
    case addToAlbum      // NEW
    case deleteAlbum     // NEW
    case help
}
```

### 2. Update Intent Detection

```swift
private func detectIntent(_ message: String) -> Intent {
    let lower = message.lowercased()

    if lower.contains("add") && lower.contains("to album") {
        return .addToAlbum
    } else if lower.contains("delete album") {
        return .deleteAlbum
    }
    // ... existing cases
}
```

### 3. Implement Handler

```swift
case .addToAlbum:
    return try await addPhotosToAlbum(query: query)

private func addPhotosToAlbum(query: String) async throws -> ChatMessage {
    // Parse album name and photo UUIDs from query
    let (albumName, photoUUIDs) = extractAlbumAndPhotos(from: query)

    let result = try await mcpClient.callTool(
        name: "add_photos_to_album",
        arguments: [
            "album_name": albumName,
            "photo_uuids": photoUUIDs
        ]
    )

    // ... handle result
}
```

---

## Testing Checklist

- [ ] Server starts successfully
- [ ] App connects to server on launch
- [ ] Search queries return results
- [ ] Album creation works
- [ ] Album listing works
- [ ] Error messages display properly
- [ ] Reconnect works after server restart
- [ ] Messages scroll automatically
- [ ] Input field clears after sending

---

## Troubleshooting

### "Not connected to MCP server"

**Fix:**
1. Make sure server is running: `./restart_http_server.sh`
2. Check server URL in MCPClientHTTP.swift (should be `http://127.0.0.1:5050`)
3. Click "Connect" button in chat

### "Tool execution failed"

**Fix:**
1. Check server logs: `tail -f /tmp/mcp_server.log`
2. Verify ChromaDB index exists
3. Ensure photos are indexed: `python test_mcp_http.py`

### No search results

**Fix:**
1. Index some photos first (run indexing from Python)
2. Check ChromaDB database exists at `~/Library/Application Support/VibrantFrogMCP/photo_index`

### App won't build

**Fix:**
1. Make sure ChatView.swift is added to Xcode project
2. Check all imports are correct
3. Clean build folder: Product → Clean Build Folder

---

## Next Phase: Photo Display

Once you test the basic chat, the next step is:

1. Implement `get_photo` tool integration
2. Add photo thumbnail loading
3. Create a photo detail view
4. Add click handlers to open photos in Apple Photos

See the "Adding Photo Thumbnails" section above for implementation details.

---

**Status:** Chat interface ready for testing! 🎉

Start the server with `./restart_http_server.sh` and run the app.
