//
//  PromptTemplatesView.swift
//  VibrantFrog
//
//  Grid view for managing prompt templates
//

import SwiftUI

struct PromptTemplatesView: View {
    @StateObject private var store = PromptTemplateStore()
    @State private var editingTemplate: PromptTemplate?
    @State private var showingNewTemplate = false
    @State private var showingVariables = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Prompt Templates")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { showingVariables = true }) {
                    Label("Variables", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)

                Button(action: { showingNewTemplate = true }) {
                    Label("New Template", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Grid of templates
            if store.templates.isEmpty {
                emptyView
            } else {
                templatesGrid
            }
        }
        .sheet(item: $editingTemplate) { template in
            PromptTemplateEditor(template: template, store: store)
        }
        .sheet(isPresented: $showingNewTemplate) {
            NewPromptTemplateSheet(store: store)
        }
        .sheet(isPresented: $showingVariables) {
            TemplateVariablesSheet()
        }
    }

    private var templatesGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
            ], spacing: 16) {
                ForEach(store.templates) { template in
                    TemplateCard(template: template)
                        .onTapGesture(count: 2) {
                            editingTemplate = template
                        }
                        .contextMenu {
                            Button("Edit") {
                                editingTemplate = template
                            }

                            if !template.isBuiltIn {
                                Button("Delete", role: .destructive) {
                                    store.deleteTemplate(template)
                                }
                            }
                        }
                }
            }
            .padding()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Prompt Templates")
                .font(.title3)

            Button("Create Your First Template") {
                showingNewTemplate = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: PromptTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(template.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if template.isBuiltIn {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Text(template.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text("Edited: \(template.lastEdited.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(height: 150)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Template Editor

struct PromptTemplateEditor: View {
    let template: PromptTemplate
    let store: PromptTemplateStore

    @State private var name: String
    @State private var content: String
    @Environment(\.dismiss) private var dismiss

    init(template: PromptTemplate, store: PromptTemplateStore) {
        self.template = template
        self.store = store
        _name = State(initialValue: template.name)
        _content = State(initialValue: template.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Template")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    store.updateTemplate(template, name: name, content: content)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || content.isEmpty)
            }
            .padding()

            Divider()

            // Editor
            Form {
                Section("Template Name") {
                    TextField("Name", text: $name)
                        .disabled(template.isBuiltIn)
                }

                Section("Prompt Content") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 300)
                }

                Section("Available Variables") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(PromptTemplate.availableVariables().prefix(5), id: \.name) { variable in
                            HStack {
                                Text("{{\(variable.name)}}")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.blue)
                                Text("-")
                                    .foregroundStyle(.secondary)
                                Text(variable.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 700, height: 600)
    }
}

// MARK: - New Template Sheet

struct NewPromptTemplateSheet: View {
    let store: PromptTemplateStore

    @State private var name: String = ""
    @State private var content: String = "You are a helpful AI assistant.\n\nDate: {{DATE}}\nTools: {{TOOLS}}"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Template")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Create") {
                    store.addTemplate(name: name, content: content)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || content.isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section("Template Name") {
                    TextField("Enter template name...", text: $name)
                }

                Section("Prompt Content") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 300)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Variables Sheet

struct TemplateVariablesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Template Variables")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            List(PromptTemplate.availableVariables(), id: \.name) { variable in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("{{\(variable.name)}}")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.blue)

                        Spacer()
                    }

                    Text(variable.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Example: \(variable.example)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 500, height: 400)
    }
}

#Preview {
    PromptTemplatesView()
}
