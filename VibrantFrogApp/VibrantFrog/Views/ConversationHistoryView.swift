//
//  ConversationHistoryView.swift
//  VibrantFrog
//
//  View for managing conversation history
//

import SwiftUI

struct ConversationHistoryView: View {
    @EnvironmentObject var conversationStore: ConversationStore
    @State private var searchText = ""
    @State private var selectedConversation: Conversation?

    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversationStore.conversations
        } else {
            return conversationStore.conversations.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: createNewConversation) {
                    Label("New Conversation", systemImage: "plus.circle.fill")
                }
            }
            .padding()

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search conversations...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Conversation list
            if filteredConversations.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "No conversations yet" : "No matching conversations")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    if searchText.isEmpty {
                        Button(action: createNewConversation) {
                            Label("Start a New Conversation", systemImage: "plus.circle")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedConversation) {
                    ForEach(filteredConversations) { conversation in
                        ConversationRow(conversation: conversation)
                            .tag(conversation)
                            .contextMenu {
                                Button(action: {
                                    loadConversation(conversation)
                                }) {
                                    Label("Open", systemImage: "arrow.right.circle")
                                }
                                Button(role: .destructive, action: {
                                    deleteConversation(conversation)
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .onTapGesture(count: 2) {
                                loadConversation(conversation)
                            }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer stats
            HStack {
                Text("\(filteredConversations.count) conversation\(filteredConversations.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func createNewConversation() {
        let newConv = conversationStore.createNewConversation()
        selectedConversation = newConv
    }

    private func loadConversation(_ conversation: Conversation) {
        conversationStore.loadConversation(conversation)
        // Note: User will need to switch to AI Chat tab to see it
    }

    private func deleteConversation(_ conversation: Conversation) {
        conversationStore.deleteConversation(conversation)
        if selectedConversation?.id == conversation.id {
            selectedConversation = nil
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(conversation.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("\(conversation.messages.count) messages", systemImage: "message")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(conversation.selectedModel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }

            if let firstUserMessage = conversation.messages.first(where: { $0.role == "user" }) {
                Text(firstUserMessage.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ConversationHistoryView()
        .environmentObject(ConversationStore())
}
