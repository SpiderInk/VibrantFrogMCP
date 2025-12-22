# 🐸 VibrantFrog v1.0.0

**First public release of VibrantFrog** - A native macOS AI chat application with Model Context Protocol (MCP) integration.

## ✨ Features

- **AI Chat Interface** - Native macOS chat powered by Ollama
- **MCP Integration** - Full support for Model Context Protocol tool calling
- **Photo Intelligence** - Search your Apple Photos library using natural language
- **Prompt Templates** - Customizable templates with variable substitution
- **Conversation History** - Auto-saved conversations with intelligent naming
- **Developer Tools** - Direct tool calling interface for testing MCP servers

## 📦 Installation

### Option 1: DMG (Recommended)
1. Download `VibrantFrog-v1.0.0.dmg`
2. Open the DMG file
3. Drag VibrantFrog.app to your Applications folder
4. Right-click → Open (first time only to bypass Gatekeeper)

### Option 2: ZIP
1. Download `VibrantFrog-v1.0.0.zip`
2. Unzip the file
3. Move VibrantFrog.app to your Applications folder
4. Right-click → Open (first time only)

## ⚙️ Requirements

- macOS 14.0 (Sonoma) or later
- [Ollama](https://ollama.ai) installed and running
- At least one Ollama model pulled (e.g., `ollama pull mistral-nemo:latest`)
- Python 3.10+ (for photo search MCP server)

## 🚀 Quick Start

### Basic Chat (No Setup Required)
1. Install Ollama: `brew install ollama`
2. Start Ollama: `ollama serve`
3. Pull a model: `ollama pull mistral-nemo:latest`
4. Launch VibrantFrog
5. Start chatting!

### Photo Search (Requires Python Setup)
To enable AI-powered photo search:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/SpiderInk/VibrantFrogMCP.git
   cd VibrantFrogMCP
   ```

2. **Install Python dependencies:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

3. **Install embedding model:**
   ```bash
   ollama pull nomic-embed-text
   ```

4. **Start the MCP server:**
   ```bash
   python3 vibrant_frog_mcp.py --transport http
   ```

5. **Launch VibrantFrog** and verify the "VibrantFrog Photos" server shows as "Connected" (green)

📖 **[Full Setup Guide](https://github.com/SpiderInk/VibrantFrogMCP/blob/main/MCP_SERVER_SETUP.md)** - Includes Claude Desktop integration

## 📝 What's New

- Initial public release
- Complete MCP protocol support (HTTP transport)
- Photo library indexing with AI descriptions
- Built-in MCP servers: VibrantFrog Photos, AWS Knowledge
- Custom prompt templates with variables
- Conversation management with auto-naming

## 🔗 Links

- **Documentation:** [README.md](https://github.com/SpiderInk/VibrantFrogMCP#readme)
- **Report Issues:** [GitHub Issues](https://github.com/SpiderInk/VibrantFrogMCP/issues)
- **Discussions:** [GitHub Discussions](https://github.com/SpiderInk/VibrantFrogMCP/discussions)

## ⚠️ Note

This app is **code-signed** but **not notarized**. On first launch:
1. Right-click the app
2. Select "Open"
3. Click "Open" in the security dialog

---

**Made with ❤️ by SpiderInk**

*Bringing AI to your fingertips, one frog at a time* 🐸
