# Changelog

All notable changes to VibrantFrog will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- App sandbox disabled to access shared ChromaDB cache file
- Indexed photo count now displays correctly in IndexingView

## [1.0.0] - 2025-12-21

### Added
- Initial public release
- Native macOS AI chat interface with SwiftUI
- Ollama integration for local LLM inference
- Full MCP HTTP transport protocol implementation
- Photo library indexing with AI descriptions (LLaVA vision model)
- ChromaDB vector database for semantic photo search
- Conversation history with persistence
- Prompt template system with variable substitution
- MCP server management UI
- Developer tools for testing tool calls
- Photo attachment support in conversations
- Multi-tab interface with state persistence
- Comprehensive logging for debugging

### Core Features
- **AI Chat**: Conversation interface with multiple Ollama models
- **MCP Integration**: Connect to MCP servers, discover tools, execute tool calls
- **Photo Intelligence**: Index Apple Photos library, search by semantic meaning
- **Smart Prompts**: Customizable templates with {{TOOLS}} and {{MCP_SERVER_NAME}} variables
- **Developer Tools**: Direct tool calling interface for testing

### Technical
- Swift 5.9+ with modern async/await patterns
- SwiftUI lifecycle and Combine framework
- HTTP networking via URLSession
- Photos Framework integration
- Vision Framework for image analysis
- UserDefaults for settings persistence

### Documentation
- README.md with installation and usage guide
- ARCHITECTURE.md with technical details
- CONTRIBUTING.md with development guidelines
- DISTRIBUTION_PLAN.md with release strategy
- LICENSE (MIT)

### Known Issues
- First chat request after app launch may not use tools (model warmup added but not 100% reliable)
- No streaming response support yet
- Only HTTP MCP transport (stdio planned for v1.1)
- App sandbox disabled for file system access (required for ChromaDB)
- Hardcoded paths need to be made configurable

---

## Version History

- **1.0.0** (2025-12-21) - Initial public release
