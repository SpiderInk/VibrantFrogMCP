# Apple Photos Library Indexing Job Management API

## Overview

The VibrantFrog MCP server includes job management tools for **Apple Photos Library** indexing. This allows you to start indexing jobs that run in the background and poll for progress.

The indexing system:
- ✅ Reads directly from **Apple Photos Library** (not directories)
- ✅ Skips already-indexed photos automatically
- ✅ Indexes newest photos first by default
- ✅ Handles iCloud photos (exports if needed)
- ✅ Stores rich metadata (albums, keywords, location, etc.)
- ✅ Uses UUID-based indexing for reliable photo retrieval

## New MCP Tools

### 1. `start_indexing_job`

Start a background Apple Photos Library indexing job.

**Parameters:**
- `batch_size` (integer, optional): Limit number of photos to index. If not specified, indexes all unindexed photos. **Recommended: 100-500 for manageable sessions.**
- `reverse_chronological` (boolean, optional): Start with newest photos first (default: true). Set to false to index oldest first.
- `include_cloud` (boolean, optional): Include iCloud photos (default: true). Set to false to only index local photos.

**Returns:**
```json
{
  "job_id": "uuid-string",
  "batch_size": 100,
  "reverse_chronological": true,
  "include_cloud": true,
  "message": "Apple Photos indexing job started! Use get_job_status..."
}
```

**Example:**
```python
# Index 500 newest photos (recommended starting point)
await mcp_client.call_tool(
    name="start_indexing_job",
    arguments={
        "batch_size": 500
    }
)

# Index all unindexed photos (can take days for large libraries!)
await mcp_client.call_tool(
    name="start_indexing_job",
    arguments={}
)

# Index 100 oldest local photos only
await mcp_client.call_tool(
    name="start_indexing_job",
    arguments={
        "batch_size": 100,
        "reverse_chronological": False,
        "include_cloud": False
    }
)
```

---

### 2. `get_job_status`

Get current status and progress of an indexing job.

**Parameters:**
- `job_id` (string, required): Job ID from start_indexing_job

**Returns:**
```json
{
  "job_id": "uuid",
  "status": "running",
  "total_photos": 1000,
  "processed_photos": 243,
  "current_photo": "IMG_1234.jpg",
  "progress_percent": 24.3,
  "started_at": "2025-12-06T10:30:00",
  "completed_at": null,
  "error": null
}
```

**Status values:**
- `pending` - Job created but not started yet
- `running` - Currently processing photos
- `completed` - Successfully finished
- `failed` - Error occurred
- `cancelled` - User cancelled the job

**Example:**
```python
status = await mcp_client.call_tool(
    name="get_job_status",
    arguments={"job_id": "abc-123-def"}
)
```

---

### 3. `cancel_job`

Cancel a running indexing job.

**Parameters:**
- `job_id` (string, required): Job ID to cancel

**Returns:**
```json
{
  "job_id": "uuid",
  "message": "Cancellation requested. Job will stop after current photo."
}
```

**Example:**
```python
await mcp_client.call_tool(
    name="cancel_job",
    arguments={"job_id": "abc-123-def"}
)
```

---

### 4. `list_jobs`

List all indexing jobs (running, completed, failed).

**Parameters:** None

**Returns:**
```json
{
  "total": 3,
  "jobs": [
    {
      "job_id": "abc-123",
      "status": "running",
      "progress_percent": 45.2,
      "directory": "/path/to/photos"
    },
    {
      "job_id": "def-456",
      "status": "completed",
      "progress_percent": 100,
      "directory": "/other/path"
    }
  ]
}
```

**Example:**
```python
jobs = await mcp_client.call_tool(name="list_jobs")
```

---

## Swift Integration Pattern

### Basic Polling Implementation

```swift
class PhotoIndexingManager: ObservableObject {
    @Published var isIndexing = false
    @Published var progress: Double = 0.0
    @Published var currentPhoto: String?
    @Published var processedCount: Int = 0
    @Published var totalCount: Int = 0

    private var currentJobId: String?
    private var pollTimer: Timer?
    private let mcpClient: MCPClientHTTP

    func startIndexing(batchSize: Int? = nil, newestFirst: Bool = true, includeCloud: Bool = true) async {
        do {
            // Start the Apple Photos Library indexing job
            var args: [String: Any] = [:]
            if let batch = batchSize {
                args["batch_size"] = batch
            }
            args["reverse_chronological"] = newestFirst
            args["include_cloud"] = includeCloud

            let result = try await mcpClient.callTool(
                name: "start_indexing_job",
                arguments: args
            )

            // Extract job_id from result
            // Parse JSON from result.content
            if let jobId = extractJobId(from: result) {
                currentJobId = jobId
                isIndexing = true

                // Start polling
                startPolling()
            }
        } catch {
            print("Failed to start indexing: \(error)")
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task {
                await self?.updateStatus()
            }
        }
    }

    private func updateStatus() async {
        guard let jobId = currentJobId else { return }

        do {
            let result = try await mcpClient.callTool(
                name: "get_job_status",
                arguments: ["job_id": jobId]
            )

            // Parse status from result
            let status = parseJobStatus(from: result)

            await MainActor.run {
                self.progress = status.progressPercent / 100.0
                self.currentPhoto = status.currentPhoto
                self.processedCount = status.processedPhotos
                self.totalCount = status.totalPhotos

                // Stop polling if job is done
                if status.status == "completed" ||
                   status.status == "failed" ||
                   status.status == "cancelled" {
                    self.isIndexing = false
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                }
            }
        } catch {
            print("Failed to get status: \(error)")
        }
    }

    func cancelIndexing() async {
        guard let jobId = currentJobId else { return }

        do {
            _ = try await mcpClient.callTool(
                name: "cancel_job",
                arguments: ["job_id": jobId]
            )
        } catch {
            print("Failed to cancel: \(error)")
        }
    }
}
```

### UI Integration

```swift
struct IndexingView: View {
    @StateObject private var indexingManager = PhotoIndexingManager()

    var body: some View {
        VStack {
            if indexingManager.isIndexing {
                ProgressView(value: indexingManager.progress) {
                    HStack {
                        Text("Indexing photos...")
                        Spacer()
                        Text("\(indexingManager.processedCount) / \(indexingManager.totalCount)")
                    }
                }

                if let currentPhoto = indexingManager.currentPhoto {
                    Text("Current: \(currentPhoto)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Cancel") {
                    Task {
                        await indexingManager.cancelIndexing()
                    }
                }
            } else {
                Button("Index 500 Newest Photos") {
                    Task {
                        await indexingManager.startIndexing(
                            batchSize: 500,
                            newestFirst: true,
                            includeCloud: true
                        )
                    }
                }
            }
        }
    }
}
```

---

## Performance Characteristics

### Indexing Speed
- **Per photo:** ~2-3 seconds (LLaVA description generation)
- **Batch of 100:** ~3-5 minutes
- **1000 photos:** ~40-50 minutes

### Polling Frequency
- **Recommended:** 1-2 seconds
- **Minimum:** 500ms (avoid overwhelming server)
- **Maximum:** 5 seconds (for better UX)

### Resource Usage
- **Memory:** ~2-4 GB (ChromaDB + Ollama)
- **CPU:** High during indexing
- **Disk:** ~2 KB per photo (embedding + metadata)

---

## Error Handling

### Common Errors

**Job Not Found:**
```json
{
  "error": "Job abc-123 not found"
}
```
**Reason:** Job ID doesn't exist or was cleared from memory

**Directory Not Found:**
```json
{
  "error": "Directory /path/to/photos does not exist"
}
```

**Permission Denied:**
```json
{
  "error": "Permission denied accessing /path"
}
```

### Recovery Strategies

**If job fails mid-way:**
- Job state is preserved with error message
- Already indexed photos remain in database
- Can restart with new job for remaining photos

**If server restarts:**
- All job state is lost (in-memory only)
- Already indexed photos persist in ChromaDB
- Need to start new job after restart

---

## Advanced Usage

### Resumable Indexing

```python
# Check which photos are already indexed
existing_uuids = get_indexed_photo_uuids()

# Filter out already indexed photos
photos_to_index = [
    p for p in all_photos
    if p.uuid not in existing_uuids
]

# Index only new photos
start_indexing_job(
    directory_path=photos_dir,
    batch_size=len(photos_to_index)
)
```

### Progress Notifications

```swift
func updateStatus() async {
    // ... fetch status ...

    // Show notification every 25%
    let milestone = Int(status.progressPercent / 25)
    if milestone > lastMilestone {
        showNotification("Indexing \(milestone * 25)% complete")
        lastMilestone = milestone
    }
}
```

### Parallel Jobs (Not Recommended)

While technically possible to run multiple jobs, it's **not recommended** because:
- Ollama can only process one LLaVA request at a time
- ChromaDB writes may conflict
- Memory usage multiplies

**Better approach:** Queue jobs and run sequentially.

---

## Migration from Standalone Script

### Before (Standalone Script)
```bash
# Old approach: Run index_photos.py directly
python3 index_photos.py 500

# Blocks terminal, no progress API, manual monitoring
```

### After (MCP Job API)
```python
# New approach: Use MCP job management
job = await start_indexing_job(batch_size=500)

# Poll for progress from Swift/any client
while True:
    status = await get_job_status(job_id=job.job_id)
    if status.status in ["completed", "failed"]:
        break
    await asyncio.sleep(1)
```

**Key Difference:** The MCP server now uses the **same comprehensive indexing logic** from `index_photos.py` (Apple Photos integration, HEIC conversion, rich metadata, caching), but exposed as pollable MCP tools for UI integration.

---

## Testing

### Test Job Lifecycle

```bash
# Start indexing 10 newest photos
mcp-tool start_indexing_job '{
  "batch_size": 10
}'
# Returns: Job ID abc-123

# Check status
mcp-tool get_job_status '{"job_id": "abc-123"}'

# List all jobs
mcp-tool list_jobs '{}'

# Cancel if needed
mcp-tool cancel_job '{"job_id": "abc-123"}'
```

---

## Future Enhancements

Potential improvements for v2:

1. **Persistent Jobs** - Save to SQLite, survive restarts
2. **Progress Events** - WebSocket notifications instead of polling
3. **Job Priorities** - High priority jobs run first
4. **Scheduled Jobs** - Cron-like auto-indexing
5. **Job History** - Keep completed jobs for audit trail
6. **Batch Operations** - Delete multiple jobs at once

---

## Summary

The job management API makes Apple Photos Library indexing:
- ✅ **Non-blocking** - Returns immediately
- ✅ **Pollable** - Check progress anytime
- ✅ **Cancellable** - Stop if needed
- ✅ **Trackable** - See what's being processed
- ✅ **UI-friendly** - Perfect for progress bars
- ✅ **Smart** - Automatically skips already-indexed photos
- ✅ **Comprehensive** - Uses full Apple Photos integration with rich metadata
- ✅ **Resumable** - Can stop/start without losing progress (via cache)

Use `start_indexing_job` + polling to integrate Apple Photos indexing into your Swift app!
