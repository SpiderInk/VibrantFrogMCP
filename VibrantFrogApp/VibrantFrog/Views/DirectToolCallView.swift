//
//  DirectToolCallView.swift
//  VibrantFrog
//
//  Direct MCP tool calling interface
//

import SwiftUI

struct DirectToolCallView: View {
    @StateObject private var registry = MCPServerRegistry()
    @EnvironmentObject var mcpClient: MCPClientHTTP
    @StateObject private var photoService = PhotoLibraryService()

    @State private var selectedTool: RegistryMCPTool?
    @State private var parameters: [String: Any] = [:]
    @State private var isExecuting = false
    @State private var result: String = ""
    @State private var photoUUIDs: [String] = []
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var callHistory: [ToolCallRecord] = []
    @State private var availableTools: [RegistryMCPTool] = []
    @State private var isLoadingAvailableTools = false

    var body: some View {
        HSplitView {
            // Left: Tool selector and form
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Direct Tool Calling")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button(action: loadAllTools) {
                        Label("Refresh Tools", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
                .padding()

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Tool selector
                        GroupBox("Select Tool") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Tool", selection: $selectedTool) {
                                    Text("Choose a tool...").tag(nil as RegistryMCPTool?)
                                    ForEach(availableTools) { tool in
                                        Text("\(tool.name) (\(tool.serverName))").tag(tool as RegistryMCPTool?)
                                    }
                                }
                                .labelsHidden()

                                if let tool = selectedTool {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tool.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        HStack {
                                            Label(tool.serverName, systemImage: "server.rack")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)

                                            Spacer()
                                        }
                                    }
                                }
                            }
                            .padding()
                        }

                        // Dynamic form
                        if let tool = selectedTool {
                            GroupBox("Parameters") {
                                DynamicToolFormView(tool: tool, parameters: $parameters)
                                    .padding()
                                    .id(tool.id) // Force re-creation when tool changes
                            }

                            // Execute button
                            Button(action: executeToolCall) {
                                HStack {
                                    if isExecuting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                    Text(isExecuting ? "Executing..." : "Execute Tool")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isExecuting || !isValidParameters)
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
            }
            .frame(minWidth: 400, maxWidth: 500)

            // Right: Results and history
            VStack(spacing: 0) {
                // Tabs
                TabView {
                    // Results tab
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if result.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary)
                                    Text("Execute a tool to see results")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding()
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Result")
                                            .font(.headline)
                                        Spacer()
                                        Button(action: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(result, forType: .string)
                                        }) {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    Text(result)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(8)

                                    // Photo thumbnails
                                    if !photoUUIDs.isEmpty {
                                        Text("Photos (\(photoUUIDs.count))")
                                            .font(.headline)

                                        LazyVGrid(columns: [
                                            GridItem(.adaptive(minimum: 150, maximum: 200))
                                        ], spacing: 12) {
                                            ForEach(photoUUIDs, id: \.self) { uuid in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    if let image = thumbnails[uuid] {
                                                        Image(nsImage: image)
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(height: 150)
                                                            .clipped()
                                                            .cornerRadius(8)
                                                            .onTapGesture {
                                                                openPhoto(uuid: uuid)
                                                            }
                                                    } else {
                                                        Button(action: {
                                                            openPhoto(uuid: uuid)
                                                        }) {
                                                            VStack(spacing: 8) {
                                                                Image(systemName: "photo.fill")
                                                                    .font(.system(size: 40))
                                                                    .foregroundStyle(.blue)
                                                                Text("Open in Photos")
                                                                    .font(.caption)
                                                                    .foregroundStyle(.blue)
                                                            }
                                                            .frame(height: 150)
                                                            .frame(maxWidth: .infinity)
                                                            .background(Color.blue.opacity(0.1))
                                                            .cornerRadius(8)
                                                        }
                                                        .buttonStyle(.plain)
                                                    }

                                                    Text(uuid)
                                                        .font(.caption2)
                                                        .lineLimit(1)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    .tabItem {
                        Label("Results", systemImage: "terminal.fill")
                    }

                    // History tab
                    ScrollView {
                        if callHistory.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "clock")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("No call history yet")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(callHistory.reversed()) { record in
                                    HistoryRowView(record: record) {
                                        // Re-run with same parameters
                                        selectedTool = record.tool
                                        parameters = record.parameters
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    .tabItem {
                        Label("History", systemImage: "clock.fill")
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadAllTools()
            if !photoService.isAuthorized {
                photoService.requestAuthorization()
            }
        }
        .onChange(of: selectedTool) { _ in
            // Clear parameters when tool selection changes
            parameters = [:]
        }
    }

    private var isValidParameters: Bool {
        guard let tool = selectedTool else { return false }
        guard let schema = tool.inputSchema as? [String: Any],
              let required = schema["required"] as? [String] else {
            return true
        }

        for key in required {
            if parameters[key] == nil {
                return false
            }
        }
        return true
    }

    private func loadAllTools() {
        print("🔧 DirectToolCallView: loadAllTools() called")
        guard !isLoadingAvailableTools else {
            print("⚠️ DirectToolCallView: Already loading tools, skipping")
            return
        }

        isLoadingAvailableTools = true
        print("🔧 DirectToolCallView: Starting to load tools from registry...")
        Task {
            do {
                let tools = try await registry.getAllTools()
                print("🔧 DirectToolCallView: Got \(tools.count) tools from registry")
                for tool in tools {
                    print("  - \(tool.name) (\(tool.serverName))")
                }
                await MainActor.run {
                    availableTools = tools
                    isLoadingAvailableTools = false
                    print("🔧 DirectToolCallView: Updated availableTools, count = \(availableTools.count)")
                }
            } catch {
                print("❌ DirectToolCallView: Failed to load tools: \(error)")
                await MainActor.run {
                    availableTools = []
                    isLoadingAvailableTools = false
                }
            }
        }
    }

    private func executeToolCall() {
        guard let tool = selectedTool else { return }

        isExecuting = true
        result = ""
        photoUUIDs = []
        thumbnails = [:]

        Task {
            do {
                // Connect if needed
                if !mcpClient.isConnected {
                    try await mcpClient.connect()
                }

                // Execute tool
                let toolResult = try await mcpClient.callTool(name: tool.name, arguments: parameters)

                // Extract text content
                let textContent = toolResult.content
                    .filter { $0.type == "text" }
                    .compactMap { $0.text }
                    .joined(separator: "\n")

                await MainActor.run {
                    result = textContent

                    // Parse UUIDs if this is a photo search
                    if tool.name.contains("search") || tool.name.contains("photo") {
                        photoUUIDs = parseUUIDs(from: textContent)
                        if !photoUUIDs.isEmpty {
                            loadThumbnails()
                        }
                    }

                    // Add to history
                    callHistory.append(ToolCallRecord(
                        tool: tool,
                        parameters: parameters,
                        result: textContent
                    ))

                    isExecuting = false
                }
            } catch {
                await MainActor.run {
                    result = "Error: \(error.localizedDescription)"
                    isExecuting = false
                }
            }
        }
    }

    private func parseUUIDs(from text: String) -> [String] {
        var uuids: [String] = []
        let lines = text.split(separator: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("uuid=") {
                if let uuidRange = trimmed.range(of: "uuid=") {
                    let uuid = String(trimmed[uuidRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: CharacterSet.whitespaces)[0]
                    if uuid.contains("-") && uuid.count > 20 {
                        uuids.append(uuid)
                    }
                }
            } else if trimmed.contains("UUID:") {
                if let uuidPart = trimmed.split(separator: ":").last {
                    let uuid = String(uuidPart).trimmingCharacters(in: .whitespaces)
                    if uuid.contains("-") && uuid.count > 20 {
                        uuids.append(uuid)
                    }
                }
            }
        }

        return Array(Set(uuids)) // Remove duplicates
    }

    private func loadThumbnails() {
        Task {
            let loaded = await photoService.loadThumbnailsByUUIDs(photoUUIDs)
            await MainActor.run {
                thumbnails = loaded
            }
        }
    }

    private func openPhoto(uuid: String) {
        let url = URL(string: "photos://asset?uuid=\(uuid)")!
        NSWorkspace.shared.open(url)
    }
}

struct ToolCallRecord: Identifiable, Hashable {
    let id = UUID()
    let tool: RegistryMCPTool
    let parameters: [String: Any]
    let result: String
    let timestamp = Date()

    static func == (lhs: ToolCallRecord, rhs: ToolCallRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct HistoryRowView: View {
    let record: ToolCallRecord
    let onRerun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.tool.name)
                        .font(.headline)
                    Text(record.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onRerun) {
                    Label("Re-run", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            Text("Parameters:")
                .font(.caption)
                .fontWeight(.semibold)
            Text(formatParameters(record.parameters))
                .font(.caption)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)

            Text("Result:")
                .font(.caption)
                .fontWeight(.semibold)
            Text(record.result.prefix(200) + (record.result.count > 200 ? "..." : ""))
                .font(.caption2)
                .lineLimit(3)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private func formatParameters(_ params: [String: Any]) -> String {
        params.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }
}

#Preview {
    DirectToolCallView()
        .environmentObject(MCPClientHTTP())
}
