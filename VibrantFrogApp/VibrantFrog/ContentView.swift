//
//  ContentView.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case aiChat = "AI Chat"
    case conversations = "Conversations"
    case prompts = "Prompts"
    case mcp = "MCP Server"
    case toolCalling = "Tool Calling"
    case indexing = "Indexing"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .aiChat: return "brain"
        case .conversations: return "bubble.left.and.bubble.right"
        case .prompts: return "doc.text"
        case .mcp: return "network"
        case .toolCalling: return "terminal"
        case .indexing: return "arrow.triangle.2.circlepath"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var photoLibraryService: PhotoLibraryService
    @EnvironmentObject var llmService: LLMService
    @StateObject private var mcpClient = MCPClientHTTP()
    @StateObject private var conversationStore = ConversationStore()
    @State private var selectedItem: NavigationItem? = .aiChat

    var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            switch selectedItem {
            case .aiChat:
                AIChatView()
                    .environmentObject(mcpClient)
                    .environmentObject(conversationStore)
            case .conversations:
                ConversationHistoryView()
                    .environmentObject(conversationStore)
            case .prompts:
                PromptTemplatesView()
            case .mcp:
                MCPManagementView()
            case .toolCalling:
                DirectToolCallView()
                    .environmentObject(mcpClient)
            case .indexing:
                IndexingView()
            case .settings:
                SettingsView()
            case .none:
                Text("Select an item")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            photoLibraryService.requestAuthorization()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PhotoLibraryService())
        .environmentObject(LLMService())
}
