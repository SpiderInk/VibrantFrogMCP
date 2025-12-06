# Contributing to VibrantFrog

First off, thank you for considering contributing to VibrantFrog! It's people like you that make VibrantFrog such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by respect, professionalism, and collaboration. By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When you create a bug report, include as many details as possible:

**Bug Report Template:**
```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. See error

**Expected behavior**
What you expected to happen.

**Screenshots**
If applicable, add screenshots.

**Environment:**
 - macOS Version: [e.g. Sonoma 14.2]
 - VibrantFrog Version: [e.g. 1.0]
 - Ollama Version: [e.g. 0.1.17]
 - Model: [e.g. mistral-nemo:latest]

**Logs**
Paste relevant logs from Console.app or Xcode console.
```

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, include:

- **Clear title and description**
- **Use case** - Why would this be useful?
- **Proposed solution** - How might it work?
- **Alternatives considered** - What other approaches did you think about?

### Pull Requests

#### Development Setup

1. **Fork and clone**
   ```bash
   git clone https://github.com/YOUR_USERNAME/VibrantFrog.git
   cd VibrantFrog
   ```

2. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow the Swift style guide (see below)
   - Write clear commit messages
   - Add tests if applicable
   - Update documentation

4. **Test your changes**
   ```bash
   # Build
   cd VibrantFrogApp
   xcodebuild -scheme VibrantFrog -configuration Debug build

   # Run tests
   xcodebuild -scheme VibrantFrog -configuration Debug test
   ```

5. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   ```
   Then create a pull request on GitHub.

#### Pull Request Guidelines

- **Title**: Use a clear, descriptive title
- **Description**: Explain what changes you made and why
- **Link issues**: Reference any related issues with `Fixes #123`
- **Small PRs**: Keep PRs focused on a single feature/fix
- **Documentation**: Update README.md if you change functionality
- **Tests**: Add tests for new features

**PR Template:**
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
How did you test these changes?

## Checklist
- [ ] Code follows Swift style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Documentation updated
- [ ] No new warnings
- [ ] Tests added/updated
```

## Style Guidelines

### Swift Code Style

**General Principles:**
- Follow Apple's [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use SwiftLint for consistency (configuration coming soon)
- Prefer clarity over brevity

**Naming:**
```swift
// Good
func fetchUserProfile(for userID: String) async throws -> UserProfile

// Bad
func get(id: String) async throws -> UserProfile
```

**SwiftUI:**
```swift
// Extract complex views into separate structs
struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading) {
            messageContent
            messageMetadata
        }
    }

    private var messageContent: some View {
        Text(message.content)
    }

    private var messageMetadata: some View {
        Text(message.timestamp, style: .time)
            .font(.caption)
    }
}
```

**Async/Await:**
```swift
// Prefer async/await over completion handlers
func loadData() async throws -> Data {
    try await URLSession.shared.data(from: url).0
}

// Use Task for concurrent operations
Task {
    async let user = fetchUser()
    async let posts = fetchPosts()

    let (userData, postsData) = try await (user, posts)
}
```

**Error Handling:**
```swift
// Provide context in errors
enum MCPError: LocalizedError {
    case connectionFailed(String)
    case toolNotFound(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let server):
            return "Failed to connect to MCP server: \(server)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        }
    }
}
```

**Logging:**
```swift
// Use descriptive emoji prefixes for log categorization
print("🔄 Loading model: \(modelName)")  // Process/action
print("✅ Model loaded successfully")     // Success
print("❌ Failed to load model: \(error)") // Error
print("⚠️ Model not found, using default") // Warning
print("🔥 Priming model for tool calling") // Special operation
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): subject

body

footer
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `style:` Formatting, missing semicolons, etc.
- `refactor:` Code change that neither fixes a bug nor adds a feature
- `perf:` Performance improvement
- `test:` Adding tests
- `chore:` Maintain

**Examples:**
```
feat(chat): add streaming response support

Implement server-sent events for real-time streaming
of LLM responses in the chat interface.

Closes #42
```

```
fix(mcp): prevent tool calls on cold start

Add warmup request after system message regeneration
to prime the model for immediate tool use.

Fixes #127
```

## Project Structure

Understanding the codebase:

```
VibrantFrog/
├── Models/                  # Data models
│   ├── Conversation.swift   # Chat conversation model
│   ├── Photo.swift          # Photo library model
│   └── PromptTemplate.swift # Template system
│
├── Views/                   # SwiftUI views
│   ├── AIChatView.swift     # Main chat interface
│   ├── MCPManagementView.swift  # MCP configuration
│   └── ...
│
├── Services/                # Business logic
│   ├── OllamaService.swift  # Ollama API client
│   ├── MCPClientHTTP.swift  # MCP protocol
│   ├── ConversationStore.swift  # Persistence
│   └── ...
│
└── VibrantFrogApp.swift     # App entry point
```

**Key architectural decisions:**
- **MVVM pattern** - Views observe ViewModels via `@StateObject`/@ObservedObject
- **Service layer** - Business logic separated from UI
- **Protocol-oriented** - Use protocols for testability
- **Async/await first** - No completion handlers for new code

## Testing

### Unit Tests
```swift
import XCTest
@testable import VibrantFrog

final class OllamaServiceTests: XCTestCase {
    func testModelLoading() async throws {
        let service = OllamaService()
        await service.checkAvailability()
        XCTAssertFalse(service.availableModels.isEmpty)
    }
}
```

### Manual Testing Checklist

Before submitting a PR, test:

- [ ] App launches without crash
- [ ] Chat sends and receives messages
- [ ] Model selection persists across tab switches
- [ ] MCP server connects successfully
- [ ] Tool calls execute properly
- [ ] Conversation history saves/loads
- [ ] No memory leaks (use Instruments)
- [ ] No console warnings/errors

## Documentation

### Code Comments

```swift
/// Primes the model for tool calling with a warmup request.
///
/// This prevents the "cold start" issue where the first user request
/// may not utilize available tools. The warmup exchange is not added
/// to conversation history to keep the chat clean.
///
/// - Parameter mcpClient: The connected MCP client with available tools
/// - Throws: Non-critical errors are logged but don't fail the operation
private func primeModelForToolCalling(mcpClient: MCPClientHTTP) async {
    // Implementation
}
```

### README Updates

When adding features, update:
- Feature list in README.md
- Quick Start guide if applicable
- Configuration section for new settings
- Troubleshooting for common issues

## Release Process

(For maintainers)

1. Update version in `VibrantFrogApp.swift`
2. Update CHANGELOG.md
3. Create git tag: `git tag -a v1.0.0 -m "Release 1.0.0"`
4. Push tag: `git push origin v1.0.0`
5. Create GitHub release with notes
6. Update website

## Questions?

- Open an issue for questions about contributing
- Check existing issues and PRs for similar discussions
- Join our community discussions

## Recognition

Contributors will be:
- Listed in CONTRIBUTORS.md
- Mentioned in release notes
- Credited in the About panel (for significant contributions)

---

Thank you for contributing to VibrantFrog! 🐸
