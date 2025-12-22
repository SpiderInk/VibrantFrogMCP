# Quick Start to Release

**For:** Tony Piazza (Maintainer)
**Purpose:** Execute VibrantFrog v1.0.0 public release
**Time Required:** ~1 day of focused work

---

## Pre-Flight Checklist

Before you begin, ensure:
- ✅ All code changes committed to git
- ✅ Xcode project builds successfully
- ✅ You have GitHub account and can create SpiderInk organization
- ✅ Ollama is installed and working on your Mac
- ✅ You have time to monitor release for first 48 hours

---

## Step 1: Fix Hardcoded Paths (2-3 hours)

### Current Hardcoded Path

**File:** `VibrantFrogApp/VibrantFrog/Services/MCPClientHTTP.swift`
**Line:** 36

```swift
serverScriptPath: String = "/Users/tpiazza/git/VibrantFrogMCP/vibrant_frog_mcp.py"
```

### Solution Options

**Option A: Make Configurable via Settings (Recommended)**

1. Add setting to store MCP server script path
2. Use `UserDefaults` to persist
3. Provide UI in Settings to change path
4. Default to looking in common locations:
   - `~/vibrant_frog_mcp.py`
   - `/usr/local/bin/vibrant_frog_mcp.py`
   - Bundle resources

**Option B: Bundle Resource (Simpler)**

1. Add `vibrant_frog_mcp.py` to Xcode project as resource
2. Use `Bundle.main.path(forResource:ofType:)` to find it
3. Copy to user's home directory on first launch

**Option C: Environment Variable**

```swift
let defaultPath = ProcessInfo.processInfo.environment["VIBRANTFROG_MCP_SCRIPT"]
    ?? "~/vibrant_frog_mcp.py"
```

### Search for Other Hardcoded Paths

```bash
cd /Users/tpiazza/git/VibrantFrogMCP
grep -r "/Users/tpiazza" VibrantFrogApp/ | grep -v ".xcuserstate" | grep -v "DerivedData"
```

Fix any you find!

### Verification

1. Build and run on YOUR Mac
2. If possible, test on a different Mac (VM or friend's machine)
3. Ensure app launches and connects to Ollama

---

## Step 2: Take Screenshots (1 hour)

### Required Screenshots

Use **⌘+Shift+4** to capture specific windows, or **⌘+Shift+5** for screen recording.

**1. Hero Shot (main README image)**
- Open VibrantFrog
- Select `mistral-nemo:latest` model
- Start a conversation showing tool use
- Capture clean, centered window
- Save as: `/assets/screenshots/hero.png`

**2. Chat Interface**
- Show active conversation with tool calls visible
- Save as: `/assets/screenshots/chat-interface.png`

**3. Photo Search**
- Navigate to AI Chat
- Show photo search results with thumbnails
- Save as: `/assets/screenshots/photo-search.png`

**4. MCP Server Management**
- Navigate to MCP Server tab
- Show connected server with tools listed
- Save as: `/assets/screenshots/mcp-management.png`

**5. Prompt Templates**
- Navigate to Prompts tab
- Show template library
- Save as: `/assets/screenshots/prompts.png`

**6. Developer Tools**
- Navigate to Developer tab
- Show tool calling interface
- Save as: `/assets/screenshots/developer-tools.png`

### Create Directory

```bash
mkdir -p /Users/tpiazza/git/VibrantFrogMCP/assets/screenshots
```

### Embed in README

Add to README.md after the badges:

```markdown
## Screenshots

### Main Interface
![VibrantFrog Chat Interface](assets/screenshots/hero.png)

### Photo Intelligence
![Photo Search with AI](assets/screenshots/photo-search.png)

### MCP Integration
![MCP Server Management](assets/screenshots/mcp-management.png)

<details>
<summary>More Screenshots</summary>

![Prompt Templates](assets/screenshots/prompts.png)
![Developer Tools](assets/screenshots/developer-tools.png)

</details>
```

### Optional: Demo GIF

If you want to go the extra mile:

1. Record with QuickTime (File → New Screen Recording)
2. Show: Launch → Select Model → Ask Question → Tool Call → Result
3. Keep it under 30 seconds
4. Convert to GIF: https://cloudconvert.com/mp4-to-gif
5. Optimize: https://ezgif.com/optimize
6. Save as: `/assets/demo/demo.gif`

---

## Step 3: Update Bundle Configuration (30 minutes)

### Xcode Project Settings

1. Open `VibrantFrogApp/VibrantFrog.xcodeproj`
2. Select VibrantFrog target
3. Go to **General** tab:
   - **Bundle Identifier:** `com.spiderink.vibrantfrog`
   - **Version:** `1.0.0`
   - **Build:** `1`
4. Go to **Signing & Capabilities** tab:
   - Uncheck "Automatically manage signing" (for now)
   - Or use your personal Developer ID if you have one

### Info.plist

Verify these values:

```xml
<key>CFBundleName</key>
<string>VibrantFrog</string>

<key>CFBundleShortVersionString</key>
<string>1.0.0</string>

<key>CFBundleVersion</key>
<string>1</string>

<key>NSHumanReadableCopyright</key>
<string>© 2025 SpiderInk</string>
```

### Build and Test

```bash
cd VibrantFrogApp
xcodebuild -scheme VibrantFrog -configuration Release clean build
```

Make sure it builds successfully!

---

## Step 4: Final Code Review (1 hour)

### Check for Sensitive Data

```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# Search for potential issues
grep -r "password" . --exclude-dir=".git"
grep -r "api_key" . --exclude-dir=".git"
grep -r "secret" . --exclude-dir=".git"
grep -r "TODO.*FIXME\|HACK\|XXX" . --exclude-dir=".git"
```

### Review .gitignore

Ensure these are ignored:

```
# Xcode
*.xcuserstate
*.xcworkspace/xcuserdata/
DerivedData/
build/

# macOS
.DS_Store

# Python
__pycache__/
*.pyc
.venv/

# ChromaDB
chroma_db/

# Personal
*.backup.*
```

### Check Large Files

```bash
find . -type f -size +10M | grep -v ".git"
```

Remove or gitignore any large files found.

### Commit All Changes

```bash
git add .
git status  # Review what's being committed
git commit -m "chore: prepare for v1.0.0 release

- Remove hardcoded paths
- Add screenshots to README
- Update bundle configuration
- Final documentation review
"
```

---

## Step 5: Create GitHub Repository (1 hour)

### On GitHub

1. Go to https://github.com/organizations/SpiderInk (or create organization first)
2. Click **New repository**
3. Settings:
   - **Repository name:** `VibrantFrog`
   - **Description:** `Native macOS AI Chat with Model Context Protocol Support`
   - **Visibility:** Public
   - **DO NOT** initialize with README (we have our own)
4. Click **Create repository**

### Configure Repository

1. Go to **Settings** tab
2. Under **Features**:
   - ✅ Enable Issues
   - ✅ Enable Discussions
   - ✅ Enable Projects (optional)
   - ✅ Enable Wiki (optional)
3. Under **General** → **Social Preview**:
   - Upload hero screenshot as repository image
4. Under **Topics**:
   - Add: `macos`, `ai-chat`, `mcp`, `ollama`, `swift`, `swiftui`, `model-context-protocol`, `llm`, `local-ai`

### Create Issue Templates

Create directory and files:

```bash
mkdir -p .github/ISSUE_TEMPLATE
```

**`.github/ISSUE_TEMPLATE/bug_report.md`:**

```markdown
---
name: Bug Report
about: Report a bug or issue
title: '[BUG] '
labels: bug
---

**Description**
Clear description of the bug.

**Steps to Reproduce**
1. Go to '...'
2. Click on '...'
3. See error

**Expected Behavior**
What should happen.

**Actual Behavior**
What actually happens.

**Environment**
- macOS Version:
- VibrantFrog Version:
- Ollama Version:
- Model:

**Console Logs**
```
Paste relevant logs here
```
```

**`.github/ISSUE_TEMPLATE/feature_request.md`:**

```markdown
---
name: Feature Request
about: Suggest a new feature
title: '[FEATURE] '
labels: enhancement
---

**Feature Description**
Describe what you'd like to see.

**Use Case**
Why would this be valuable?

**Possible Implementation**
Ideas on how it could work?
```

**`.github/PULL_REQUEST_TEMPLATE.md`:**

```markdown
## Description
What does this PR do?

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring

## Testing
How did you test this?

## Checklist
- [ ] Code follows project style
- [ ] Self-reviewed code
- [ ] Commented complex logic
- [ ] Updated documentation
- [ ] No new warnings
```

Commit templates:

```bash
git add .github/
git commit -m "chore: add GitHub issue and PR templates"
```

---

## Step 6: Push to GitHub (10 minutes)

### Add Remote

```bash
cd /Users/tpiazza/git/VibrantFrogMCP
git remote add origin https://github.com/SpiderInk/VibrantFrog.git
```

### Push Code

```bash
git push -u origin main
```

If you're using a different branch name (e.g., `master`), use that instead.

### Verify

1. Go to https://github.com/SpiderInk/VibrantFrog
2. Verify all files are there
3. Check that README displays correctly
4. Ensure screenshots show up

---

## Step 7: Create v1.0.0 Release (30 minutes)

### Create Git Tag

```bash
git tag -a v1.0.0 -m "Release v1.0.0 - Initial public release"
git push origin v1.0.0
```

### Create GitHub Release

1. Go to https://github.com/SpiderInk/VibrantFrog/releases
2. Click **Draft a new release**
3. Settings:
   - **Choose a tag:** v1.0.0 (should exist from above)
   - **Release title:** `VibrantFrog v1.0.0 - Initial Release 🐸`
   - **Description:** Copy from CHANGELOG.md + release notes template below

### Release Notes Template

```markdown
# 🐸 VibrantFrog v1.0.0

**The first public release of VibrantFrog is here!**

VibrantFrog is a native macOS AI chat application with full support for the Model Context Protocol (MCP). Chat with local Ollama models, connect to MCP servers for tool calling, and search your photo library with AI-powered semantic search.

## ✨ Features

### AI Chat Interface
- Native macOS experience built with SwiftUI
- Powered by Ollama for private, local AI
- Multi-model support (Mistral, Llama, etc.)
- Conversation history with persistence
- Photo attachment support

### Model Context Protocol (MCP)
- Full HTTP transport implementation
- Dynamic tool discovery and execution
- Custom MCP server support
- Built-in AWS server integration
- Developer tools for testing

### Photo Intelligence
- Apple Photos library integration
- AI-generated descriptions (LLaVA vision model)
- Vector search with ChromaDB
- Semantic photo search
- Privacy-first (all local processing)

### Smart Prompts
- Template library
- Variable substitution ({{TOOLS}}, {{MCP_SERVER_NAME}})
- Customizable and extensible

## 🚀 Quick Start

### Install Dependencies
```bash
# Install Ollama
brew install ollama

# Start Ollama
ollama serve

# Pull a model with good function calling
ollama pull mistral-nemo:latest
```

### Build VibrantFrog
```bash
git clone https://github.com/SpiderInk/VibrantFrog.git
cd VibrantFrog/VibrantFrogApp
open VibrantFrog.xcodeproj
# Build and run (⌘R)
```

### Start Chatting!
1. Select `mistral-nemo:latest` model
2. Connect to an MCP server (optional)
3. Ask questions and watch the AI use tools

## 📚 Documentation

- **[README](https://github.com/SpiderInk/VibrantFrog#readme)** - Installation and usage
- **[Architecture](https://github.com/SpiderInk/VibrantFrog/blob/main/ARCHITECTURE.md)** - Technical details
- **[Contributing](https://github.com/SpiderInk/VibrantFrog/blob/main/CONTRIBUTING.md)** - How to contribute
- **[Security](https://github.com/SpiderInk/VibrantFrog/blob/main/SECURITY.md)** - Security policy

## 🐛 Known Issues

- **Tool Use:** First chat after launch may not use tools (warmup added, but not 100% reliable yet)
- **No Sandbox:** App runs without macOS sandbox for ChromaDB access (documented in SECURITY.md)
- **Source Only:** No binary distribution yet (users must build from source)

## 🔮 Coming Soon

**v1.1:**
- Streaming response support
- Stdio MCP transport
- Better error messages
- UI refinements

**v1.2:**
- Conversation export (Markdown, PDF)
- Custom model parameters
- More prompt templates

## 🙏 Acknowledgments

Built with:
- [Ollama](https://ollama.ai) - Local LLM inference
- [Model Context Protocol](https://modelcontextprotocol.io) - Tool calling standard
- [ChromaDB](https://www.trychroma.com) - Vector database
- SwiftUI - Modern UI framework

## 📝 License

VibrantFrog is released under the [MIT License](https://github.com/SpiderInk/VibrantFrog/blob/main/LICENSE).

## 💬 Support

- **Issues:** [Report bugs](https://github.com/SpiderInk/VibrantFrog/issues)
- **Discussions:** [Ask questions](https://github.com/SpiderInk/VibrantFrog/discussions)
- **Security:** security@spiderink.net

---

Made with ❤️ by SpiderInk

**Full Changelog**: https://github.com/SpiderInk/VibrantFrog/commits/v1.0.0
```

4. Click **Publish release**

---

## Step 8: Announce Release (2-3 hours)

### Hacker News

1. Go to https://news.ycombinator.com/submit
2. Title: `Show HN: VibrantFrog - Native macOS AI Chat with MCP Support`
3. URL: `https://github.com/SpiderInk/VibrantFrog`
4. Text (optional):

```
I built VibrantFrog as a native macOS client for the Model Context Protocol.

It combines local Ollama models with MCP tool calling, plus AI-powered
photo library search using ChromaDB vector embeddings.

Key features:
- Full MCP HTTP transport implementation
- Privacy-first (everything runs locally)
- Photo search with semantic understanding
- Native SwiftUI interface

Happy to answer questions! This is my first open source release.
```

### Reddit

Post to these subreddits:

**r/MacApps:**
- Title: `[Open Source] VibrantFrog - AI Chat with MCP Support for macOS`
- Include screenshots
- Focus on native macOS experience

**r/LocalLLaMA:**
- Title: `VibrantFrog: Native macOS app for Ollama with MCP tool calling`
- Focus on Ollama integration and local AI

**r/ollama:**
- Title: `Built a native macOS app for Ollama with MCP and photo search`
- Focus on Ollama features

### Twitter/X

```
🐸 Just released VibrantFrog v1.0.0!

Native macOS AI chat with:
✅ Ollama integration
✅ MCP tool calling
✅ Photo library search
✅ Privacy-first local AI

Open source, MIT license

→ github.com/SpiderInk/VibrantFrog

#AI #macOS #OpenSource #MCP #Ollama
```

### LinkedIn

```
Excited to release VibrantFrog 1.0! 🐸

A native macOS application showcasing the Model Context Protocol (MCP)
with local AI via Ollama. Built with SwiftUI and modern Swift.

Key features:
• Full MCP HTTP transport
• ChromaDB vector search
• Privacy-focused local processing
• Photo library integration

Perfect for developers exploring MCP or users wanting AI without
cloud dependencies.

Check it out: https://github.com/SpiderInk/VibrantFrog

#SwiftUI #AI #ModelContextProtocol #macOS
```

### MCP Community

- Post in MCP Discord/Slack
- Email MCP protocol maintainers
- Share in developer forums

---

## Step 9: Monitor and Respond (First 48 Hours)

### Set Up Notifications

1. GitHub:
   - Settings → Notifications → Enable all for VibrantFrog
   - Watch the repository

2. Email:
   - Check security@spiderink.net regularly

3. Social:
   - Monitor HN comments
   - Check Reddit responses
   - Reply to tweets

### Response Guidelines

**For Bug Reports:**
- Acknowledge within 24 hours
- Ask for logs/reproduction steps
- Create GitHub issue if valid
- Provide timeline for fix

**For Questions:**
- Answer promptly and friendly
- Add to FAQ if common
- Update docs if unclear

**For Feature Requests:**
- Thank them for suggestion
- Ask about use case
- Consider for roadmap
- Create issue for tracking

**For Criticism:**
- Stay professional
- Acknowledge valid points
- Explain trade-offs
- Improve if reasonable

### Track Metrics

Create a spreadsheet tracking:
- GitHub stars (hourly for first day)
- Issues opened
- Discussions started
- Social media engagement
- Downloads/clones

---

## Emergency Procedures

### Critical Bug Found

1. **Immediate:**
   - Add warning to README
   - Pin issue on GitHub
   - Post in Discussions

2. **Within 24 hours:**
   - Create hotfix branch
   - Fix the bug
   - Test thoroughly

3. **Within 48 hours:**
   - Release v1.0.1
   - Update all announcements
   - Thank reporter

### Negative Feedback

1. **Don't panic** - Not everyone will love it
2. **Listen** - Valid criticism helps improve
3. **Respond professionally** - Stay calm and factual
4. **Learn** - Use feedback to prioritize improvements

### Overwhelming Response

1. **Set boundaries** - You can't respond to everything
2. **Prioritize** - Critical bugs first, then features
3. **Ask for help** - Recruit contributors
4. **Pace yourself** - This is a marathon, not a sprint

---

## Post-Release Checklist (Week 1)

### Daily
- [ ] Check GitHub issues
- [ ] Respond to discussions
- [ ] Monitor social media
- [ ] Answer questions

### By End of Week
- [ ] Create v1.0.1 if bugs found
- [ ] Update README based on FAQs
- [ ] Thank contributors
- [ ] Document common issues

### By End of Month
- [ ] Write blog post about launch
- [ ] Plan v1.1 features
- [ ] Consider binary distribution
- [ ] Review metrics and learnings

---

## Success Criteria

You'll know it's successful if:

- ✅ 50+ GitHub stars in first week
- ✅ Positive feedback on HN/Reddit
- ✅ People actually using it (issues, discussions)
- ✅ No critical bugs discovered
- ✅ Contribution PRs from community

Even if you hit just 2-3 of these, it's a win!

---

## Final Thoughts

**Remember:**
- This is v1.0.0, not the final product
- Community feedback will guide improvements
- Not everyone will love it (that's okay!)
- You built something real and useful
- Open source is about iteration and learning

**Most Important:**
- Have fun!
- Engage with community
- Learn from feedback
- Keep improving

---

## Quick Commands Reference

```bash
# Remove hardcoded paths (manual edit)
# Then commit:
git add .
git commit -m "chore: remove hardcoded paths"

# Take screenshots (manual)
# Then:
mkdir -p assets/screenshots
# Copy screenshots
git add assets/
git commit -m "docs: add screenshots"

# Update bundle config (Xcode)
# Then build:
cd VibrantFrogApp
xcodebuild -scheme VibrantFrog -configuration Release clean build

# Create GitHub templates
mkdir -p .github/ISSUE_TEMPLATE
# Create files
git add .github/
git commit -m "chore: add GitHub templates"

# Push to GitHub
git remote add origin https://github.com/SpiderInk/VibrantFrog.git
git push -u origin main

# Create release
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# Then create GitHub release via web UI
```

---

## Ready? Let's Go! 🚀

You've got this. VibrantFrog is ready. The documentation is ready. The community is waiting.

**Next step:** Open this file, start with Step 1, and work through each section.

**Questions?** Refer to DISTRIBUTION_PLAN.md for detailed strategy.

**Need help?** The MCP community is friendly - don't hesitate to ask!

---

**Good luck, and enjoy the launch! 🐸**
