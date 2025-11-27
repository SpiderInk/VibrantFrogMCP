# Tool Support Fix

## Issue Found

**Error:** `gemma3:4b does not support tools`

The model you had (`gemma3:4b`) doesn't support function calling / tool use.

## Solution

Download a model that supports tools:

```bash
ollama pull mistral:latest  # Currently downloading (4.4 GB)
```

## Models That Support Tools

✅ **These models support function calling:**
- `mistral:latest` (7B, ~4.4 GB) ← **Recommended**
- `llama3.1:latest` (8B, ~4.7 GB)
- `llama3.2:latest` (3B, ~2.0 GB)
- `qwen2.5:latest` (7B, ~4.7 GB)

❌ **These models DO NOT support tools:**
- `gemma3:4b` ← Your current model
- `llava:7b` (vision model, no tools)
- `phi3:latest`
- Most older models

## Status

⏳ **Currently downloading:** `mistral:latest` (18% complete, ~54s remaining)

Once download is complete:
1. Restart the app (or it will auto-detect the new model)
2. Select "mistral:latest" from the model picker
3. Try: "Show me beach photos"
4. **It will work!** ✅

## What Changed in Code

Updated `OllamaService.swift`:
```swift
@Published var selectedModel: String = "mistral:latest"  // Changed from gemma3:4b

// Added list of tool-supported models
let toolSupportedModels = ["mistral", "llama3.1", "llama3.2", "qwen2.5"]
```

## Why This Matters

**Function calling** (tools) is required for the AI to:
- Call MCP tools (search_photos, create_album, etc.)
- Understand when to use which tool
- Pass parameters correctly
- Return structured results

Without tool support, the LLM can only chat - it can't actually DO anything with your photos.

## After Fix

Once Mistral is downloaded and selected:

**You:** "Show me beach photos"

**Mistral:**
1. Understands the request
2. Calls `search_photos(query="beach", n_results=10)`
3. Gets results from MCP server
4. Responds: "I found 12 beach photos for you!"
5. Displays thumbnails

**This is the full AI experience you wanted!** 🎉

## Alternative: Smaller Model

If 4.4 GB is too large, try `llama3.2:1b` (1.3 GB):
```bash
ollama pull llama3.2:1b
```

But `mistral:latest` is recommended for better quality responses.
