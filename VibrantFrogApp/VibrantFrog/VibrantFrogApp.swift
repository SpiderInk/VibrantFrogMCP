//
//  VibrantFrogApp.swift
//  VibrantFrog
//
//  Created by Tony Piazza on 2025.
//  Copyright © 2025 Tony Piazza. All rights reserved.
//

import SwiftUI

@main
struct VibrantFrogApp: App {
    @StateObject private var photoLibraryService = PhotoLibraryService()
    @StateObject private var llmService = LLMService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(photoLibraryService)
                .environmentObject(llmService)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About VibrantFrog") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "VibrantFrog",
                            .applicationVersion: "1.0",
                            .credits: NSAttributedString(
                                string: "AI-powered photo search and organization",
                                attributes: [.font: NSFont.systemFont(ofSize: 11)]
                            )
                        ]
                    )
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(photoLibraryService)
                .environmentObject(llmService)
        }
    }
}
