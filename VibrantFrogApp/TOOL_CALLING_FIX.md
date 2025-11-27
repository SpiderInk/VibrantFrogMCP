# Tool Calling Issue - Mistral Not Calling Tools

## Problem Identified

**Symptoms:**
- UI shows "Ollama not available" ✅ FIXED
- Tools are being fetched: ✅ 10 MCP tools found
- Tools are being passed to Ollama: ✅ Calling with 10 tools
- **BUT:** Mistral returns `tool_calls: 0` and describes what it would do instead of calling tools

**Example Response from Mistral:**
```
"To find beach photos for you, I'm searching the library now...
Here are some of the beach photos I found:
(List photos returned by search_photos(query="beach"))"
```

**This is NOT actual tool calling** - it's just describing the tools in text.

## Root Cause

**Mistral has inconsistent tool calling behavior.** It knows tools are available but often chooses to respond with descriptive text instead of making actual tool calls.

From the console logs:
```
🔧 AIChatViewModel: Fetched 10 MCP tools
  - search_photos: Search indexed photos using natural language queries
  - create_album_from_search: Search for photos and create a new Apple Photos album
  ... (8 more)
🤖 AIChatViewModel: Calling Ollama with 10 tools
🤖 AIChatViewModel: Got response from Ollama
🤖 Response content: [descriptive text instead of tool call]
🤖 Tool calls: 0  ← THE PROBLEM
```

## Solutions Applied

### 1. Added Low Temperature for Determinism
**File:** `OllamaService.swift:148`
```swift
struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let tools: [Tool]?
    let stream: Bool = false
    let temperature: Double = 0.1  // Low temperature for more deterministic tool calling
}
```

This makes the model less creative and more likely to follow instructions.

### 2. Strengthened System Message
**File:** `AIChatView.swift:163-182`

Changed from generic instructions to explicit prohibitions:
```swift
CRITICAL RULES:
1. When users ask about photos, you MUST call the tools directly - do NOT explain or describe what tools to use
2. NEVER write code or pseudocode - you have real function calling capability
3. DO NOT say "I will use tool X" or "You should call function Y" - just call it
4. DO NOT output markdown code blocks or example function calls - use actual tool calling

When a user asks "Show me beach photos", you MUST immediately call search_photos(query="beach"), not describe it.
```

### 3. Switched to llama3.2 (Better Tool Calling)
**File:** `OllamaService.swift:16`

```swift
@Published var selectedModel: String = "llama3.2:latest"

// llama3.2 is generally better at actually calling tools vs mistral
let toolSupportedModels = ["mistral", "llama3.1", "llama3.2", "qwen2.5"]
```

**Why llama3.2?**
- Llama3.2 is known to be more reliable at function calling than Mistral
- It follows tool calling instructions more consistently
- Better at understanding when to call tools vs when to respond with text

### 4. Added Debug Logging
**File:** `AIChatView.swift:213-230`

```swift
print("🔧 AIChatViewModel: Fetched \(tools.count) MCP tools")
for tool in tools {
    print("  - \(tool.function.name): \(tool.function.description)")
}
print("🤖 AIChatViewModel: Calling Ollama with \(tools.isEmpty ? "NO" : "\(tools.count)") tools")
print("🤖 Response content: \(response.content)")
print("🤖 Tool calls: \(response.tool_calls?.count ?? 0)")
```

This helps diagnose tool calling issues in real-time.

## Current Status

✅ **Build:** SUCCESS
✅ **Ollama:** Running
✅ **MCP Server:** Running (http://127.0.0.1:5050)
✅ **UI Fix:** Ollama shows as available
⏳ **llama3.2 Download:** ~90% complete (should finish in ~10 seconds)
✅ **Temperature:** Set to 0.1 for determinism
✅ **System Message:** Strengthened with explicit prohibitions

## Next Steps

### Option A: Wait for llama3.2 and Test (RECOMMENDED)

1. **Wait for download to complete** (check with `ollama list`)
2. **Restart the app** (Cmd+R in Xcode)
3. **Try:** "Show me beach photos"
4. **Look for in console:**
   ```
   ✅ AIChatViewModel: LLM wants to call 1 tools!
   🔧 Calling MCP tool: search_photos with args: ["query": "beach", "n_results": 10]
   ```
5. **Expected result:** Actual tool call with photo thumbnails displayed

### Option B: Try Mistral with New Temperature (Less Likely to Work)

You can manually switch back to Mistral in the UI model selector and try again with the new temperature=0.1 setting. However, Mistral is known to be inconsistent.

### Option C: Try llama3.1 (Alternative)

If llama3.2 doesn't work well:
```bash
ollama pull llama3.1:latest
```

Then select it from the model dropdown in the app.

## Why Simple Chat Works

**Simple Chat** doesn't use an LLM at all - it directly parses user input and calls MCP tools based on keywords:

```swift
if message.lowercased().contains("search") || message.lowercased().contains("find") {
    // Extract query and directly call search_photos
}
```

This is why it always works but isn't "intelligent" - it's just pattern matching.

## Model Comparison

| Model | Tool Support | Actual Calling Reliability | Notes |
|-------|--------------|---------------------------|-------|
| **llama3.2** | ✅ Yes | ⭐⭐⭐⭐⭐ Excellent | Recommended |
| **llama3.1** | ✅ Yes | ⭐⭐⭐⭐ Very Good | Good alternative |
| **mistral** | ✅ Yes | ⭐⭐ Poor | Describes instead of calling |
| **gemma3:4b** | ❌ No | ❌ N/A | No function calling support |
| **llava:7b** | ❌ No | ❌ N/A | Vision model, no tools |

## Testing After llama3.2 Download

1. **Check download complete:**
   ```bash
   ollama list
   ```
   Should show `llama3.2:latest`

2. **Run app** (Cmd+R)

3. **Verify model selected:** Should show "llama3.2:latest" in dropdown

4. **Test with:**
   ```
   "Show me beach photos"
   "Find photos of sunsets"
   "Create an album from my vacation photos"
   ```

5. **Console should show:**
   ```
   🔧 AIChatViewModel: Fetched 10 MCP tools
   🤖 AIChatViewModel: Calling Ollama with 10 tools
   🤖 Tool calls: 1  ← SUCCESS!
   ✅ AIChatViewModel: LLM wants to call 1 tools!
   🔧 Calling MCP tool: search_photos with args: ...
   ```

6. **UI should show:**
   - Tool result message: "Called search_photos"
   - Photo thumbnails with descriptions
   - Clickable photos that open in Photos.app
   - Final assistant response: "I found X beach photos for you!"

## If It Still Doesn't Work

If llama3.2 also doesn't call tools:

1. **Check tool format:** Add logging to see exact JSON sent to Ollama
2. **Try different prompt:** Sometimes rewording the system message helps
3. **Update Ollama:** `brew upgrade ollama` (may fix tool calling bugs)
4. **Try qwen2.5:** `ollama pull qwen2.5:latest` (alternative model)
5. **Check Ollama logs:** See if there are errors during tool calling

## Files Modified

1. **VibrantFrog/Services/OllamaService.swift**
   - Line 16: Changed default model to llama3.2
   - Line 148: Added temperature parameter

2. **VibrantFrog/Views/AIChatView.swift**
   - Lines 163-182: Strengthened system message
   - Lines 213-230: Added debug logging
   - Line 10: Added Combine import
   - Lines 150-155: Added objectWillChange forwarding (UI fix)

---

**Download should be complete shortly. Once `ollama list` shows llama3.2:latest, restart the app and test!**
