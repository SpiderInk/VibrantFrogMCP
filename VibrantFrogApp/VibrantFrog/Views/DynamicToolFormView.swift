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

    var schema: [String: Any] {
        (tool.inputSchema as? [String: Any]) ?? [:]
    }

    var properties: [String: [String: Any]] {
        (schema["properties"] as? [String: [String: Any]]) ?? [:]
    }

    var required: [String] {
        (schema["required"] as? [String]) ?? []
    }

    var body: some View {
        Form {
            ForEach(Array(properties.keys.sorted()), id: \.self) { key in
                if let propSchema = properties[key] {
                    FormField(
                        key: key,
                        schema: propSchema,
                        isRequired: required.contains(key),
                        stringValues: $stringValues,
                        numberValues: $numberValues,
                        boolValues: $boolValues
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: stringValues) { _ in updateParameters() }
        .onChange(of: numberValues) { _ in updateParameters() }
        .onChange(of: boolValues) { _ in updateParameters() }
        .onAppear {
            initializeDefaults()
        }
    }

    private func initializeDefaults() {
        for (key, propSchema) in properties {
            guard let type = propSchema["type"] as? String else { continue }

            switch type {
            case "string":
                if stringValues[key] == nil {
                    stringValues[key] = (propSchema["default"] as? String) ?? ""
                }
            case "integer", "number":
                if numberValues[key] == nil {
                    if let defaultNum = propSchema["default"] as? Double {
                        numberValues[key] = defaultNum
                    } else if let defaultInt = propSchema["default"] as? Int {
                        numberValues[key] = Double(defaultInt)
                    } else {
                        numberValues[key] = 0
                    }
                }
            case "boolean":
                if boolValues[key] == nil {
                    boolValues[key] = (propSchema["default"] as? Bool) ?? false
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
               let type = propSchema["type"] as? String,
               type == "integer" {
                params[key] = Int(value)
            } else {
                params[key] = value
            }
        }

        for (key, value) in boolValues {
            params[key] = value
        }

        parameters = params
    }
}

struct FormField: View {
    let key: String
    let schema: [String: Any]
    let isRequired: Bool
    @Binding var stringValues: [String: String]
    @Binding var numberValues: [String: Double]
    @Binding var boolValues: [String: Bool]

    var type: String {
        (schema["type"] as? String) ?? "string"
    }

    var description: String {
        (schema["description"] as? String) ?? ""
    }

    var label: String {
        key + (isRequired ? " *" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch type {
            case "string":
                LabeledContent(label) {
                    TextField(description, text: Binding(
                        get: { stringValues[key] ?? "" },
                        set: { stringValues[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

            case "integer", "number":
                LabeledContent(label) {
                    HStack {
                        TextField("0", value: Binding(
                            get: { numberValues[key] ?? 0 },
                            set: { numberValues[key] = $0 }
                        ), format: type == "integer" ? .number : .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                        if let minimum = schema["minimum"] as? Double,
                           let maximum = schema["maximum"] as? Double {
                            Slider(value: Binding(
                                get: { numberValues[key] ?? minimum },
                                set: { numberValues[key] = $0 }
                            ), in: minimum...maximum)
                        }
                    }
                }

            case "boolean":
                Toggle(label, isOn: Binding(
                    get: { boolValues[key] ?? false },
                    set: { boolValues[key] = $0 }
                ))

            default:
                LabeledContent(label) {
                    TextField(description, text: Binding(
                        get: { stringValues[key] ?? "" },
                        set: { stringValues[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
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
