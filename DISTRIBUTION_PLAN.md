# VibrantFrog Distribution Plan

## Executive Summary

VibrantFrog is production-ready for open source distribution. This document outlines the complete path from current state to public release on GitHub under the SpiderInk organization.

**Timeline Estimate:** 2-3 days for preparation, immediate release capability
**Distribution Model:** Open source (MIT License) via GitHub
**Target Audience:** AI enthusiasts, macOS developers, MCP protocol adopters, local LLM users

---

## Current State Analysis

### What's Complete ✅

**Core Application:**
- Native macOS app with SwiftUI
- AI chat with Ollama integration
- Full MCP HTTP protocol support
- Photo library indexing with ChromaDB
- Conversation persistence and history
- Prompt template system
- Developer tools interface
- Vision model support (LLaVA)
- Sandbox disabled for file system access

**Documentation:**
- README.md with installation and usage
- ARCHITECTURE.md with technical details
- CONTRIBUTING.md with development guidelines
- LICENSE (MIT)
- Release checklist prepared

**Technical Foundation:**
- Clean Swift codebase with async/await
- Proper error handling throughout
- Comprehensive logging for debugging
- State management with Combine
- Modular architecture

### What Needs Attention ⚠️

**Critical for Release:**
1. **Screenshots** - Need app screenshots for README
2. **Hardcoded Paths** - Remove personal paths from code
3. **Bundle Identifier** - Set to `com.spiderink.vibrantfrog`
4. **Version Number** - Set to `1.0.0` in app
5. **GitHub Repository** - Create under SpiderInk org

**Nice to Have:**
- Demo video/GIF showing features
- More prompt templates
- Better error messages for end users
- Installation script or DMG

---

## Distribution Strategy

### Phase 1: Open Source Release (Recommended First Step)

**Platform:** GitHub (SpiderInk organization)
**License:** MIT (already in place)
**Distribution:** Source code only initially

**Advantages:**
- No notarization/signing requirements
- Community can build and modify
- Transparent development
- Easy to iterate based on feedback
- Lower barrier to contribution

**Process:**
1. Create GitHub repository
2. Push code with proper .gitignore
3. Create v1.0.0 release with release notes
4. Announce on relevant communities

### Phase 2: Binary Distribution (Optional, Later)

**Platform:** GitHub Releases + Homebrew Cask
**Requirements:**
- Apple Developer ID for code signing ($99/year)
- Notarization via Apple
- DMG installer creation
- Update mechanism

**Timeline:** 2-4 weeks after initial release
**Why Wait:** Gather feedback, fix bugs, validate demand

### Phase 3: Community Growth (Ongoing)

**Platforms:**
- GitHub (primary)
- Hacker News
- Reddit (r/MacApps, r/LocalLLaMA, r/ollama)
- MCP Community forums
- Twitter/X, Mastodon

---

## Pre-Release Tasks

### 1. Code Cleanup (2-3 hours)

**Remove Hardcoded Paths:**

Current hardcoded paths to fix:
```swift
// MCPClientHTTP.swift line 36
serverScriptPath: String = "/Users/tpiazza/git/VibrantFrogMCP/vibrant_frog_mcp.py"

// Various files referencing personal directories
/Users/tpiazza/...
```

**Solution:**
- Use bundle resources for included files
- Make MCP server path configurable via Settings
- Use `FileManager` to find appropriate directories
- Add environment variable support

**Files to Update:**
- `MCPClientHTTP.swift` - Server script path
- `PhotoLibraryService.swift` - Check for any hardcoded paths
- `ConversationStore.swift` - Verify data directories
- Any logging or debug code with personal info

### 2. Bundle Configuration (30 minutes)

**Update Info.plist / Build Settings:**
```
Bundle Identifier: com.spiderink.vibrantfrog
Version: 1.0.0
Build: 1
Display Name: VibrantFrog
Copyright: © 2025 SpiderInk
```

**Entitlements Check:**
- ✅ Photo Library access
- ✅ Network client
- ✅ Sandbox disabled (documented reason)

### 3. Screenshots and Assets (1 hour)

**Required Screenshots:**

1. **Hero Shot** (main README image)
   - AI Chat interface with active conversation
   - Tool calls visible
   - Clean, professional appearance

2. **Feature Screenshots:**
   - Photo Intelligence (search results with thumbnails)
   - MCP Server Management UI
   - Prompt Templates library
   - Developer Tools interface
   - Conversation History

3. **Demo GIF** (optional but highly recommended)
   - 30-second walkthrough
   - Shows: model selection → question → tool call → result
   - Screen recording with QuickTime, convert to GIF

**Asset Location:**
```
/assets/
  screenshots/
    hero.png
    chat-interface.png
    photo-search.png
    mcp-management.png
    prompts.png
    developer-tools.png
  demo/
    demo.gif
  icon/
    app-icon-1024.png
```

### 4. Documentation Review (1 hour)

**README.md Updates:**
- Add screenshots (embed from assets folder)
- Update GitHub URLs (currently placeholder)
- Add "Known Issues" section
- Verify all installation steps work on fresh Mac

**ARCHITECTURE.md:**
- Review for accuracy
- Add diagrams if possible
- Explain MCP integration clearly

**CONTRIBUTING.md:**
- Add code style guidelines
- Explain PR process
- List good first issues

**New Documents to Create:**
- `CHANGELOG.md` - Version history starting with 1.0.0
- `SECURITY.md` - Security policy and vulnerability reporting
- `CODE_OF_CONDUCT.md` - Community guidelines (optional)

### 5. Remove Sensitive Data (30 minutes)

**Scan for:**
- API keys or credentials
- Personal file paths
- Internal URLs or IP addresses
- Email addresses (except public contact)
- Debug statements with sensitive info

**Tools:**
```bash
# Search for common sensitive patterns
grep -r "password" .
grep -r "api_key" .
grep -r "/Users/tpiazza" .
grep -r "TODO" . | grep -i "fix\|hack\|temp"
```

### 6. GitHub Repository Setup (1 hour)

**Create Repository:**
- Organization: SpiderInk
- Name: VibrantFrog
- Description: "Native macOS AI Chat with Model Context Protocol Support"
- Public visibility
- Topics: `macos`, `ai-chat`, `mcp`, `ollama`, `swiftui`, `swift`, `model-context-protocol`, `llm`

**Repository Configuration:**
- Enable Issues
- Enable Discussions
- Enable GitHub Pages (for potential landing page)
- Configure branch protection for `main`
- Add repository description and website link

**GitHub Templates:**

Create `.github/` folder with:

**`.github/ISSUE_TEMPLATE/bug_report.md`:**
```markdown
---
name: Bug Report
about: Report a bug or issue
title: '[BUG] '
labels: bug
---

**Description**
A clear description of the bug.

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

**Logs**
Paste relevant console output here.
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
Describe the feature you'd like to see.

**Use Case**
Why would this be valuable?

**Possible Implementation**
Any ideas on how this could work?
```

**`.github/PULL_REQUEST_TEMPLATE.md`:**
```markdown
## Description
Describe your changes.

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

---

## Release Process

### Step 1: Final Code Review (1 hour)

```bash
cd /Users/tpiazza/git/VibrantFrogMCP

# Ensure all changes committed
git status

# Review recent changes
git log --oneline -20

# Check for large files
find . -type f -size +10M | grep -v ".git"

# Verify .gitignore
cat .gitignore
```

### Step 2: Version Bump (15 minutes)

Update version in code:
```swift
// VibrantFrogApp.swift or Info.plist
let version = "1.0.0"
```

Commit version bump:
```bash
git add .
git commit -m "chore: bump version to 1.0.0 for initial release"
```

### Step 3: Create Git Tag (5 minutes)

```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release v1.0.0 - Initial public release"

# Verify tag
git tag -l
git show v1.0.0
```

### Step 4: Push to GitHub (10 minutes)

```bash
# Add remote (if new repo)
git remote add origin https://github.com/SpiderInk/VibrantFrog.git

# Push code
git push origin main

# Push tags
git push origin v1.0.0
```

### Step 5: Create GitHub Release (30 minutes)

**Navigate to:** GitHub → Releases → Draft a new release

**Tag:** v1.0.0
**Title:** VibrantFrog v1.0.0 - Initial Release

**Release Notes:**

```markdown
# 🐸 VibrantFrog v1.0.0

**The first public release of VibrantFrog is here!**

VibrantFrog brings AI-powered conversations to macOS with full support for the Model Context Protocol (MCP), enabling AI models to interact with external services, search your photo library, and execute custom tools.

## ✨ Features

### AI Chat Interface
- **Native macOS Experience** - Built with SwiftUI for seamless integration
- **Powered by Ollama** - Run AI models locally with privacy
- **Multi-Model Support** - Works with Mistral, Llama, and other Ollama models
- **Conversation History** - All chats saved and searchable
- **Photo Attachments** - Attach and discuss images in conversations

### Model Context Protocol (MCP)
- **Full MCP Support** - HTTP transport implementation
- **Tool Calling** - AI can execute functions via MCP servers
- **Dynamic Discovery** - Automatically detects available tools
- **Custom Servers** - Connect to any MCP-compatible server
- **Developer Tools** - Test and debug tool calls directly

### Photo Intelligence
- **Apple Photos Integration** - Index your entire photo library
- **AI Descriptions** - Automatic photo captioning with LLaVA vision model
- **Vector Search** - Find photos by semantic meaning, not just metadata
- **ChromaDB Backend** - Fast, local vector database
- **Privacy First** - All processing happens on your Mac

### Smart Prompts
- **Template Library** - Pre-built prompts for common tasks
- **Variable Substitution** - Dynamic {{TOOLS}} and {{MCP_SERVER_NAME}} insertion
- **Customizable** - Create and save your own templates
- **Context Aware** - Prompts adapt to selected MCP server

## 🚀 Quick Start

### 1. Install Ollama
```bash
brew install ollama
ollama serve
ollama pull mistral-nemo:latest
```

### 2. Build VibrantFrog
```bash
git clone https://github.com/SpiderInk/VibrantFrog.git
cd VibrantFrog/VibrantFrogApp
open VibrantFrog.xcodeproj
# Build and run (⌘R)
```

### 3. Start Chatting
- Select `mistral-nemo:latest` model
- Ask questions and watch the AI use tools!

## 📚 Documentation

- **[README](https://github.com/SpiderInk/VibrantFrog#readme)** - Installation and features
- **[Architecture Guide](./ARCHITECTURE.md)** - Technical deep dive
- **[Contributing](./CONTRIBUTING.md)** - How to contribute
- **[Distribution Plan](./DISTRIBUTION_PLAN.md)** - Release roadmap

## 🐛 Known Issues

### Tool Use on First Request
**Issue:** First chat after app launch may not use tools
**Workaround:** Model is now "primed" automatically on startup (may need second request in some cases)
**Status:** Investigating improvement for 100% first-try reliability

### Sandbox Disabled
**Issue:** App runs without sandbox to access shared ChromaDB
**Impact:** App has full filesystem access
**Status:** Acceptable for v1.0 (personal use), will address in future release

### No Binary Distribution
**Issue:** Users must build from source
**Workaround:** Follow Quick Start instructions above
**Status:** Binary releases planned after community feedback

## 🔮 Roadmap

**v1.1 - Stability & Polish** (Next)
- Streaming response support
- Improved error messages
- First-request tool use reliability
- UI refinements

**v1.2 - Feature Expansion**
- Stdio MCP transport
- Conversation export (Markdown, PDF)
- Custom model parameters UI
- More prompt templates

**v2.0 - Platform Growth**
- Pre-built binaries (DMG)
- Homebrew Cask distribution
- Plugin system for MCP servers
- iOS companion app (maybe!)

## 🙏 Acknowledgments

Built with love using:
- **[Ollama](https://ollama.ai)** - Local LLM inference
- **[Model Context Protocol](https://modelcontextprotocol.io)** - Tool calling standard
- **[ChromaDB](https://www.trychroma.com)** - Vector database
- **SwiftUI** - Modern Swift UI framework

Special thanks to the MCP community for creating an amazing protocol!

## 📝 License

VibrantFrog is released under the [MIT License](./LICENSE).

## 💬 Support

- **Issues:** [Report bugs](https://github.com/SpiderInk/VibrantFrog/issues)
- **Discussions:** [Ask questions](https://github.com/SpiderInk/VibrantFrog/discussions)
- **Website:** [spiderink.net](https://spiderink.net)

---

**Full Changelog**: https://github.com/SpiderInk/VibrantFrog/commits/v1.0.0

Made with ❤️ by SpiderInk
```

**Assets:**
- Attach screenshots if creating binary release
- Link to demo video if available

### Step 6: Announcement Strategy (2-3 hours)

**GitHub:**
- Pin the v1.0.0 release
- Create welcome discussion post
- Enable GitHub Discussions

**Hacker News:**
Post: "Show HN: VibrantFrog - Native macOS AI Chat with MCP Support"

Key points:
- Built for local LLM privacy
- Full MCP protocol implementation
- Photo library integration is unique
- Open source MIT license

**Reddit:**

Post to:
- r/MacApps - Focus on native macOS experience
- r/LocalLLaMA - Focus on Ollama integration
- r/ollama - Direct Ollama audience
- r/selfhosted - Privacy angle

**Social Media:**

Twitter/X example:
```
🐸 VibrantFrog v1.0.0 is here!

Native macOS AI chat with:
✅ Ollama integration
✅ MCP tool calling
✅ Photo library search
✅ Privacy-first (runs locally)

Open source • MIT license

→ github.com/SpiderInk/VibrantFrog

#AI #macOS #OpenSource #MCP
```

LinkedIn (professional angle):
```
Excited to release VibrantFrog 1.0! 🐸

A native macOS application demonstrating the Model Context Protocol (MCP)
in action. Built with SwiftUI, powered by local Ollama models.

Key features:
- Full MCP HTTP transport implementation
- ChromaDB vector search integration
- Privacy-focused local AI processing

Perfect for developers exploring MCP or users wanting AI chat
without cloud dependencies.

GitHub: [link]
```

**MCP Community:**
- Post in MCP Discord/Slack
- Share on MCP forums
- Reach out to MCP protocol maintainers

**Blog Post Ideas:**

1. **"Introducing VibrantFrog"** (Launch announcement)
2. **"Building a Native MCP Client in Swift"** (Technical deep-dive)
3. **"Privacy-First AI: Running Everything Locally"** (User privacy angle)
4. **"MCP Protocol Explained Through VibrantFrog"** (Educational)

---

## Post-Release Plan

### Week 1: Active Monitoring

**Daily Tasks:**
- Respond to GitHub Issues within 24 hours
- Monitor Discussions for questions
- Track social media mentions
- Collect feedback in a document

**Metrics to Track:**
- GitHub stars
- Issue count (bugs vs features)
- Community questions/themes
- Download/clone counts

### Week 2-4: Iteration

**Bug Fix Priority:**
1. Crashes or data loss (critical)
2. Features not working as documented (high)
3. UX issues (medium)
4. Enhancement requests (low)

**Release v1.0.1:**
- Address critical bugs
- Improve documentation based on questions
- Add FAQ to README
- Consider quick wins from feature requests

### Month 2: Feature Development

**Based on Community Feedback:**
- Most requested features
- Common pain points
- Integration opportunities

**Potential v1.1 Features:**
- Streaming responses (highly requested)
- Binary distribution (if demand is high)
- More MCP server examples
- Video tutorials

### Long-Term: Community Building

**Content Creation:**
- Tutorial videos on YouTube
- Blog posts about implementation
- Conference talks about MCP

**Partnerships:**
- Collaborate with other MCP projects
- Integration with popular MCP servers
- Ollama community engagement

---

## Distribution Alternatives

### Option 1: GitHub Only (Recommended Start)
**Pros:**
- Immediate release
- No overhead
- Easy to iterate
- Community can fork/modify

**Cons:**
- Users must build from source
- Lower adoption threshold
- Requires Xcode

**Best for:** Technical audience, initial validation

### Option 2: Homebrew Cask
**Timeline:** 2-4 weeks after initial release
**Requirements:**
- Create DMG installer
- Code sign with Developer ID
- Submit to homebrew-cask

**Installation:**
```bash
brew install --cask vibrantfrog
```

**Pros:**
- One-line installation
- Automatic updates possible
- Familiar to Mac developers
- No App Store restrictions

**Cons:**
- Requires Developer ID ($99/year)
- Notarization process
- DMG creation complexity

### Option 3: Mac App Store
**Timeline:** 3-6 months (if desired)
**Requirements:**
- Apple Developer Program ($99/year)
- App Review compliance
- Sandbox properly
- Full notarization

**Pros:**
- Maximum distribution
- Built-in updates
- User trust

**Cons:**
- Strict review process
- Sandbox limitations (ChromaDB access issue)
- 30% revenue share (if paid)
- Slower iteration

**Recommendation:** Skip for now due to sandbox constraints

### Option 4: Direct Download (GitHub Releases)
**Timeline:** 1-2 weeks after initial release
**Requirements:**
- Create DMG
- Code sign (recommended, not required)
- Notarize (recommended)

**Process:**
```bash
# Create release build
xcodebuild -scheme VibrantFrog -configuration Release archive

# Export as app
xcodebuild -exportArchive -archivePath ~/Desktop/VibrantFrog.xcarchive \
  -exportPath ~/Desktop/VibrantFrog -exportOptionsPlist ExportOptions.plist

# Create DMG
hdiutil create -volname "VibrantFrog" -srcfolder ~/Desktop/VibrantFrog/VibrantFrog.app \
  -ov -format UDZO ~/Desktop/VibrantFrog-1.0.0.dmg
```

**Attach DMG to GitHub Release**

**Pros:**
- Direct distribution
- No third-party dependency
- User-friendly installation

**Cons:**
- Unsigned apps show warning on first launch
- No automatic updates
- Manual download process

---

## Success Metrics

### Immediate (Week 1)
- ✅ 50+ GitHub stars
- ✅ 10+ discussions/issues
- ✅ No critical bugs reported
- ✅ 5+ social media shares

### Short-term (Month 1)
- ✅ 200+ GitHub stars
- ✅ 50+ clones/downloads
- ✅ 3+ community contributions (PRs)
- ✅ Mentioned in MCP community
- ✅ v1.0.1 released with bug fixes

### Medium-term (Month 3)
- ✅ 500+ GitHub stars
- ✅ 100+ active users
- ✅ 10+ contributors
- ✅ Featured on Hacker News
- ✅ v1.1 with major features

### Long-term (Month 6)
- ✅ 1000+ stars
- ✅ Active community
- ✅ Binary distribution available
- ✅ Integration with popular MCP servers
- ✅ Conference presentation or blog features

---

## Budget Considerations

### Free Distribution (Recommended Start)
**Costs:** $0
- GitHub hosting (free for open source)
- Domain if desired ($10-20/year)

### Binary Distribution
**Costs:** $99/year minimum
- Apple Developer ID ($99/year)
- Optional: Code signing certificate
- Optional: Website hosting ($5-10/month)

### Full Commercial
**Costs:** $200-500/year
- All of the above
- Marketing budget
- Potential server costs (if cloud features added)

**Recommendation:** Start with free distribution, evaluate demand before investing

---

## Risk Assessment

### Technical Risks

**Risk:** Sandbox limitations prevent future App Store distribution
**Mitigation:** Document well, design alternative architectures, consider stdio MCP transport

**Risk:** Hardcoded paths break for other users
**Mitigation:** Make all paths configurable, use environment variables, test on clean Mac

**Risk:** Ollama API changes break integration
**Mitigation:** Version pin, monitor Ollama releases, test before updating

### Community Risks

**Risk:** Low adoption, no community interest
**Mitigation:** Niche is real (MCP + macOS + local AI), target marketing, provide value

**Risk:** Negative feedback on missing features
**Mitigation:** Set expectations clearly, rapid iteration, transparent roadmap

**Risk:** Security vulnerabilities discovered
**Mitigation:** Create SECURITY.md, respond quickly, release patches ASAP

### Legal Risks

**Risk:** Trademark issues with "VibrantFrog" name
**Mitigation:** Name appears unique, MIT license protects contributors

**Risk:** Photo library access privacy concerns
**Mitigation:** Clear privacy policy, all processing local, user consent required

---

## Timeline Summary

### Immediate (This Week)
- [ ] Remove hardcoded paths (2-3 hours)
- [ ] Take screenshots (1 hour)
- [ ] Update bundle configuration (30 min)
- [ ] Final documentation review (1 hour)
- [ ] Create GitHub repository (1 hour)
- [ ] **Total:** ~1 day of focused work

### Week 1 (Launch Week)
- [ ] Push code to GitHub
- [ ] Create v1.0.0 release
- [ ] Post announcements (HN, Reddit, social)
- [ ] Monitor and respond to feedback
- [ ] Fix any critical issues immediately

### Week 2-4 (Stabilization)
- [ ] Address bug reports
- [ ] Improve documentation based on questions
- [ ] Release v1.0.1 with fixes
- [ ] Continue community engagement

### Month 2 (Growth)
- [ ] Add most-requested features
- [ ] Create tutorial content
- [ ] Consider binary distribution
- [ ] Release v1.1

---

## Conclusion

VibrantFrog is **ready for distribution** with minimal preparation work. The open source approach via GitHub is the best first step:

1. **Low friction** - No approval processes or fees
2. **Fast iteration** - Can release updates immediately
3. **Community building** - Encourage contributions
4. **Validation** - Test market interest before investing in binary distribution

**Recommended Action Plan:**
1. Spend 1 day removing hardcoded paths and taking screenshots
2. Push to GitHub and create v1.0.0 release
3. Announce on Hacker News and Reddit
4. Monitor feedback for 2-4 weeks
5. Decide on binary distribution based on demand

**Is it worth distributing?**

**YES.** VibrantFrog fills a real need:
- Native macOS MCP client (few alternatives)
- Privacy-focused local AI
- Photo library integration is unique
- Well-built, documented, and functional

The niche exists, the app works, and the timing is good with rising interest in MCP and local AI. Distribution risk is minimal (no costs), and potential upside is significant (community, portfolio, learning, potential commercial opportunities later).

**Next Step:** Execute the pre-release tasks checklist above, then push the button. 🚀
