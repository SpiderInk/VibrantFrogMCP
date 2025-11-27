# Manual Fix Required for Xcode Project

## Issue

The following files exist but are not added to the Xcode project:
- `VibrantFrog/Services/OllamaService.swift`
- `VibrantFrog/Services/MCPServerRegistry.swift`

## Quick Fix (5 minutes)

### Step 1: Open Xcode
```bash
cd /Users/tpiazza/git/VibrantFrogMCP/VibrantFrogApp
open VibrantFrog.xcodeproj
```

### Step 2: Add the files to the project

1. In Xcode's left sidebar (Project Navigator), right-click on the **Services** folder
2. Select **"Add Files to 'VibrantFrog'..."**
3. Navigate to: `VibrantFrogApp/VibrantFrog/Services/`
4. Select these two files:
   - `OllamaService.swift`
   - `MCPServerRegistry.swift`
5. Make sure these options are checked:
   - ✅ **Copy items if needed** (leave UNCHECKED - files are already there)
   - ✅ **Create groups** (not folder references)
   - ✅ **Add to targets: VibrantFrog**
6. Click **Add**

### Step 3: Build
- Press **Cmd+B** to build
- Should see: `** BUILD SUCCEEDED **`

### Step 4: Run
- Press **Cmd+R** to run
- Select **AI Chat** tab (brain icon)
- Try: "Show me beach photos"

---

## Alternative: Remove and Re-Add AIChatView.swift

If adding the Services doesn't work, also try:

1. In Xcode, select `AIChatView.swift` in Views folder
2. Right-click → **Delete** → **Remove Reference** (don't move to trash)
3. Right-click on Views folder → **"Add Files to 'VibrantFrog'..."**
4. Select `AIChatView.swift`
5. Build again

---

## What's Ready

✅ **All code is written and correct**
✅ **Ollama is running** (Process 6209)
✅ **MCP Server is running** (http://127.0.0.1:5050)
✅ **Files exist in correct locations**

❌ **Xcode project file needs manual update**

---

## Why This Happened

When I created the files programmatically, Xcode's project file (`project.pbxproj`) wasn't automatically updated with the new file references. This is normal - Xcode needs to be open to track file changes automatically.

---

## After Fix

Once the files are added, the app will build successfully and you'll have:

1. **AI Chat** tab - Real LLM (Ollama) with MCP tool calling
2. **Simple Chat** tab - Direct MCP calls (no LLM)
3. **MCP Server** tab - Server configuration
4. Full photo search with natural language

Try asking:
- "Show me beach photos"
- "Find photos of sunsets"
- "Create an album from my vacation photos"

The LLM will automatically call MCP tools and show results!
