# Native Thumbnail Implementation Plan

## Problem
Llama3.2 can't properly handle photo URIs. Empty image boxes appear because the LLM doesn't know how to construct proper `photos://` URLs.

## Solution
Use native Swift PhotoKit to load thumbnails after MCP search_photos returns UUIDs.

## Implementation Status

### ✅ Completed
1. Added `loadThumbnailByUUID()` to PhotoLibraryService
2. Added `loadThumbnailsByUUIDs()` for batch loading
3. Added PhotoThumbnail model to AIChatMessage
4. Added photoService to AIChatViewModel

### 🔄 Next Steps

#### 1. Parse UUIDs from MCP search results
In `executeToolCalls()` after line 357, add:

```swift
// If this was a search_photos call, parse UUIDs and load thumbnails
if toolName == "search_photos" {
    let uuids = parseUUIDs(from: textContent)
    if !uuids.isEmpty, let photoService = photoService {
        print("📸 Loading \(uuids.count) thumbnails...")
        let thumbnails = await photoService.loadThumbnailsByUUIDs(uuids)

        // Update the last message with thumbnails
        if var lastMessage = messages.last, lastMessage.role == .tool {
            messages.removeLast()
            var photoThumbs: [PhotoThumbnail] = []
            for uuid in uuids {
                photoThumbs.append(PhotoThumbnail(
                    uuid: uuid,
                    image: thumbnails[uuid],
                    description: extractDescription(for: uuid, from: textContent)
                ))
            }
            messages.append(AIChatMessage(
                role: .tool,
                content: textContent,
                timestamp: lastMessage.timestamp,
                toolName: toolName,
                photoThumbnails: photoThumbs
            ))
        }
    }
}
```

#### 2. Add UUID parsing helper

```swift
private func parseUUIDs(from text: String) -> [String] {
    var uuids: [String] = []
    let lines = text.split(separator: "\n")

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.starts(with: "UUID:") {
            let uuid = String(trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces))
            if !uuid.isEmpty {
                uuids.append(uuid)
            }
        }
    }

    return uuids
}

private func extractDescription(for uuid: String, from text: String) -> String? {
    // Parse description from MCP result text
    // Format: UUID: xxx\nDescription: yyy\nRelevance: zzz
    let lines = text.split(separator: "\n")
    var foundUUID = false

    for i in 0..<lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.starts(with: "UUID:") && line.contains(uuid) {
            foundUUID = true
        } else if foundUUID && line.starts(with: "Description:") {
            return String(line.dropFirst(12).trimmingCharacters(in: .whitespaces))
        } else if foundUUID && line.starts(with: "Relevance:") {
            break  // End of this photo's info
        }
    }

    return nil
}
```

#### 3. Update MessageView to display thumbnails

In MessageView.swift around line 403, after the content text, add:

```swift
// Photo thumbnails grid
if let thumbnails = message.photoThumbnails, !thumbnails.isEmpty {
    LazyVGrid(columns: [
        GridItem(.adaptive(minimum: 150, maximum: 200))
    ], spacing: 12) {
        ForEach(thumbnails) { thumb in
            VStack(alignment: .leading, spacing: 4) {
                if let image = thumb.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipped()
                        .cornerRadius(8)
                        .onTapGesture {
                            openPhoto(uuid: thumb.uuid)
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 150)
                        .cornerRadius(8)
                        .overlay(
                            ProgressView()
                        )
                }

                if let desc = thumb.description {
                    Text(desc)
                        .font(.caption2)
                        .lineLimit(2)
                }
            }
        }
    }
    .padding(.top, 8)
}

// Helper function
private func openPhoto(uuid: String) {
    let url = URL(string: "photos://asset?uuid=\(uuid)")!
    NSWorkspace.shared.open(url)
}
```

## How It Works

1. User asks: "Show me beach photos"
2. Llama3.2 calls `search_photos(query="beach")`
3. MCP server returns text with UUIDs:
   ```
   UUID: ABC-123
   Description: Beautiful beach sunset
   Relevance: 0.92

   UUID: DEF-456
   Description: Sandy beach with waves
   Relevance: 0.85
   ```
4. We parse UUIDs: `["ABC-123", "DEF-456"]`
5. Call `photoService.loadThumbnailsByUUIDs()`
6. PhotoKit loads actual NSImage thumbnails
7. Display in chat with clickable thumbnails
8. Click → opens in Photos.app

## Benefits

- No need for LLM to understand photo URIs
- Native PhotoKit = reliable thumbnail loading
- Works with iCloud photos (auto-downloads)
- Clickable to open in Photos.app
- Descriptions from MCP search included

## Files to Modify

1. `VibrantFrog/Views/AIChatView.swift`:
   - Add parseUUIDs() helper (line ~370)
   - Add extractDescription() helper
   - Update executeToolCalls() to load thumbnails after search_photos
   - Update MessageView to display photo grid

## Testing

After implementation:
1. Run app
2. Ask: "Show me beach photos"
3. Should see:
   - Tool call message
   - Grid of actual photo thumbnails (not empty boxes!)
   - Click thumbnail → opens in Photos.app
   - Assistant summary: "I found X beach photos"

This completely bypasses the URI issue by using native Swift!
