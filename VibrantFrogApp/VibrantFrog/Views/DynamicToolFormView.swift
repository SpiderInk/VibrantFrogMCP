//
//  DynamicToolFormView.swift
//  VibrantFrog
//
//  Dynamic form generation from JSON schema for MCP tools
//

import SwiftUI

struct DynamicToolFormView: View {
    let tool: RegistryMCPTool
    @Binding var parameters: [String: Any]
    @State private var stringValues: [String: String] = [:]
    @State private var numberValues: [String: Double] = [:]
    @State private var boolValues: [String: Bool] = [:]

    var inputSchema: MCPTool.InputSchema? {
        print("🔍 DynamicToolFormView: inputSchema type = \(type(of: tool.inputSchema))")
        print("🔍 DynamicToolFormView: inputSchema value = \(tool.inputSchema)")

        if let schema = tool.inputSchema as? MCPTool.InputSchema {
            print("✅ Successfully cast to MCPTool.InputSchema")
            print("✅ Properties count: \(schema.properties?.count ?? 0)")
            print("✅ Required count: \(schema.required?.count ?? 0)")
            return schema
        } else {
            print("❌ Failed to cast inputSchema to MCPTool.InputSchema")
            return nil
        }
    }

    var properties: [String: MCPTool.InputSchema.Property] {
        inputSchema?.properties ?? [:]
    }

    var required: [String] {
        inputSchema?.required ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let sortedKeys = Array(properties.keys.sorted())
            let _ = print("📋 DynamicToolFormView: Rendering with \(sortedKeys.count) properties: \(sortedKeys)")

            ForEach(sortedKeys, id: \.self) { key in
                if let propSchema = properties[key] {
                    let _ = print("  📋 Creating FormField for '\(key)': \(propSchema)")
                    FormField(
                        key: key,
                        schema: propSchema,
                        isRequired: required.contains(key),
                        stringValues: $stringValues,
                        numberValues: $numberValues,
                        boolValues: $boolValues
                    )

                    Divider()
                }
            }
        }
        .onChange(of: stringValues) { updateParameters() }
        .onChange(of: numberValues) { updateParameters() }
        .onChange(of: boolValues) { updateParameters() }
        .onAppear {
            print("📋 DynamicToolFormView: onAppear called")
            print("📋 InputSchema: \(String(describing: inputSchema))")
            print("📋 Properties: \(properties)")
            print("📋 Required: \(required)")
            initializeDefaults()
        }
    }

    private func initializeDefaults() {
        for (key, propSchema) in properties {
            let type = propSchema.type

            switch type {
            case "string":
                if stringValues[key] == nil {
                    stringValues[key] = ""
                }
            case "integer", "number":
                if numberValues[key] == nil {
                    numberValues[key] = 0
                }
            case "boolean":
                if boolValues[key] == nil {
                    boolValues[key] = false
                }
            default:
                break
            }
        }
        updateParameters()
    }

    private func updateParameters() {
        var params: [String: Any] = [:]

        for (key, value) in stringValues where !value.isEmpty {
            params[key] = value
        }

        for (key, value) in numberValues {
            if let propSchema = properties[key],
               propSchema.type == "integer" {
                params[key] = Int(value)
            } else {
                params[key] = value
            }
        }

        for (key, value) in boolValues {
            params[key] = value
        }

        print("🔄 updateParameters() - New params: \(params)")
        parameters = params
    }
}

struct FormField: View {
    let key: String
    let schema: MCPTool.InputSchema.Property
    let isRequired: Bool
    @Binding var stringValues: [String: String]
    @Binding var numberValues: [String: Double]
    @Binding var boolValues: [String: Bool]

    var type: String {
        schema.type
    }

    var description: String {
        schema.description ?? ""
    }

    var label: String {
        key + (isRequired ? " *" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.primary)

            switch type {
            case "string":
                TextField(description, text: Binding(
                    get: {
                        let value = stringValues[key] ?? ""
                        print("📝 TextField[\(key)] GET: '\(value)'")
                        return value
                    },
                    set: { newValue in
                        print("📝 TextField[\(key)] SET: '\(newValue)'")
                        stringValues[key] = newValue
                    }
                ))
                .textFieldStyle(.roundedBorder)

            case "integer", "number":
                TextField("0", value: Binding(
                    get: { numberValues[key] ?? 0 },
                    set: { numberValues[key] = $0 }
                ), format: type == "integer" ? .number : .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            case "boolean":
                Toggle(label, isOn: Binding(
                    get: { boolValues[key] ?? false },
                    set: { boolValues[key] = $0 }
                ))

            default:
                TextField(description, text: Binding(
                    get: { stringValues[key] ?? "" },
                    set: { stringValues[key] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            if !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var params: [String: Any] = [:]

        var body: some View {
            let mockTool = RegistryMCPTool(
                serverID: UUID(),
                serverName: "Test",
                name: "search_photos",
                description: "Search photos",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Search query"
                        ],
                        "n_results": [
                            "type": "integer",
                            "description": "Number of results",
                            "default": 10
                        ]
                    ],
                    "required": ["query"]
                ],
                isEnabled: true
            )

            VStack {
                DynamicToolFormView(tool: mockTool, parameters: $params)
                Text("Parameters: \(String(describing: params))")
            }
        }
    }

    return PreviewWrapper()
}
