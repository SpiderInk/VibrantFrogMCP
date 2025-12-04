//
//  PromptTemplate.swift
//  VibrantFrog
//
//  Prompt templates with variable substitution
//

import Foundation

struct PromptTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var lastEdited: Date
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, content: String, lastEdited: Date = Date(), isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.content = content
        self.lastEdited = lastEdited
        self.isBuiltIn = isBuiltIn
    }

    /// Render the template with variable substitution
    func render(withTools tools: [String] = [], mcpServerName: String? = nil) -> String {
        var rendered = content

        // Replace standard variables
        let variables = PromptTemplateVariables.current()
        rendered = rendered.replacingOccurrences(of: "{{DATE}}", with: variables.date)
        rendered = rendered.replacingOccurrences(of: "{{TIME}}", with: variables.time)
        rendered = rendered.replacingOccurrences(of: "{{DATETIME}}", with: variables.datetime)
        rendered = rendered.replacingOccurrences(of: "{{DAY}}", with: variables.day)
        rendered = rendered.replacingOccurrences(of: "{{YEAR}}", with: variables.year)

        // Replace tools list if present
        if !tools.isEmpty {
            let toolsList = tools.joined(separator: "\n")
            rendered = rendered.replacingOccurrences(of: "{{TOOLS}}", with: toolsList)
        }

        // Replace MCP server name if present
        if let serverName = mcpServerName {
            rendered = rendered.replacingOccurrences(of: "{{MCP_SERVER}}", with: serverName)
        }

        return rendered
    }

    /// Get list of all available template variables
    static func availableVariables() -> [TemplateVariable] {
        return [
            TemplateVariable(name: "DATE", description: "Current date (YYYY-MM-DD)", example: "2025-01-15"),
            TemplateVariable(name: "TIME", description: "Current time (HH:mm:ss)", example: "14:30:00"),
            TemplateVariable(name: "DATETIME", description: "Current date and time", example: "2025-01-15 14:30:00"),
            TemplateVariable(name: "DAY", description: "Day of week", example: "Monday"),
            TemplateVariable(name: "YEAR", description: "Current year", example: "2025"),
            TemplateVariable(name: "TOOLS", description: "List of available MCP tools (auto-populated)", example: "- search_photos(...)\n- create_album(...)"),
            TemplateVariable(name: "MCP_SERVER", description: "Name of active MCP server", example: "VibrantFrog Photos"),
        ]
    }
}

struct TemplateVariable {
    let name: String
    let description: String
    let example: String
}

/// Current values for template variables
struct PromptTemplateVariables {
    let date: String
    let time: String
    let datetime: String
    let day: String
    let year: String

    static func current() -> PromptTemplateVariables {
        let now = Date()
        let dateFormatter = DateFormatter()

        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "HH:mm:ss"
        let time = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let datetime = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "EEEE"
        let day = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyy"
        let year = dateFormatter.string(from: now)

        return PromptTemplateVariables(
            date: date,
            time: time,
            datetime: datetime,
            day: day,
            year: year
        )
    }
}
