# VibrantFrog Release Checklist

This document outlines all steps needed to prepare VibrantFrog for public release on GitHub under the SpiderInk organization.

## Pre-Release Preparation

### 1. Code Cleanup ✅

- [x] Remove debug print statements (keep informative logging)
- [x] Remove commented-out code
- [x] Remove backup files (*.backup.swift)
- [x] Ensure consistent code style
- [x] Run SwiftLint (if configured)
- [x] Fix all compiler warnings

### 2. Documentation ✅

- [x] Main README.md with:
  - [ ] Screenshots (NEEDED)
  - [x] Feature list
  - [x] Installation instructions
  - [x] Quick start guide
  - [x] Troubleshooting
  - [x] License badge
- [x] CONTRIBUTING.md
- [x] LICENSE file (MIT)
- [x] ARCHITECTURE.md
- [x] Organized docs/ folder
- [x] Code comments for complex logic

### 3. Repository Structure

- [x] Clean .gitignore
- [ ] Remove sensitive data:
  - [ ] No API keys
  - [ ] No personal paths
  - [ ] No credentials
- [ ] Clean git history (if needed)
- [x] Organize documentation

### 4. GitHub Repository Setup

- [ ] Create repository in SpiderInk organization:
  - Repository name: `VibrantFrog`
  - Description: "AI Chat with MCP Tool Calling for macOS"
  - Visibility: Public
  - Initialize with README: No (we have our own)

- [ ] Repository settings:
  - [ ] Add topics/tags: `macos`, `ai-chat`, `mcp`, `ollama`, `swift`, `swiftui`, `model-context-protocol`, `llm`
  - [ ] Enable Issues
  - [ ] Enable Discussions
  - [ ] Enable Wiki (optional)
  - [ ] Configure branch protection for `main`

- [ ] Add repository description and website:
  - About: "Native macOS AI chat application with Model Context Protocol (MCP) integration"
  - Website: https://spiderink.net/vibrantfrog (or forgoteam.ai)

### 5. GitHub Templates

Create `.github/` folder with:

- [ ] **ISSUE_TEMPLATE/bug_report.md**
- [ ] **ISSUE_TEMPLATE/feature_request.md**
- [ ] **PULL_REQUEST_TEMPLATE.md**
- [ ] **FUNDING.yml** (if you want sponsorship)

### 6. Screenshots and Assets

**Critical for README:**

- [ ] App icon (high-res PNG/SVG)
- [ ] Hero screenshot (main chat interface)
- [ ] Feature screenshots:
  - [ ] AI Chat with tool calling
  - [ ] MCP server management
  - [ ] Prompt templates
  - [ ] Conversation history
- [ ] Demo GIF or video (optional but recommended)

**Where to add:**
- Create `/assets/screenshots/` folder
- Embed in README.md

### 7. Build Configuration

- [ ] Set version number in VibrantFrogApp.swift
- [ ] Update app display name
- [ ] Configure bundle identifier (com.spiderink.vibrantfrog)
- [ ] Set minimum macOS version (14.0)
- [ ] Remove development team signing (or document it)
- [ ] Create Release build configuration

### 8. Testing

- [ ] Fresh install test on clean Mac
- [ ] Verify all features work:
  - [ ] Ollama connection
  - [ ] Model selection
  - [ ] Chat functionality
  - [ ] MCP server connection
  - [ ] Tool calling
  - [ ] Conversation persistence
  - [ ] Photo attachments
  - [ ] Prompt templates
- [ ] Test with different Ollama models
- [ ] Test error scenarios
- [ ] Memory leak check (Instruments)

## Release Process

### 1. Version Control

```bash
# Ensure you're on main branch
git checkout main

# Update version in code
# Edit VibrantFrogApp.swift: applicationVersion: "1.0.0"

# Commit version bump
git add .
git commit -m "chore: bump version to 1.0.0"

# Create tag
git tag -a v1.0.0 -m "Release v1.0.0 - Initial public release"

# Push to GitHub
git push origin main
git push origin v1.0.0
```

### 2. GitHub Release

- [ ] Go to GitHub Releases
- [ ] Click "Draft a new release"
- [ ] Select tag: `v1.0.0`
- [ ] Release title: `VibrantFrog v1.0.0 - Initial Release`

**Release Notes Template:**

```markdown
# VibrantFrog v1.0.0 🐸

**The first public release of VibrantFrog - Native macOS AI Chat with MCP Integration!**

## 🎉 What's New

VibrantFrog brings AI-powered conversations to your Mac with full support for the Model Context Protocol (MCP), allowing AI models to interact with external services and execute custom tools.

### ✨ Features

- **AI Chat Interface** - Native macOS chat powered by Ollama
- **MCP Integration** - Connect to MCP servers for tool calling
- **Multiple Models** - Support for Mistral, Llama, and more
- **Smart Prompts** - Customizable templates with variable substitution
- **Conversation History** - Persistent chat history with search
- **Developer Tools** - Direct tool calling and MCP testing interface
- **Photo Support** - Attach and analyze photos in conversations

### 🚀 Getting Started

1. **Install Ollama:**
   ```bash
   brew install ollama
   ollama pull mistral-nemo:latest
   ```

2. **Build VibrantFrog:**
   ```bash
   git clone https://github.com/SpiderInk/VibrantFrog.git
   cd VibrantFrog/VibrantFrogApp
   open VibrantFrog.xcodeproj
   # Build and run (⌘R)
   ```

3. **Start Chatting!**
   Select a model, connect to MCP servers, and ask questions.

### 📚 Documentation

- [README](https://github.com/SpiderInk/VibrantFrog#readme) - Installation and quick start
- [Architecture](./ARCHITECTURE.md) - Technical design
- [Contributing](./CONTRIBUTING.md) - How to contribute

### 🐛 Known Issues

- First chat request after startup may not use tools (requires second request)
  - _Fixed in upcoming v1.0.1 with model priming_
- Streaming responses not yet supported
- Only HTTP MCP transport (stdio coming soon)

### 🙏 Acknowledgments

Built with:
- [Ollama](https://ollama.ai) for local LLM inference
- [Model Context Protocol](https://modelcontextprotocol.io) specification
- SwiftUI and modern Swift async/await

### 📝 License

VibrantFrog is released under the [MIT License](./LICENSE).

---

**Full Changelog**: https://github.com/SpiderInk/VibrantFrog/commits/v1.0.0
```

### 3. Binary Release (Optional)

If providing pre-built binaries:

- [ ] Create Release build
- [ ] Export as Archive
- [ ] Notarize with Apple (requires Developer ID)
- [ ] Create DMG installer
- [ ] Attach to GitHub release

**Note:** For initial release, source-only is fine. Users can build from source.

### 4. Announcement

**GitHub:**
- [ ] Post in Discussions
- [ ] Pin the release

**Social Media:**
- [ ] Twitter/X: Announce with screenshot
- [ ] LinkedIn: Share with professional angle
- [ ] Mastodon: Technical audience

**Communities:**
- [ ] Hacker News: "Show HN: VibrantFrog - macOS AI Chat with MCP Support"
- [ ] Reddit:
  - [ ] /r/MacApps
  - [ ] /r/LocalLLaMA
  - [ ] /r/ollama
- [ ] Product Hunt (optional)
- [ ] MCP Community Discord/Slack

**Blog Post Ideas:**
1. "Introducing VibrantFrog: AI Chat with MCP for macOS"
2. "How We Built VibrantFrog with SwiftUI and Ollama"
3. "Understanding the Model Context Protocol"

### 5. Website Launch

- [ ] Deploy landing page to spiderink.net or forgoteam.ai
- [ ] Add link to GitHub repository
- [ ] Set up analytics
- [ ] Create social share cards

## Post-Release

### Immediate (Week 1)

- [ ] Monitor GitHub Issues
- [ ] Respond to questions in Discussions
- [ ] Track analytics and downloads
- [ ] Collect user feedback
- [ ] Update documentation based on questions

### Short-term (Month 1)

- [ ] Release v1.0.1 with bug fixes
- [ ] Address top community requests
- [ ] Write blog posts about development
- [ ] Create tutorial videos
- [ ] Expand MCP server compatibility

### Long-term Roadmap

- [ ] Streaming response support
- [ ] Stdio MCP transport
- [ ] Custom model parameters UI
- [ ] Conversation export (Markdown, PDF)
- [ ] Plugin system for MCP servers
- [ ] Cross-platform support (iOS, Linux)

## Quality Gates

### Before Pushing to GitHub:

✅ All tests pass
✅ No compiler warnings
✅ Documentation complete
✅ Screenshots added to README
✅ No sensitive data in repo
✅ License file present
✅ .gitignore properly configured

### Before Creating Release:

✅ Version number updated
✅ Git tag created
✅ Release notes written
✅ Tested on fresh Mac
✅ All known issues documented
✅ Contributing guide reviewed

### Before Public Announcement:

✅ Website live
✅ GitHub repository public
✅ Release published
✅ Social share cards created
✅ Announcement posts drafted

## Emergency Rollback Plan

If critical issues are discovered after release:

1. **Immediate:**
   - Add warning to README
   - Pin issue in GitHub
   - Post in Discussions

2. **Short-term:**
   - Create hotfix branch
   - Fix critical bug
   - Release v1.0.1 ASAP

3. **Communication:**
   - Be transparent about the issue
   - Provide timeline for fix
   - Thank users for reporting

## Metrics to Track

**GitHub:**
- Stars
- Forks
- Issues opened/closed
- Pull requests
- Traffic (clones, visitors)

**Website:**
- Page views
- Download clicks
- Time on page
- Bounce rate

**Community:**
- Reddit upvotes/comments
- Hacker News points
- Social media engagement

---

## Quick Reference Commands

```bash
# Clean build
cd VibrantFrogApp
xcodebuild clean
xcodebuild -scheme VibrantFrog -configuration Release build

# Create release tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# Create archive (for binary distribution)
xcodebuild -scheme VibrantFrog -configuration Release archive \
  -archivePath ~/Desktop/VibrantFrog.xcarchive

# Export app
xcodebuild -exportArchive \
  -archivePath ~/Desktop/VibrantFrog.xcarchive \
  -exportPath ~/Desktop/VibrantFrog \
  -exportOptionsPlist ExportOptions.plist
```

---

**Ready to Release? 🚀**

Once all items are checked, you're ready to share VibrantFrog with the world!
