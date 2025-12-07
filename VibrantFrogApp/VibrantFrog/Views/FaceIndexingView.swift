//
//  FaceIndexingView.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import SwiftUI

struct FaceIndexingView: View {
    @State private var isIndexing: Bool = false
    @State private var indexingProgress: Double = 0
    @State private var processedCount: Int = 0
    @State private var totalCount: Int = 0
    @State private var facesDetected: Int = 0
    @State private var errorMessage: String?
    @State private var outputLog: [String] = []
    @State private var showBrowserSheet: Bool = false

    private let scriptPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-worktrees/VibrantFrogMCP/sweet-carson/index_faces.py")

    var body: some View {
        VStack(spacing: 24) {
            // Status card
            statusCard

            // Progress section (when indexing)
            if isIndexing {
                progressCard
            }

            // Actions
            actionsCard

            // Output log
            if !outputLog.isEmpty {
                logCard
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showBrowserSheet) {
            faceBrowserSheet
        }
    }

    // MARK: - Views

    private var statusCard: some View {
        GroupBox("Face Detection & Clustering") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Uses InsightFace to detect and cluster faces in your photo library.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Divider()

                HStack {
                    Image(systemName: "face.smiling")
                        .foregroundStyle(.blue)
                    Text("Face Indexing")
                    Spacer()
                    Text(isIndexing ? "Running..." : "Ready")
                        .foregroundStyle(isIndexing ? .orange : .green)
                }

                if facesDetected > 0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Faces Detected")
                        Spacer()
                        Text("\(facesDetected)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var progressCard: some View {
        GroupBox("Indexing Progress") {
            VStack(spacing: 16) {
                ProgressView(value: indexingProgress) {
                    HStack {
                        Text("Processing photos...")
                        Spacer()
                        Text("\(processedCount) / \(totalCount)")
                            .monospacedDigit()
                    }
                }

                if facesDetected > 0 {
                    Text("Detected \(facesDetected) faces so far")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Stop Indexing") {
                    stopIndexing()
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 8)
        }
    }

    private var actionsCard: some View {
        GroupBox("Actions") {
            VStack(spacing: 12) {
                Button {
                    startFaceIndexing(reindex: false)
                } label: {
                    Label("Start Face Detection", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isIndexing)

                Button {
                    startFaceIndexing(reindex: true)
                } label: {
                    Label("Reindex All Faces", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isIndexing)

                Divider()

                Button {
                    openFaceBrowser()
                } label: {
                    Label("Browse Face Clusters", systemImage: "person.3.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var logCard: some View {
        GroupBox("Output Log") {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(outputLog.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .onChange(of: outputLog.count) { _, _ in
                    if let lastIndex = outputLog.indices.last {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var faceBrowserSheet: some View {
        VStack {
            HStack {
                Text("Face Cluster Browser")
                    .font(.title2)

                Spacer()

                Button("Done") {
                    showBrowserSheet = false
                }
            }
            .padding()

            Divider()

            // For now, show a message about using the web interface
            VStack(spacing: 16) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Face Browser")
                    .font(.title3)

                Text("To browse and label face clusters, use the web interface:")
                    .multilineTextAlignment(.center)

                Text("python browse_faces_web.py")
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                Text("Then open http://localhost:8081 in your browser")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open in Browser") {
                    if let url = URL(string: "http://localhost:8081") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Actions

    private func startFaceIndexing(reindex: Bool) {
        isIndexing = true
        errorMessage = nil
        processedCount = 0
        totalCount = 0
        facesDetected = 0
        outputLog = []

        Task {
            do {
                // Build command
                var args = ["python3", scriptPath.path]
                if reindex {
                    args.append("--reindex")
                }

                // Execute the Python script
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = args

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                // Read output
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                        Task { @MainActor in
                            let lines = output.components(separatedBy: .newlines)
                            for line in lines where !line.isEmpty {
                                outputLog.append(line)
                                parseProgressLine(line)
                            }
                        }
                    }
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                        Task { @MainActor in
                            outputLog.append("ERROR: \(output)")
                        }
                    }
                }

                try process.run()
                process.waitUntilExit()

                await MainActor.run {
                    isIndexing = false
                    if process.terminationStatus != 0 {
                        errorMessage = "Face indexing failed with exit code \(process.terminationStatus)"
                    }
                }
            } catch {
                await MainActor.run {
                    isIndexing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopIndexing() {
        // This would require tracking the process and terminating it
        isIndexing = false
    }

    private func openFaceBrowser() {
        showBrowserSheet = true
    }

    private func parseProgressLine(_ line: String) {
        // Parse progress from log lines like "Processing photo 123/1000"
        if line.contains("Processing") || line.contains("photo") {
            let components = line.components(separatedBy: " ")
            for (index, component) in components.enumerated() {
                if component.contains("/") {
                    let parts = component.split(separator: "/")
                    if parts.count == 2,
                       let current = Int(parts[0]),
                       let total = Int(parts[1]) {
                        processedCount = current
                        totalCount = total
                        indexingProgress = Double(current) / Double(total)
                    }
                }
            }
        }

        // Parse faces detected
        if line.contains("face") && line.contains("detected") {
            let components = line.components(separatedBy: " ")
            for component in components {
                if let count = Int(component) {
                    facesDetected += count
                }
            }
        }
    }
}

#Preview {
    FaceIndexingView()
        .frame(width: 600, height: 700)
}
