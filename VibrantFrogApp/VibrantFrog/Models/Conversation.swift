//
//  Conversation.swift
//  VibrantFrog
//
//  Conversation model for chat persistence
//

import Foundation

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ConversationMessage]
    var createdAt: Date
    var updatedAt: Date
    var selectedModel: String
    var mcpServerIDs: [UUID]

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(id: UUID = UUID(), title: String = "New Conversation", messages: [ConversationMessage] = [], selectedModel: String = "llama3.2:latest", mcpServerIDs: [UUID] = []) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = Date()
        self.updatedAt = Date()
        self.selectedModel = selectedModel
        self.mcpServerIDs = mcpServerIDs
    }

    /// Auto-generate title from first user message
    mutating func updateTitleFromFirstMessage() {
        guard title == "New Conversation" || title.isEmpty else { return }

        if let firstUserMessage = messages.first(where: { $0.role == "user" }) {
            // Take first 50 chars of first message as title
            let text = firstUserMessage.content.prefix(50)
            self.title = String(text) + (firstUserMessage.content.count > 50 ? "..." : "")
        }
    }

    mutating func addMessage(_ message: ConversationMessage) {
        messages.append(message)
        updatedAt = Date()
        updateTitleFromFirstMessage()
    }
}

struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let role: String // "user", "assistant", "system"
    var content: String
    let timestamp: Date
    var toolCalls: [ToolCall]?
    var photoUUIDs: [String]? // UUIDs of photos to display

    init(id: UUID = UUID(), role: String, content: String, toolCalls: [ToolCall]? = nil, photoUUIDs: [String]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.toolCalls = toolCalls
        self.photoUUIDs = photoUUIDs
    }
}

struct ToolCall: Codable {
    let name: String
    let arguments: String
    var result: String?
}
