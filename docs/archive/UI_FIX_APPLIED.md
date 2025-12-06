# UI Update Fix - Ollama Availability

## Problem Identified

**Console showed:** ✅ OllamaService: Ollama is AVAILABLE
**UI showed:** "Ollama not available" (text box disabled)

**Root Cause:** Nested ObservableObject issue in SwiftUI

## The Issue

In `AIChatView.swift`:
- `AIChatViewModel` is an `@StateObject` (observed by the view)
- `OllamaService` is `@Published` inside the ViewModel
- `OllamaService` is also an `ObservableObject`

**Problem:** SwiftUI doesn't automatically propagate changes from nested ObservableObjects up to parent views. When `OllamaService.isAvailable` changed from `false` to `true`, the `AIChatViewModel` didn't notify the view to re-render.

## The Fix

Added Combine subscription in `AIChatViewModel.init()` to forward changes:

```swift
import Combine  // Added at top

@MainActor
class AIChatViewModel: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var ollamaService = OllamaService()

    private var mcpClient: MCPClientHTTP?
    private var conversationHistory: [OllamaService.ChatMessage] = []
    private var cancellables = Set<AnyCancellable>()  // NEW

    init() {
        // Forward changes from ollamaService to this ViewModel
        ollamaService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    // ... rest of code
}
```

**How it works:**
1. When `OllamaService` changes (e.g., `isAvailable = true`)
2. It fires `objectWillChange` event
3. Our sink catches that event
4. Forwards it to `AIChatViewModel.objectWillChange`
5. SwiftUI sees ViewModel changed → re-renders view
6. UI now shows correct state

## Files Changed

### VibrantFrog/Views/AIChatView.swift
**Lines 10:** Added `import Combine`
**Lines 148-155:** Added init() with objectWillChange forwarding
**Lines 114-116:** Added manual checkAvailability() call in onAppear (defensive)

### VibrantFrog/Services/OllamaService.swift
**Lines 89-93:** Added explicit MainActor.run for isAvailable update (defensive, may not be needed)

## Test Now

1. **Run the app** (Cmd+R in Xcode)
2. **Look for console output:**
   ```
   ✅ OllamaService: Ollama is AVAILABLE (isAvailable set to true)
   ```
3. **Check the UI:**
   - Should show model selector with "mistral:latest"
   - Text box should be ENABLED
   - "Ollama not available" should be GONE

4. **Try natural language search:**
   - Type: "Show me beach photos"
   - Press Enter
   - LLM should call `search_photos` tool
   - Results should appear with thumbnails

## Expected Behavior

### Before Fix:
```
Console: ✅ Ollama is AVAILABLE
UI:      ❌ Ollama not available (disabled)
```

### After Fix:
```
Console: ✅ Ollama is AVAILABLE (isAvailable set to true)
UI:      ✅ Model selector active, text box enabled
```

## Why This Matters

Without this fix, the entire AI chat feature was unusable because:
1. Ollama was working fine (proven by console logs)
2. UI thought it wasn't available
3. Text box was disabled
4. User couldn't send messages to LLM

Now the UI correctly reflects the actual Ollama state, enabling the full AI chat + MCP tool calling workflow.

## Next: Test Tool Calling

Once UI shows Ollama available, test the full workflow:

1. **Ask:** "Show me beach photos"
2. **Expected flow:**
   - User message appears in chat
   - "Thinking..." spinner appears
   - Tool call message: "Called search_photos"
   - Tool result shows photo UUIDs
   - Assistant message: "I found X beach photos for you!"
   - Photo thumbnails appear
3. **Check console for:**
   ```
   🔧 Calling MCP tool: search_photos with args: ["query": "beach", "n_results": 10]
   ```

## Build Status

✅ **BUILD SUCCEEDED**
✅ All files updated correctly
✅ No compilation errors
✅ Ready to run

---

**The fix is complete. Please run the app and verify the UI now shows Ollama as available!**
