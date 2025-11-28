//
//  ConversationStore.swift
//  VibrantFrog
//
//  Manages conversation persistence
//

import Foundation
import Combine

@MainActor
class ConversationStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?

    private let fileManager = FileManager.default
    private let conversationsDirectory: URL

    init() {
        // Store conversations in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        conversationsDirectory = appSupport.appendingPathComponent("VibrantFrogMCP/Conversations", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)

        loadConversations()
    }

    // MARK: - Persistence

    private func conversationFileURL(for id: UUID) -> URL {
        conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func loadConversations() {
        guard let files = try? fileManager.contentsOfDirectory(at: conversationsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        var loaded: [Conversation] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let conversation = try? JSONDecoder().decode(Conversation.self, from: data) else {
                continue
            }
            loaded.append(conversation)
        }

        // Sort by most recent first
        conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveConversation(_ conversation: Conversation) {
        let url = conversationFileURL(for: conversation.id)

        do {
            let data = try JSONEncoder().encode(conversation)
            try data.write(to: url)

            // Update in-memory list
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index] = conversation
            } else {
                conversations.insert(conversation, at: 0)
            }

            // Re-sort
            conversations.sort { $0.updatedAt > $1.updatedAt }

        } catch {
            print("Failed to save conversation: \(error)")
        }
    }

    func deleteConversation(_ conversation: Conversation) {
        let url = conversationFileURL(for: conversation.id)

        try? fileManager.removeItem(at: url)

        conversations.removeAll { $0.id == conversation.id }

        if currentConversation?.id == conversation.id {
            currentConversation = nil
        }
    }

    // MARK: - Conversation Management

    func createNewConversation(model: String = "llama3.2:latest", mcpServerIDs: [UUID] = []) -> Conversation {
        let conversation = Conversation(selectedModel: model, mcpServerIDs: mcpServerIDs)
        currentConversation = conversation
        return conversation
    }

    func loadConversation(_ conversation: Conversation) {
        currentConversation = conversation
    }

    func updateCurrentConversation(_ conversation: Conversation) {
        currentConversation = conversation
        saveConversation(conversation)
    }

    func getAllConversations() -> [Conversation] {
        return conversations
    }
}
