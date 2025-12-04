//
//  PromptTemplateStore.swift
//  VibrantFrog
//
//  Manages prompt template persistence and defaults
//

import Foundation

@MainActor
class PromptTemplateStore: ObservableObject {
    @Published var templates: [PromptTemplate] = []

    private let defaults = UserDefaults.standard
    private let templatesKey = "prompt_templates"

    init() {
        loadTemplates()
    }

    // MARK: - Persistence

    private func loadTemplates() {
        guard let data = defaults.data(forKey: templatesKey),
              let decoded = try? JSONDecoder().decode([PromptTemplate].self, from: data) else {
            // Load default templates
            templates = createDefaultTemplates()
            saveTemplates()
            return
        }

        // Merge with defaults (in case new defaults were added)
        let existingIds = Set(decoded.map { $0.id })
        let defaults = createDefaultTemplates().filter { !existingIds.contains($0.id) }

        templates = decoded + defaults
        if !defaults.isEmpty {
            saveTemplates()
        }
    }

    private func saveTemplates() {
        if let encoded = try? JSONEncoder().encode(templates) {
            defaults.set(encoded, forKey: templatesKey)
        }
    }

    // MARK: - Template Management

    func addTemplate(name: String, content: String) {
        let template = PromptTemplate(
            name: name,
            content: content,
            lastEdited: Date(),
            isBuiltIn: false
        )
        templates.append(template)
        saveTemplates()
    }

    func updateTemplate(_ template: PromptTemplate, name: String? = nil, content: String? = nil) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            if let newName = name {
                templates[index].name = newName
            }
            if let newContent = content {
                templates[index].content = newContent
            }
            templates[index].lastEdited = Date()
            saveTemplates()
        }
    }

    func deleteTemplate(_ template: PromptTemplate) {
        guard !template.isBuiltIn else { return }
        templates.removeAll { $0.id == template.id }
        saveTemplates()
    }

    // MARK: - Default Templates

    private func createDefaultTemplates() -> [PromptTemplate] {
        return [
            PromptTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Photo Assistant",
                content: """
                You are a helpful AI assistant with access to tools via function calling.

                ABSOLUTELY CRITICAL - YOU MUST FOLLOW THESE RULES:
                1. When users ask about photos, YOU MUST USE FUNCTION CALLING to invoke the tools
                2. DO NOT write JSON or describe function calls - USE THE ACTUAL FUNCTION CALLING MECHANISM
                3. DO NOT output text like {"name":"search_photos",...} - that is WRONG
                4. DO NOT explain what you will do - JUST DO IT by calling the function
                5. NEVER say "I will search" or "Let me find" - CALL THE FUNCTION IMMEDIATELY

                You have these tools available:
                {{TOOLS}}

                EXAMPLE OF CORRECT BEHAVIOR:
                User: "Show me beach photos"
                Assistant: [CALLS search_photos function with query="beach", n_results=10]
                [After getting results]
                Assistant: "I found 10 beach photos for you!"

                EXAMPLE OF WRONG BEHAVIOR:
                User: "Show me beach photos"
                Assistant: {"name":"search_photos","parameters":{"query":"beach"}} <- THIS IS WRONG!

                Remember: USE FUNCTION CALLING, not text descriptions of function calls.

                Today is {{DAY}}, {{DATE}}.
                """,
                lastEdited: Date(),
                isBuiltIn: true
            ),
            PromptTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "General Assistant",
                content: """
                You are a helpful AI assistant with access to various tools.

                Current date: {{DATE}}
                Current time: {{TIME}}

                Available tools:
                {{TOOLS}}

                When users request information or actions, use the appropriate tools to help them.
                Always be clear, concise, and helpful in your responses.
                """,
                lastEdited: Date(),
                isBuiltIn: true
            ),
            PromptTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Blank Template",
                content: """
                You are a helpful AI assistant.

                Date: {{DATE}}
                Tools: {{TOOLS}}
                """,
                lastEdited: Date(),
                isBuiltIn: true
            )
        ]
    }
}
