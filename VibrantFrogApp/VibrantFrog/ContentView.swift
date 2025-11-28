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
    case mcp = "MCP Server"
    case toolCalling = "Tool Calling"
    case indexing = "Indexing"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .aiChat: return "brain"
        case .conversations: return "bubble.left.and.bubble.right"
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
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.icon)
                }
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
