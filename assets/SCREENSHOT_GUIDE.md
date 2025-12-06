# Screenshot Guide for VibrantFrog

This guide will help you capture professional screenshots for the README and website.

## Required Screenshots

### 1. Hero Screenshot (Priority: CRITICAL)
**File:** `hero-main-chat.png`
**Size:** 1920x1080 or larger
**Content:** Main AI Chat interface showing a complete conversation with tool calling

**Setup:**
1. Launch VibrantFrog
2. Select `mistral-nemo:latest` model
3. Connect to AWS MCP server
4. Select "AWS Helper" prompt template
5. Ask: "What AWS services are available?"
6. Wait for tool call and response
7. The conversation should show:
   - Your question
   - Tool call indicator (🔧)
   - Tool result
   - Final AI response

**How to Capture:**
```bash
# Use macOS screenshot tool
# Press: Cmd + Shift + 4
# Click window to capture entire window
# OR press Spacebar after Cmd+Shift+4 to capture specific window
```

**Tips:**
- Clean, uncluttered screen
- Good lighting/contrast
- Show complete, successful interaction
- Include visible UI elements (model dropdown, server selector)

### 2. MCP Server Management
**File:** `mcp-server-config.png`
**Size:** 1200x800 or larger
**Content:** MCP Server tab showing connected server

**Setup:**
1. Go to "MCP Server" tab
2. Show AWS server with green "Connected" indicator
3. Show list of available tools
4. Capture clean, organized view

### 3. Prompt Templates
**File:** `prompt-templates.png`
**Size:** 1200x800 or larger
**Content:** Prompts tab showing template editor

**Setup:**
1. Go to "Prompts" tab
2. Select "AWS Helper" template
3. Show the template content with variables highlighted
4. Capture the clean editing interface

### 4. Conversation History
**File:** `conversation-history.png`
**Size:** 1200x800 or larger
**Content:** Conversations tab with multiple past chats

**Setup:**
1. Have 3-4 conversations saved
2. Go to "Conversations" tab
3. Show list with titles and timestamps
4. Capture organized history view

### 5. Tool Calling in Action (Optional but Recommended)
**File:** `tool-calling-detail.png`
**Size:** 1200x800
**Content:** Close-up of tool call execution

**Setup:**
1. Capture the moment when tool results are displayed
2. Show the JSON or formatted tool response
3. Highlight the transition from tool → final response

## Screenshot Workflow

### Step-by-Step Process

1. **Prepare the App**
   ```bash
   # Make sure Ollama is running
   ollama serve

   # Verify model is available
   ollama list | grep mistral-nemo

   # Launch VibrantFrog
   open VibrantFrogApp/VibrantFrog.xcodeproj
   # Build and run
   ```

2. **Set Up Sample Conversation**
   - Connect to AWS MCP server
   - Ask: "What AWS services are available?"
   - Let it complete with tool calls
   - Ask follow-up: "Tell me more about Amazon S3"
   - This gives you a rich conversation to screenshot

3. **Capture Screenshots**
   ```bash
   # For each screenshot:
   # 1. Navigate to the view
   # 2. Press Cmd+Shift+4, then Spacebar
   # 3. Click the window
   # 4. Screenshot saves to Desktop
   ```

4. **Organize Files**
   ```bash
   # Move screenshots to project
   mv ~/Desktop/Screenshot*.png /Users/tpiazza/git/VibrantFrogMCP/assets/screenshots/

   # Rename appropriately
   cd /Users/tpiazza/git/VibrantFrogMCP/assets/screenshots/
   mv Screenshot1.png hero-main-chat.png
   mv Screenshot2.png mcp-server-config.png
   # etc.
   ```

5. **Optimize Images** (Optional)
   ```bash
   # Install ImageOptim (optional)
   brew install --cask imageoptim

   # Or use built-in tools
   # Compress PNG without losing quality
   sips -s format png hero-main-chat.png --out hero-main-chat-optimized.png
   ```

## Embedding in README

Once you have screenshots, update README.md:

```markdown
## Screenshots

### AI Chat with Tool Calling
![VibrantFrog AI Chat](assets/screenshots/hero-main-chat.png)

### MCP Server Management
![MCP Configuration](assets/screenshots/mcp-server-config.png)

### Prompt Templates
![Template Editor](assets/screenshots/prompt-templates.png)
```

## Demo GIF (Optional)

Create an animated GIF showing the tool calling flow:

**Tools:**
- **QuickTime Player** - Record screen
- **gifski** - Convert video to GIF

**Steps:**
```bash
# 1. Record with QuickTime
# File → New Screen Recording
# Record: Ask question → Tool call → Response (15-20 seconds)

# 2. Convert to GIF
brew install gifski

# Trim video first (optional)
ffmpeg -i recording.mov -ss 00:00:00 -t 00:00:20 trimmed.mov

# Convert to GIF
gifski trimmed.mov -o demo.gif --fps 10 --quality 90 --width 1200

# Move to assets
mv demo.gif /Users/tpiazza/git/VibrantFrogMCP/assets/screenshots/
```

**Embed in README:**
```markdown
## Demo

![VibrantFrog Demo](assets/screenshots/demo.gif)
```

## Screenshot Checklist

Before taking screenshots:
- [ ] App is in Release mode (looks polished)
- [ ] No debug logs visible in UI
- [ ] macOS appearance: Light or Dark? (Choose one for consistency)
- [ ] Window size is appropriate (not too small)
- [ ] No personal data visible
- [ ] Clean desktop background (or blur it)

After taking screenshots:
- [ ] Images are clear and readable
- [ ] Text is not blurry
- [ ] Colors look good
- [ ] File sizes are reasonable (<5MB each)
- [ ] Saved in /assets/screenshots/
- [ ] Named descriptively

## Best Practices

### Lighting & Contrast
- Use dark mode for modern look
- OR light mode for clarity
- Be consistent across all screenshots

### Composition
- Center the important content
- Leave some breathing room around edges
- Avoid cutting off UI elements

### Content
- Use realistic example queries
- Show successful outcomes
- Demonstrate key features
- Keep it professional

### File Formats
- **PNG** - For static screenshots (preferred)
- **GIF** - For animations (optional)
- **MP4** - For demo videos (can convert to GIF)

## Sample Questions for Screenshots

Good questions to show in screenshots:
1. "What AWS services are available?"
2. "Search for AWS Lambda documentation"
3. "Tell me about Amazon S3 features"
4. "What are the latest AWS announcements?"
5. "Compare EC2 and Lambda for running applications"

These demonstrate:
- Tool calling
- Real-world use cases
- AI's ability to synthesize information
- Value of MCP integration

---

## Quick Reference

**Screenshot shortcut:** `Cmd + Shift + 4`, then `Spacebar`, then click window

**Default location:** `~/Desktop/Screenshot [date] at [time].png`

**Required screenshots:**
1. hero-main-chat.png (CRITICAL)
2. mcp-server-config.png
3. prompt-templates.png
4. conversation-history.png

**Optional:**
5. tool-calling-detail.png
6. demo.gif

Once you have at least the hero screenshot, you can make the repository public!
