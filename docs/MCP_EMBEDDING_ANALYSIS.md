# MCP Server Embedding Analysis: Stdio vs HTTP

## Goal
Make VibrantFrog's photo search MCP server easy to deploy with job management for indexing.

## Option 1: Embed Stdio MCP Server in Swift App

### How It Works

```
┌─────────────────────────────────────────────────────┐
│         VibrantFrog.app (Swift)                     │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │         MCPClient (stdio)                    │  │
│  │                                              │  │
│  │  Process: python3 vibrant_frog_mcp.py       │  │
│  │  stdin/stdout pipes                          │  │
│  └──────────────┬───────────────────────────────┘  │
│                 │                                   │
│                 ↓ JSON-RPC over pipes               │
│  ┌──────────────────────────────────────────────┐  │
│  │  Python Process (embedded)                   │  │
│  │                                              │  │
│  │  vibrant_frog_mcp.py                        │  │
│  │  ├─ Ollama client                           │  │
│  │  ├─ ChromaDB                                │  │
│  │  └─ Photo indexing jobs                     │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Difficulty Assessment: **MEDIUM** ⚠️

#### What's Already Done ✅
You already have `MCPClient.swift` with stdio support:
```swift
// Services/MCPClient.swift already exists
// It can launch subprocess with stdin/stdout pipes
```

#### What Needs to Be Done

**1. Bundle Python Environment (HARD)**
```
Challenges:
- Need to bundle Python interpreter with app
- Need to install pip packages at runtime OR bundle them
- macOS code signing issues with bundled Python
- App size increases (~50-100 MB)
```

**Solutions:**
- **Option A:** Use system Python (`/usr/bin/python3`)
  - ⚠️ May not exist on all Macs
  - ⚠️ User may not have required packages

- **Option B:** Bundle Python.framework
  - ✅ Guaranteed to work
  - ❌ Complex build process
  - ❌ Code signing issues

- **Option C:** Download Python on first run
  - ✅ Smaller initial app size
  - ❌ Requires internet on first launch
  - ❌ Still need to install packages

**2. Install Python Dependencies (HARD)**
```
Challenges:
- pip install at runtime?
- Bundle site-packages in app?
- Version compatibility
```

**Solutions:**
- **Option A:** Bundle all dependencies
  ```
  VibrantFrog.app/
  └── Contents/
      └── Resources/
          └── python/
              ├── python3
              ├── lib/
              │   └── python3.11/
              │       └── site-packages/
              │           ├── chromadb/
              │           ├── ollama/
              │           └── ...
              └── bin/
                  └── vibrant_frog_mcp.py
  ```
  - App size: +200-300 MB (ChromaDB is big)
  - Code signing complexity

- **Option B:** First-run setup wizard
  ```swift
  if !pythonDependenciesInstalled {
      showSetupWizard()
      // Runs: pip install -r requirements.txt
  }
  ```
  - Better UX
  - Still requires system Python

**3. Process Lifecycle Management (MEDIUM)**
```swift
class EmbeddedMCPManager {
    private var mcpProcess: Process?
    private var mcpClient: MCPClient?

    func start() async throws {
        // 1. Find Python
        let pythonPath = findPython()

        // 2. Find script
        let scriptPath = Bundle.main.path(
            forResource: "vibrant_frog_mcp",
            ofType: "py"
        )

        // 3. Launch process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath!, "--transport", "stdio"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe

        try process.run()

        // 4. Create MCP client connected to pipes
        mcpClient = MCPClient(
            inputPipe: inputPipe,
            outputPipe: outputPipe
        )
    }

    func stop() {
        mcpProcess?.terminate()
    }
}
```

**Challenges:**
- What if process crashes?
- How to restart?
- How to detect startup success?
- How to handle ChromaDB initialization (slow)?

**4. Resource Path Management (EASY)**
```swift
// Where does ChromaDB store data?
let mcpDataPath = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
).first!.appendingPathComponent("VibrantFrog/mcp")

// Pass to Python via environment variable
process.environment = [
    "VIBRANTFROG_DATA_PATH": mcpDataPath.path
]
```

### Pros of Stdio Embedding ✅
- ✅ **Single app** - No separate server to manage
- ✅ **Auto-start** - Launches with app
- ✅ **Controlled lifecycle** - Can restart if crashes
- ✅ **Sandboxed** - Process runs as child
- ✅ **Security** - No network exposure

### Cons of Stdio Embedding ❌
- ❌ **Complex packaging** - Python + dependencies bundling
- ❌ **Large app size** - +200-300 MB
- ❌ **Code signing** - Notarization issues with bundled Python
- ❌ **Startup delay** - ChromaDB initialization (2-5 seconds)
- ❌ **Debugging harder** - Can't easily inspect logs
- ❌ **Update complexity** - Need to update app to update Python code

---

## Option 2: HTTP MCP Server (Separate Process)

### How It Works

```
┌─────────────────────────────────────────────────────┐
│         VibrantFrog.app (Swift)                     │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │      MCPClientHTTP                           │  │
│  │      http://localhost:8765/mcp               │  │
│  └──────────────┬───────────────────────────────┘  │
└─────────────────┼───────────────────────────────────┘
                  │ HTTP POST
                  ↓
┌─────────────────────────────────────────────────────┐
│    Separate Process (Background Service)           │
│                                                     │
│    python3 -m vibrant_frog_mcp --http --port 8765  │
│                                                     │
│    OR via LaunchAgent (auto-start on login)        │
└─────────────────────────────────────────────────────┘
```

### Difficulty Assessment: **EASY** ✅

#### What Needs to Be Done

**1. HTTP Server Wrapper (ALREADY EXISTS?)**

Check if you have an HTTP wrapper:
```bash
ls -la /Users/tpiazza/git/VibrantFrogMCP/*http*.py
```

If not, create simple one:
```python
# http_mcp_server.py
import asyncio
from aiohttp import web
import json
import vibrant_frog_mcp

async def handle_mcp(request):
    """Handle MCP JSON-RPC requests over HTTP"""
    try:
        body = await request.json()
        # Dispatch to MCP handlers
        result = await vibrant_frog_mcp.handle_request(body)
        return web.json_response(result)
    except Exception as e:
        return web.json_response(
            {"error": str(e)},
            status=500
        )

async def init_app():
    app = web.Application()
    app.router.add_post('/mcp', handle_mcp)
    return app

if __name__ == '__main__':
    web.run_app(init_app(), port=8765)
```

**2. Installation Script (EASY)**
```bash
#!/bin/bash
# install_mcp_server.sh

# Install Python dependencies
pip3 install -r requirements.txt

# Create LaunchAgent
cat > ~/Library/LaunchAgents/com.vibrantfrog.mcp.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vibrantfrog.mcp</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/python3</string>
        <string>$(pwd)/http_mcp_server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

# Load service
launchctl load ~/Library/LaunchAgents/com.vibrantfrog.mcp.plist

echo "MCP server installed and running on http://localhost:8765"
```

**3. Swift Auto-Detection (EASY)**
```swift
// In VibrantFrogApp startup
func checkMCPServerHealth() async -> Bool {
    let url = URL(string: "http://localhost:8765/mcp")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let testRequest = [
        "jsonrpc": "2.0",
        "method": "initialize",
        "params": [:],
        "id": 1
    ]

    request.httpBody = try? JSONEncoder().encode(testRequest)

    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            return httpResponse.statusCode == 200
        }
    } catch {
        return false
    }
    return false
}

// Show setup instructions if server not running
if !await checkMCPServerHealth() {
    showMCPServerSetupInstructions()
}
```

### Pros of HTTP Approach ✅
- ✅ **Simple deployment** - User runs install script once
- ✅ **Easy debugging** - Can curl endpoints, check logs
- ✅ **Independent updates** - Update Python without updating app
- ✅ **Small app size** - No Python bundling
- ✅ **Fast startup** - Server already running
- ✅ **Better for development** - Can restart server without restarting app
- ✅ **Works with other clients** - Claude Desktop, etc.

### Cons of HTTP Approach ❌
- ❌ **Requires setup** - User must run install script
- ❌ **Separate process** - Not "just works"
- ❌ **Port conflicts** - 8765 might be in use
- ❌ **Security** - localhost only, but still network exposed
- ❌ **User must troubleshoot** - If server crashes, need to restart

---

## Recommendation: HTTP with Excellent UX 🎯

### The Best of Both Worlds

Make HTTP server **feel** like it's embedded:

#### Phase 1: Detect & Guide
```swift
// On first launch
if !isMCPServerInstalled() {
    showOnboardingWizard()
}

func isMCPServerInstalled() -> Bool {
    // Check if LaunchAgent exists
    let plistPath = NSHomeDirectory() +
        "/Library/LaunchAgents/com.vibrantfrog.mcp.plist"
    return FileManager.default.fileExists(atPath: plistPath)
}

func showOnboardingWizard() {
    // Beautiful SwiftUI wizard:
    // 1. "Welcome to VibrantFrog Photo Search"
    // 2. "We need to install a background service"
    // 3. [Install] button -> runs script
    // 4. Progress indicator
    // 5. "All set! Let's search your photos"
}
```

#### Phase 2: One-Click Install
```swift
@MainActor
func installMCPServer() async throws {
    // 1. Find bundled install script
    guard let scriptPath = Bundle.main.path(
        forResource: "install_mcp_server",
        ofType: "sh"
    ) else {
        throw InstallError.scriptNotFound
    }

    // 2. Run in Terminal (visible to user)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [scriptPath]

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
        // Success!
        await checkMCPServerHealth()
    } else {
        throw InstallError.installFailed
    }
}
```

#### Phase 3: Auto-Restart
```swift
func ensureMCPServerRunning() async {
    if !await checkMCPServerHealth() {
        // Attempt to restart
        _ = try? await restartMCPServer()

        // Wait a bit
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Check again
        if !await checkMCPServerHealth() {
            showServerErrorAlert()
        }
    }
}

func restartMCPServer() async throws {
    let script = """
    launchctl unload ~/Library/LaunchAgents/com.vibrantfrog.mcp.plist
    launchctl load ~/Library/LaunchAgents/com.vibrantfrog.mcp.plist
    """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", script]
    try process.run()
}
```

---

## Job Management API Design

### New MCP Tools for Indexing

```python
# In vibrant_frog_mcp.py

# Global job tracking
indexing_jobs = {}

class IndexingJob:
    def __init__(self, job_id: str):
        self.job_id = job_id
        self.status = "pending"  # pending, running, completed, failed
        self.total_photos = 0
        self.processed_photos = 0
        self.current_photo = None
        self.started_at = None
        self.completed_at = None
        self.error = None

@app.call_tool()
async def call_tool(name: str, arguments: dict):
    # ... existing tools ...

    if name == "start_indexing_job":
        """
        Start background indexing job

        Args:
            directory_path: Path to index (optional, defaults to Photos Library)
            batch_size: Photos to process (optional, default: all)

        Returns:
            {"job_id": "uuid-string", "status": "started"}
        """
        job_id = str(uuid.uuid4())
        directory = arguments.get("directory_path")
        batch_size = arguments.get("batch_size")

        # Create job
        job = IndexingJob(job_id)
        indexing_jobs[job_id] = job

        # Start async task
        asyncio.create_task(
            run_indexing_job(job_id, directory, batch_size)
        )

        return {
            "job_id": job_id,
            "status": "started",
            "message": "Indexing job started in background"
        }

    elif name == "get_job_status":
        """
        Get status of indexing job

        Args:
            job_id: Job ID from start_indexing_job

        Returns:
            {
                "job_id": "uuid",
                "status": "running",
                "total_photos": 1000,
                "processed_photos": 243,
                "current_photo": "IMG_1234.jpg",
                "progress_percent": 24.3
            }
        """
        job_id = arguments["job_id"]

        if job_id not in indexing_jobs:
            raise ValueError(f"Job {job_id} not found")

        job = indexing_jobs[job_id]

        return {
            "job_id": job.job_id,
            "status": job.status,
            "total_photos": job.total_photos,
            "processed_photos": job.processed_photos,
            "current_photo": job.current_photo,
            "progress_percent": (
                (job.processed_photos / job.total_photos * 100)
                if job.total_photos > 0 else 0
            ),
            "started_at": job.started_at.isoformat() if job.started_at else None,
            "error": job.error
        }

    elif name == "cancel_job":
        """
        Cancel running indexing job

        Args:
            job_id: Job ID to cancel

        Returns:
            {"job_id": "uuid", "status": "cancelled"}
        """
        job_id = arguments["job_id"]

        if job_id not in indexing_jobs:
            raise ValueError(f"Job {job_id} not found")

        job = indexing_jobs[job_id]
        job.status = "cancelled"

        return {
            "job_id": job_id,
            "status": "cancelled"
        }

    elif name == "list_jobs":
        """
        List all indexing jobs

        Returns:
            {
                "jobs": [
                    {"job_id": "...", "status": "...", ...},
                    ...
                ]
            }
        """
        return {
            "jobs": [
                {
                    "job_id": job.job_id,
                    "status": job.status,
                    "progress_percent": (
                        (job.processed_photos / job.total_photos * 100)
                        if job.total_photos > 0 else 0
                    )
                }
                for job in indexing_jobs.values()
            ]
        }

async def run_indexing_job(
    job_id: str,
    directory: Optional[str],
    batch_size: Optional[int]
):
    """Background task to run indexing"""
    job = indexing_jobs[job_id]
    job.status = "running"
    job.started_at = datetime.now()

    try:
        # Get photos to index
        photos = get_photos_to_index(directory)
        job.total_photos = min(len(photos), batch_size) if batch_size else len(photos)

        # Index each photo
        for i, photo_path in enumerate(photos[:batch_size] if batch_size else photos):
            if job.status == "cancelled":
                break

            job.current_photo = os.path.basename(photo_path)
            job.processed_photos = i

            # Index photo
            await index_photo(photo_path)

        job.status = "completed"
        job.completed_at = datetime.now()

    except Exception as e:
        job.status = "failed"
        job.error = str(e)
        logger.error(f"Job {job_id} failed: {e}")
```

### Swift Integration

```swift
// In IndexingView.swift

@State private var currentJobId: String?
@State private var jobStatus: JobStatus?
@State private var pollTimer: Timer?

func startIndexing() {
    Task {
        do {
            // Start job
            let result = try await mcpClient.callTool(
                name: "start_indexing_job",
                arguments: [
                    "batch_size": 100  // Or nil for all
                ]
            )

            // Extract job ID
            if let jobId = result.content.first?.text?.jobId {
                currentJobId = jobId

                // Start polling
                startPolling()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

func startPolling() {
    pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        Task {
            await updateJobStatus()
        }
    }
}

func updateJobStatus() async {
    guard let jobId = currentJobId else { return }

    do {
        let result = try await mcpClient.callTool(
            name: "get_job_status",
            arguments: ["job_id": jobId]
        )

        // Parse status
        if let statusData = result.content.first?.text {
            let status = try JSONDecoder().decode(JobStatus.self, from: statusData)

            await MainActor.run {
                self.jobStatus = status
                self.indexingProgress = status.progressPercent / 100.0
                self.indexedCount = status.processedPhotos
                self.totalToIndex = status.totalPhotos

                // Stop polling if completed
                if status.status == "completed" || status.status == "failed" {
                    pollTimer?.invalidate()
                }
            }
        }
    } catch {
        print("Failed to get job status: \(error)")
    }
}

struct JobStatus: Codable {
    let jobId: String
    let status: String
    let totalPhotos: Int
    let processedPhotos: Int
    let currentPhoto: String?
    let progressPercent: Double
    let error: String?
}
```

---

## Final Recommendation

### Go with HTTP + Job Management API

**Implementation Timeline:**

**Week 1: HTTP Server Setup**
- [ ] Create `http_mcp_server.py` wrapper
- [ ] Test with existing `vibrant_frog_mcp.py`
- [ ] Create `install_mcp_server.sh` script
- [ ] Create `uninstall_mcp_server.sh` script
- [ ] Test LaunchAgent auto-start

**Week 2: Job Management API**
- [ ] Add `start_indexing_job` tool
- [ ] Add `get_job_status` tool
- [ ] Add `cancel_job` tool
- [ ] Add `list_jobs` tool
- [ ] Test background job execution

**Week 3: Swift Integration**
- [ ] Add onboarding wizard for MCP server install
- [ ] Wire IndexingView to job API
- [ ] Add polling for job status
- [ ] Add progress UI updates
- [ ] Add server health checks

**Week 4: Polish & Documentation**
- [ ] Error handling
- [ ] Recovery from failures
- [ ] User documentation
- [ ] Troubleshooting guide
- [ ] Testing on clean Mac

### Why This Approach Wins

1. **Easy to implement** - Build on what exists
2. **Easy to debug** - Separate process, clear logs
3. **Easy to update** - Python code independent of app
4. **Professional UX** - Onboarding wizard makes setup smooth
5. **Scalable** - Job API works for other operations too
6. **Open** - Other apps can use same server

### Bonus: Can Add Stdio Later

If you want to add stdio embedding in v2.0:
- Keep HTTP as "advanced mode"
- Add stdio as "simple mode"
- Use same job management API
- User can choose preference

For now, HTTP is the pragmatic choice that gets you to production faster.
