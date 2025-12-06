# VibrantFrog Website Plan

This document outlines the plan for creating a landing page for VibrantFrog at either **spiderink.net** or **forgoteam.ai**.

## Website Structure

### Homepage (Landing Page)

```
┌─────────────────────────────────────────────────────┐
│                    Hero Section                     │
│  🐸 VibrantFrog                                     │
│  AI Chat with MCP Tool Calling for macOS           │
│  [Download for macOS] [View on GitHub]             │
│  Screenshot/Demo Video                             │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                  Features Section                   │
│  🤖 AI Chat | 🔧 MCP Integration | 📝 Prompts      │
│  💬 History | 🛠️ Developer Tools                   │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                 Quick Start Guide                   │
│  1. Install Ollama                                  │
│  2. Download VibrantFrog                            │
│  3. Start Chatting                                  │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              MCP Integration Showcase               │
│  Connect to MCP servers for enhanced AI             │
│  AWS, Custom Servers, Tool Calling                  │
│  Live demo or video                                 │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                 Open Source CTA                     │
│  Built by the community, for the community          │
│  [Star on GitHub] [Contribute]                      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                      Footer                         │
│  Links | Docs | GitHub | License                    │
└─────────────────────────────────────────────────────┘
```

## Page Sections (Detailed)

### 1. Hero Section
**Copy:**
```
VibrantFrog 🐸
AI Chat with Model Context Protocol

Bring AI-powered conversations to your Mac with full support
for MCP tool calling, allowing AI models to interact with
external services and execute custom tools.

[Download for macOS 14+]  [View on GitHub]

Available for: macOS Sonoma and later
```

**Visual:**
- App screenshot showing AI Chat interface
- OR short demo video (15-30 seconds) showing:
  - User asking "What AWS services are available?"
  - Tool call being made
  - Results displayed

### 2. Features Grid

**🤖 AI Chat**
- Native macOS interface
- Powered by Ollama
- Multiple model support
- Conversation history

**🔧 MCP Integration**
- HTTP & stdio transports
- Dynamic tool discovery
- AWS MCP server built-in
- Custom server support

**📝 Smart Prompts**
- Template system
- Variable substitution
- Pre-built templates
- Custom prompts

**💬 Conversations**
- Persistent history
- Multi-tab support
- Photo attachments
- Search & filter

**🛠️ Developer Tools**
- Direct tool calling
- Server management
- Comprehensive logging
- MCP protocol testing

**🎨 Native macOS**
- SwiftUI interface
- System integration
- Privacy-first
- Local processing

### 3. Quick Start

**3-Step Setup:**

```
1️⃣ Install Ollama
   brew install ollama
   ollama pull mistral-nemo:latest

2️⃣ Download VibrantFrog
   Clone from GitHub or download release
   Open in Xcode and build

3️⃣ Start Chatting
   Select a model, connect to MCP servers,
   and start asking questions!
```

### 4. MCP Showcase

**"Connect Your AI to Anything"**

Show examples of MCP integration:
- AWS documentation search
- Custom tool execution
- Real-time API calls
- Photo library search (local)

Code snippet:
```json
{
  "mcpServers": {
    "aws-knowledge": {
      "url": "https://knowledge-mcp.global.api.aws",
      "path": "/mcp"
    }
  }
}
```

### 5. Technology Stack

**Built With:**
- Swift 5.9+ & SwiftUI
- Ollama for local LLM inference
- Model Context Protocol
- URLSession for networking
- Photos Framework integration

### 6. Community & Contributing

**Open Source**
- MIT Licensed
- Contributions welcome
- Active development
- Community-driven

[Contribute on GitHub] [Read the Docs] [Join Discussions]

### 7. Footer

**Links:**
- GitHub Repository
- Documentation
- Architecture Guide
- Contributing Guidelines
- License

**SpiderInk:**
- Website: spiderink.net
- Email: contact@spiderink.net
- Other Projects: forgoteam.ai

**Social:**
- GitHub: @SpiderInk
- Twitter/X: @SpiderInk (if applicable)

## Visual Design Recommendations

### Color Scheme

**Primary:**
- Frog Green: `#4CAF50` (vibrant, friendly)
- Dark Background: `#1a1a1a` (professional)

**Accent:**
- Blue: `#2196F3` (trust, technology)
- Purple: `#9C27B0` (AI, innovation)

**Text:**
- Light: `#FFFFFF`
- Gray: `#CCCCCC`
- Muted: `#666666`

### Typography

**Headers:**
- Font: SF Pro Display / Inter
- Weight: Bold (700)
- Size: 48px (h1), 36px (h2), 24px (h3)

**Body:**
- Font: SF Pro Text / Inter
- Weight: Regular (400)
- Size: 16px
- Line height: 1.6

### Components

**Buttons:**
```css
.primary-button {
  background: linear-gradient(135deg, #4CAF50, #45a049);
  color: white;
  padding: 16px 32px;
  border-radius: 8px;
  font-weight: 600;
  box-shadow: 0 4px 12px rgba(76, 175, 80, 0.3);
}

.secondary-button {
  border: 2px solid #4CAF50;
  color: #4CAF50;
  padding: 14px 30px;
  border-radius: 8px;
  background: transparent;
}
```

**Feature Cards:**
```css
.feature-card {
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 12px;
  padding: 32px;
  backdrop-filter: blur(10px);
}
```

## Technical Implementation

### Option 1: Static Site (Recommended)

**Stack:**
- **Astro** or **Next.js** (static export)
- **Tailwind CSS** for styling
- **MDX** for content (easy to update)
- Deploy to **Vercel**, **Netlify**, or **GitHub Pages**

**Pros:**
- Fast performance
- SEO-friendly
- Easy to maintain
- Free hosting

**File Structure:**
```
website/
├── src/
│   ├── pages/
│   │   └── index.astro       # Homepage
│   ├── components/
│   │   ├── Hero.astro
│   │   ├── Features.astro
│   │   └── Footer.astro
│   ├── layouts/
│   │   └── Layout.astro
│   └── styles/
│       └── global.css
├── public/
│   ├── images/
│   │   ├── hero-screenshot.png
│   │   ├── logo.svg
│   │   └── demo-video.mp4
│   └── downloads/
│       └── VibrantFrog-v1.0.dmg
├── astro.config.mjs
└── package.json
```

### Option 2: WordPress/Webflow

**Pros:**
- No coding required
- Easy for non-technical updates
- Built-in CMS

**Cons:**
- Less control
- Slower performance
- Hosting costs

### Option 3: GitHub Pages (Minimal)

Just use the README.md as the landing page with GitHub's automatic site generation.

**Pros:**
- Zero setup
- Always in sync with repo

**Cons:**
- Limited customization
- Basic styling

## Domain Recommendations

### spiderink.net
**Subdomain:** `vibrantfrog.spiderink.net`
**Path:** `spiderink.net/vibrantfrog`

**Pros:**
- Establishes SpiderInk as an organization
- Can host multiple projects
- Professional

### forgoteam.ai
**Subdomain:** `vibrantfrog.forgoteam.ai`
**Path:** `forgoteam.ai/vibrantfrog`

**Pros:**
- AI-focused branding
- Modern .ai TLD
- Tech-forward image

**Recommendation:** Use **spiderink.net** as the main organizational site and create a redirect from **forgoteam.ai** if you own it.

## Content Assets Needed

### Screenshots (Priority: High)

1. **Hero Screenshot** (1920x1080)
   - Main chat interface
   - Show a complete conversation with tool calling
   - Clean, professional

2. **Feature Showcases** (1200x800 each)
   - MCP server configuration
   - Prompt template editor
   - Conversation history
   - Tool calling in action

3. **UI Details** (800x600 each)
   - Model selection dropdown
   - Chat message bubbles
   - Tool result display

### Demo Video (Priority: Medium)

**30-second demo:**
1. Open VibrantFrog (0-3s)
2. Select mistral-nemo model (3-6s)
3. Type question: "What AWS services are available?" (6-10s)
4. Show tool call being made (10-15s)
5. Display results (15-25s)
6. Quick pan through other features (25-30s)

**Tools:** QuickTime screen recording, Final Cut Pro/iMovie for editing

### Graphics (Priority: Low)

1. **Logo** - Frog emoji + text or custom SVG
2. **Feature Icons** - System SF Symbols or custom icons
3. **Social Cards** - For Twitter/LinkedIn sharing (1200x630)

## SEO Strategy

### Meta Tags

```html
<title>VibrantFrog - AI Chat with MCP for macOS</title>
<meta name="description" content="Native macOS AI chat application with Model Context Protocol support. Connect to MCP servers, use tools, and chat with local LLMs via Ollama.">
<meta name="keywords" content="AI chat, MCP, Model Context Protocol, Ollama, macOS, Swift, tool calling, AI assistant">

<!-- Open Graph -->
<meta property="og:title" content="VibrantFrog - AI Chat with MCP">
<meta property="og:description" content="Native macOS AI chat with MCP tool calling">
<meta property="og:image" content="/images/social-card.png">
<meta property="og:url" content="https://spiderink.net/vibrantfrog">

<!-- Twitter -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="VibrantFrog">
<meta name="twitter:description" content="AI Chat with MCP for macOS">
<meta name="twitter:image" content="/images/social-card.png">
```

### Target Keywords

1. "macOS AI chat"
2. "MCP client macOS"
3. "Ollama GUI"
4. "Model Context Protocol"
5. "AI tool calling"
6. "Swift AI application"
7. "Local AI chat"

## Analytics & Metrics

**Track:**
- Page views
- Download clicks
- GitHub star clicks
- Time on page
- Bounce rate

**Tools:**
- Google Analytics 4
- Plausible (privacy-friendly alternative)
- GitHub traffic stats

## Launch Checklist

### Pre-Launch
- [ ] Create all screenshots
- [ ] Record demo video (optional)
- [ ] Write all copy
- [ ] Design and build website
- [ ] Test on mobile and desktop
- [ ] Set up analytics
- [ ] Configure domain/hosting

### Launch Day
- [ ] Deploy website
- [ ] Publish GitHub repository
- [ ] Post on relevant communities:
  - Hacker News
  - Reddit (/r/MacApps, /r/LocalLLaMA)
  - Twitter/X
  - Product Hunt
- [ ] Share in MCP community
- [ ] Update personal/company profiles

### Post-Launch
- [ ] Monitor analytics
- [ ] Respond to feedback
- [ ] Update docs based on questions
- [ ] Consider blog posts:
  - "Building VibrantFrog"
  - "MCP Integration Guide"
  - "Why Local AI Matters"

## Timeline Estimate

**Week 1:**
- Gather screenshots and assets
- Write all website copy
- Design mockups

**Week 2:**
- Build website
- Test and refine
- Set up hosting

**Week 3:**
- Final QA
- Prepare launch materials
- Launch!

## Budget Estimate

**Hosting:**
- Free: GitHub Pages, Netlify, Vercel
- Paid: $5-15/mo for custom hosting

**Domain:**
- Already owned: $0
- New .ai domain: ~$80/year

**Design:**
- DIY: $0
- Hire designer: $500-2000

**Total (DIY):** $0-15/month

---

**Next Steps:**
1. Choose domain (spiderink.net vs forgoteam.ai)
2. Gather screenshots from VibrantFrog
3. Build landing page using Astro or Next.js
4. Deploy and launch!
