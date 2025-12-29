//
//  IndexingView.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import SwiftUI

struct IndexingView: View {
    var body: some View {
        PhotoIndexingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PhotoIndexingView: View {
    @EnvironmentObject var photoLibraryService: PhotoLibraryService
    @StateObject private var mcpClient = MCPClientHTTP()

    @State private var isIndexing: Bool = false
    @State private var indexingProgress: Double = 0
    @State private var processedCount: Int = 0
    @State private var totalToIndex: Int = 0
    @State private var currentPhotoName: String = ""
    @State private var errorMessage: String?
    @State private var showStopConfirmation: Bool = false
    @State private var batchSize: Int = 500
    @State private var includeCloud: Bool = true
    @State private var newestFirst: Bool = true

    // Job management
    @State private var currentJobId: String?
    @State private var pollTimer: Timer?

    // Statistics from cache file
    @State private var indexedPhotosCount: Int = 0
    @State private var hasLoggedCacheMissing: Bool = false

    // CloudKit sync
    @State private var isSyncingToCloud: Bool = false
    @State private var lastSyncDate: Date?
    private let cloudKitSync = CloudKitPhotoIndexSync.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Status card
                statusCard

                // Settings card (when not indexing)
                if !isIndexing {
                    settingsCard
                }

                // Progress section (when indexing)
                if isIndexing {
                    progressCard
                }

                // Statistics
                statisticsCard

                // CloudKit sync card
                cloudKitSyncCard

                // Actions
                actionsCard
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            print("📸 PhotoIndexingView: onAppear called")
            print("📸 PhotoIndexingView: MCP connected = \(mcpClient.isConnected)")
            print("📸 PhotoIndexingView: Photo Library authorized = \(photoLibraryService.isAuthorized)")
        }
        .task {
            print("📸 PhotoIndexingView: .task modifier executing")
            await setupMCPConnection()
            loadIndexedCount()
            print("📸 PhotoIndexingView: .task modifier complete")
        }
        .onDisappear {
            print("📸 PhotoIndexingView: onDisappear called")
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: - Views

    private var statusCard: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: photoLibraryService.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(photoLibraryService.isAuthorized ? .green : .red)
                    Text("Photo Library Access")
                    Spacer()
                    Text(photoLibraryService.isAuthorized ? "Granted" : "Not Granted")
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Image(systemName: mcpClient.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(mcpClient.isConnected ? .green : .orange)
                    Text("MCP Server")
                    Spacer()
                    Text(mcpClient.isConnected ? "Connected" : "Not Connected")
                        .foregroundStyle(.secondary)
                }

                if !mcpClient.isConnected {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MCP server is required for Apple Photos indexing")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Button("Retry Connection") {
                            Task {
                                await setupMCPConnection()
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var settingsCard: some View {
        GroupBox("Indexing Settings") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Batch Size")
                        Spacer()
                        TextField("Batch size", value: $batchSize, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("Number of photos to index (recommended: 100-500)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle("Include iCloud Photos", isOn: $includeCloud)
                    .help("Include photos stored in iCloud (may require download)")

                Divider()

                Toggle("Index Newest First", isOn: $newestFirst)
                    .help("Start with most recent photos for immediate value")
            }
            .padding(.vertical, 8)
        }
    }

    private var progressCard: some View {
        GroupBox("Indexing Progress") {
            VStack(spacing: 16) {
                ProgressView(value: indexingProgress) {
                    HStack {
                        Text("Processing Apple Photos Library...")
                        Spacer()
                        Text("\(processedCount) / \(totalToIndex)")
                            .monospacedDigit()
                    }
                }

                if !currentPhotoName.isEmpty {
                    Text("Current: \(currentPhotoName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("Indexing is slow (~2-3 min per photo). Already-indexed photos are automatically skipped.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Cancel Indexing") {
                    showStopConfirmation = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 8)
        }
        .confirmationDialog("Cancel Indexing?", isPresented: $showStopConfirmation) {
            Button("Cancel Job", role: .destructive) {
                cancelIndexing()
            }
            Button("Continue", role: .cancel) {}
        } message: {
            Text("Progress is saved after each photo. You can resume later.")
        }
    }

    private var statisticsCard: some View {
        GroupBox("Statistics") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Total Photos", systemImage: "photo.stack")
                    Spacer()
                    Text("\(photoLibraryService.totalPhotoCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Label("Indexed Photos", systemImage: "checkmark.square.fill")
                    Spacer()
                    Text("\(indexedPhotosCount)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Label("Remaining", systemImage: "square.dashed")
                    Spacer()
                    let remaining = photoLibraryService.totalPhotoCount - indexedPhotosCount
                    Text("\(max(0, remaining))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if indexedPhotosCount > 0 {
                    Divider()

                    HStack {
                        Label("Completion", systemImage: "chart.bar.fill")
                        Spacer()
                        let percent = photoLibraryService.totalPhotoCount > 0 ?
                            Double(indexedPhotosCount) / Double(photoLibraryService.totalPhotoCount) * 100 : 0
                        Text(String(format: "%.1f%%", percent))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var cloudKitSyncCard: some View {
        GroupBox("CloudKit Sync") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: cloudKitSync.isCloudKitAvailable ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(cloudKitSync.isCloudKitAvailable ? .blue : .gray)
                    Text("iCloud Status")
                    Spacer()
                    Text(cloudKitSync.isCloudKitAvailable ? "Available" : "Not Available")
                        .foregroundStyle(.secondary)
                }

                if let lastSync = lastSyncDate {
                    Divider()

                    HStack {
                        Label("Last Sync", systemImage: "clock")
                        Spacer()
                        Text(lastSync, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }

                if isSyncingToCloud {
                    Divider()

                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Uploading to iCloud...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Button {
                    Task {
                        await uploadToCloudKit()
                    }
                } label: {
                    Label("Enrich & Upload to iCloud", systemImage: "icloud.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSyncingToCloud || !cloudKitSync.isCloudKitAvailable)

                Text("Adds cloud IDs and uploads database file")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var actionsCard: some View {
        GroupBox("Actions") {
            VStack(spacing: 12) {
                // MCP-based indexing (legacy - requires MCP server)
                Button {
                    startIndexing()
                } label: {
                    Label("Start Indexing (via MCP)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartIndexing)

                // Debug info to show why button is disabled
                if !canStartIndexing && !isIndexing {
                    VStack(alignment: .leading, spacing: 4) {
                        if !photoLibraryService.isAuthorized {
                            Text("⚠️ Photo Library access not granted")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        if !mcpClient.isConnected {
                            Text("⚠️ MCP server not connected - use Terminal script instead")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Text("Recommended: Run indexing script from Terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Divider()

                Button {
                    loadIndexedCount()
                } label: {
                    Label("Refresh Statistics", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isIndexing)

                Divider()

                Button {
                    openTerminalWithIndexingScript()
                } label: {
                    Label("Open Terminal to Index Photos", systemImage: "terminal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Opens Terminal with the indexing script ready to run")
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var canStartIndexing: Bool {
        photoLibraryService.isAuthorized &&
        mcpClient.isConnected &&
        !isIndexing
    }

    // MARK: - MCP Actions

    private func setupMCPConnection() async {
        guard !mcpClient.isConnected else {
            print("🔌 setupMCPConnection: Already connected, skipping")
            return
        }

        print("🔌 setupMCPConnection: Attempting to connect to MCP server...")
        do {
            try await mcpClient.connect()
            print("✅ setupMCPConnection: Connection successful!")
        } catch {
            print("❌ setupMCPConnection: Connection failed: \(error)")
            await MainActor.run {
                errorMessage = "Failed to connect to MCP server: \(error.localizedDescription)"
            }
        }
    }

    private func startIndexing() {
        guard canStartIndexing else { return }

        Task {
            do {
                // Build arguments
                var args: [String: Any] = ["batch_size": batchSize]
                args["reverse_chronological"] = newestFirst
                args["include_cloud"] = includeCloud

                // Call start_indexing_job
                let result = try await mcpClient.callTool(
                    name: "start_indexing_job",
                    arguments: args
                )

                // Extract job_id from result
                if let jobId = extractJobId(from: result) {
                    await MainActor.run {
                        currentJobId = jobId
                        isIndexing = true
                        errorMessage = nil
                        processedCount = 0
                        totalToIndex = 0
                        currentPhotoName = ""
                    }

                    // Start polling for progress
                    startPolling()
                } else {
                    await MainActor.run {
                        errorMessage = "Failed to start indexing job"
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to start indexing: \(error.localizedDescription)"
                }
            }
        }
    }

    private func extractJobId(from result: ToolCallResult) -> String? {
        // Look for job_id in the text content
        for content in result.content {
            if content.type == "text", let text = content.text {
                // Parse job_id from text like "Job ID: abc-123..."
                if let range = text.range(of: "Job ID: "),
                   let endRange = text.range(of: "\n", range: range.upperBound..<text.endIndex) {
                    let jobId = String(text[range.upperBound..<endRange.lowerBound])
                    return jobId
                }
            }
        }
        return nil
    }

    private func startPolling() {
        // Poll every 2 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await self.updateStatus()
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
            if let statusInfo = parseJobStatus(from: result) {
                await MainActor.run {
                    processedCount = statusInfo.processedPhotos
                    totalToIndex = statusInfo.totalPhotos
                    currentPhotoName = statusInfo.currentPhoto ?? ""

                    if totalToIndex > 0 {
                        indexingProgress = Double(processedCount) / Double(totalToIndex)
                    }

                    // Refresh indexed count every 10 photos during active indexing
                    if statusInfo.status == "running" && processedCount % 10 == 0 {
                        loadIndexedCount()
                    }

                    // Check if job is done
                    if statusInfo.status == "completed" ||
                       statusInfo.status == "failed" ||
                       statusInfo.status == "cancelled" {
                        stopPolling()
                        isIndexing = false
                        currentJobId = nil

                        // Refresh statistics
                        loadIndexedCount()

                        if statusInfo.status == "failed" {
                            errorMessage = "Indexing job failed"
                        } else if statusInfo.status == "completed" {
                            // Auto-upload to CloudKit after successful indexing
                            Task {
                                await uploadToCloudKit()
                            }
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to get job status: \(error.localizedDescription)"
            }
        }
    }

    private func parseJobStatus(from result: ToolCallResult) -> JobStatusInfo? {
        // Parse the text content to extract status information
        for content in result.content {
            if content.type == "text", let text = content.text {
                var status = ""
                var processedPhotos = 0
                var totalPhotos = 0
                var currentPhoto: String?

                // Parse status line by line
                let lines = text.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("Job Status:") {
                        let parts = line.components(separatedBy: ": ")
                        if parts.count > 1 {
                            status = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
                        }
                    } else if line.contains("Progress:") {
                        // Parse "Progress: 10/500 photos (2.0%)"
                        if let range = line.range(of: "Progress: ") {
                            let progressStr = String(line[range.upperBound...])
                            let components = progressStr.components(separatedBy: "/")
                            if components.count > 1 {
                                processedPhotos = Int(components[0].trimmingCharacters(in: .whitespaces)) ?? 0
                                let totalStr = components[1].components(separatedBy: " ")[0]
                                totalPhotos = Int(totalStr.trimmingCharacters(in: .whitespaces)) ?? 0
                            }
                        }
                    } else if line.contains("Current:") {
                        let parts = line.components(separatedBy: ": ")
                        if parts.count > 1 {
                            currentPhoto = parts[1].trimmingCharacters(in: .whitespaces)
                        }
                    }
                }

                return JobStatusInfo(
                    status: status,
                    processedPhotos: processedPhotos,
                    totalPhotos: totalPhotos,
                    currentPhoto: currentPhoto
                )
            }
        }
        return nil
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func cancelIndexing() {
        guard let jobId = currentJobId else { return }

        Task {
            do {
                _ = try await mcpClient.callTool(
                    name: "cancel_job",
                    arguments: ["job_id": jobId]
                )

                await MainActor.run {
                    stopPolling()
                    isIndexing = false
                    currentJobId = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to cancel job: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadIndexedCount() {
        print("🔍 loadIndexedCount() called")

        // Read directly from the shared photo index database
        let databasePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("VibrantFrogPhotoIndex/photo_index.db")

        let pathString: String
        if #available(macOS 13, *) {
            pathString = databasePath.path(percentEncoded: false)
        } else {
            pathString = databasePath.path
        }

        print("🔍 Database path: \(pathString)")

        guard FileManager.default.fileExists(atPath: pathString) else {
            print("📊 Database not found - no photos indexed yet")
            DispatchQueue.main.async {
                self.indexedPhotosCount = 0
            }
            return
        }

        // Open database and count photos
        var db: OpaquePointer?
        guard sqlite3_open(pathString, &db) == SQLITE_OK else {
            print("❌ Failed to open database")
            DispatchQueue.main.async {
                self.indexedPhotosCount = 0
            }
            return
        }
        defer { sqlite3_close(db) }

        // Query count
        let sql = "SELECT COUNT(*) FROM photo_index"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Failed to prepare query")
            DispatchQueue.main.async {
                self.indexedPhotosCount = 0
            }
            return
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            let count = Int(sqlite3_column_int(statement, 0))
            print("📊 Found \(count) photos in database")

            DispatchQueue.main.async {
                self.indexedPhotosCount = count
            }
        } else {
            print("❌ Failed to read count")
            DispatchQueue.main.async {
                self.indexedPhotosCount = 0
            }
        }
    }

    private func openTerminalWithIndexingScript() {
        // Get the script path - assume it's in ~/git/VibrantFrogMCP/
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let scriptPath = homeDir.appendingPathComponent("git/VibrantFrogMCP/index_photos_icloud.py")

        // Build the terminal command
        let command = """
        cd ~/git/VibrantFrogMCP && \\
        echo "======================================" && \\
        echo "Photo Indexing Script" && \\
        echo "======================================" && \\
        echo "" && \\
        echo "Index all new photos:" && \\
        echo "  python3 index_photos_icloud.py" && \\
        echo "" && \\
        echo "Index just the newest 100:" && \\
        echo "  python3 index_photos_icloud.py 100" && \\
        echo "" && \\
        echo "Show current statistics:" && \\
        echo "  python3 index_photos_icloud.py --stats" && \\
        echo "" && \\
        echo "Run reconciliation to see missing photos:" && \\
        echo "  ./reconcile_simple.sh" && \\
        echo "" && \\
        echo "======================================" && \\
        exec $SHELL
        """

        // Create AppleScript to open Terminal and run command
        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """

        // Execute AppleScript
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("❌ Failed to open Terminal: \(error)")
            }
        }
    }

    // MARK: - CloudKit Sync

    private func uploadToCloudKit() async {
        guard cloudKitSync.isCloudKitAvailable else {
            await MainActor.run {
                errorMessage = "iCloud not available. Please sign in to iCloud."
            }
            return
        }

        // Path to shared photo index
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let databasePath = homeDir.appendingPathComponent("VibrantFrogPhotoIndex/photo_index.db")

        guard FileManager.default.fileExists(atPath: databasePath.path) else {
            await MainActor.run {
                errorMessage = "Photo index database not found at ~/VibrantFrogPhotoIndex/"
            }
            return
        }

        await MainActor.run {
            isSyncingToCloud = true
            errorMessage = nil
        }

        do {
            try await cloudKitSync.uploadPhotoIndex(databaseURL: databasePath)

            await MainActor.run {
                isSyncingToCloud = false
                lastSyncDate = Date()
            }
        } catch {
            await MainActor.run {
                isSyncingToCloud = false
                errorMessage = "CloudKit upload failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Helper Types

struct JobStatusInfo {
    let status: String
    let processedPhotos: Int
    let totalPhotos: Int
    let currentPhoto: String?
}

#Preview {
    IndexingView()
        .environmentObject(PhotoLibraryService())
        .frame(width: 600, height: 700)
}

#Preview("Photo Indexing") {
    PhotoIndexingView()
        .environmentObject(PhotoLibraryService())
        .frame(width: 500, height: 700)
}
