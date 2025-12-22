# Security Policy

## Supported Versions

Currently supported versions of VibrantFrog:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Considerations

### App Sandbox Status

**VibrantFrog currently runs without macOS App Sandbox** (`com.apple.security.app-sandbox = false`)

**Reason:** The app needs to access ChromaDB vector database files located outside the app's container directory. The MCP Python server writes to `~/Library/Application Support/VibrantFrogMCP/`, which is not accessible from within a sandbox.

**Implications:**
- App has full filesystem access
- Appropriate for personal/development use
- Not suitable for App Store distribution in current form

**Future Plan:**
- v1.1+ will explore shared container approach or stdio MCP transport to enable proper sandboxing

### Photo Library Access

VibrantFrog requests access to your Apple Photos library via the `com.apple.security.personal-information.photos-library` entitlement.

**What We Do:**
- Read photo metadata and thumbnails
- Generate AI descriptions using local LLaVA model
- Store embeddings in local ChromaDB

**What We Don't Do:**
- Upload photos to any cloud service
- Share photo data with third parties
- Transmit photo content over network
- Store unencrypted personal information

**Privacy Guarantee:** All photo processing happens locally on your Mac using Ollama.

### Network Access

VibrantFrog makes network connections to:

1. **Ollama API** (localhost:11434) - Required for AI model inference
2. **MCP Servers** - User-configured endpoints for tool calling
3. **Optional:** AWS MCP Server or other third-party MCP services if user enables them

**We Never:**
- Send data to analytics services
- Include telemetry or tracking
- Phone home or auto-update without consent

### Data Storage

VibrantFrog stores data locally in:

```
~/Library/Application Support/VibrantFrogMCP/
  ├── chroma_db/           # Photo embeddings (ChromaDB)
  ├── indexed_photos.json  # List of indexed photo UUIDs
  └── conversations/       # Chat history (UserDefaults)
```

**Security Notes:**
- Files stored unencrypted (macOS FileVault recommended)
- No cloud sync or backup (user responsibility)
- Conversations may contain sensitive information - secure your Mac

### Code Execution

VibrantFrog includes these entitlements for Ollama integration:

```xml
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<true/>
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

**Purpose:** Required for Ollama's Python-based LLM execution.

**Risk:** Allows execution of unsigned code (Ollama models).

**Mitigation:** Only use trusted Ollama models from official sources.

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability in VibrantFrog:

### How to Report

**Email:** security@spiderink.net (or open a private security advisory on GitHub)

**Please Include:**
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if you have one)

### What to Expect

1. **Acknowledgment:** Within 48 hours
2. **Initial Assessment:** Within 1 week
3. **Fix Timeline:** Critical issues within 2 weeks, others within 30 days
4. **Disclosure:** Coordinated disclosure after fix is released

### Responsible Disclosure

We ask that you:
- Give us reasonable time to address the issue before public disclosure
- Don't exploit the vulnerability beyond proof-of-concept
- Don't access or modify other users' data

We commit to:
- Keep you informed of our progress
- Credit you in release notes (if desired)
- Not take legal action against good-faith security researchers

## Security Best Practices

### For Users

1. **Keep macOS Updated:** Ensure you're running latest security patches
2. **Enable FileVault:** Encrypt your disk to protect local data
3. **Verify MCP Servers:** Only connect to trusted MCP endpoints
4. **Review Permissions:** Check app permissions in System Settings
5. **Secure Your Mac:** Use strong password, enable firewall

### For Developers

1. **Review Code:** Audit changes before submitting PRs
2. **Sanitize Inputs:** Validate all user input and external data
3. **Avoid Hardcoding:** Never commit API keys or credentials
4. **Test Security:** Check for common vulnerabilities (XSS, injection, etc.)
5. **Update Dependencies:** Keep Ollama and other dependencies current

## Known Security Limitations

### Current Version (1.0.0)

1. **No App Sandbox**
   - Impact: High (full filesystem access)
   - Mitigation: Personal use only, trusted environment
   - Timeline: Address in v1.1+

2. **Unencrypted Local Storage**
   - Impact: Medium (data readable if Mac compromised)
   - Mitigation: Enable FileVault, secure physical access
   - Timeline: Consider encryption in v2.0

3. **MCP Server Trust**
   - Impact: Varies (depends on configured servers)
   - Mitigation: Only use trusted MCP endpoints
   - Timeline: Add server verification in v1.2

4. **No Code Signing**
   - Impact: Low (source distribution only)
   - Mitigation: Build from source, review code
   - Timeline: Sign binaries when released

## Compliance

VibrantFrog is designed for personal use and makes no claims of compliance with:
- HIPAA (healthcare data)
- GDPR (EU data protection)
- SOC 2 (security controls)
- Other regulatory frameworks

**If you need compliance:** Deploy in a compliant environment and review data handling carefully.

## Security Roadmap

### v1.1 (Q1 2025)
- [ ] Configurable ChromaDB path (enable sandboxing)
- [ ] MCP server allowlist configuration
- [ ] Security audit of networking code

### v1.2 (Q2 2025)
- [ ] Optional conversation encryption
- [ ] Server certificate validation for MCP
- [ ] Audit logging for tool execution

### v2.0 (Future)
- [ ] Full App Sandbox support
- [ ] Code signing and notarization
- [ ] Security documentation expansion

## Third-Party Security

VibrantFrog relies on:

- **Ollama** - https://github.com/ollama/ollama
  - Used for: LLM inference
  - Security: Review Ollama's security policy

- **ChromaDB** - https://github.com/chroma-core/chroma
  - Used for: Vector embeddings storage
  - Security: Local only, no network access

- **Apple Photos Framework** - https://developer.apple.com/documentation/photos
  - Used for: Photo library access
  - Security: System-protected with user consent

We do not control the security of these dependencies. Review their policies independently.

## Questions?

Security questions? Contact security@spiderink.net or open a discussion on GitHub.

---

**Last Updated:** 2025-12-21
**Version:** 1.0.0
