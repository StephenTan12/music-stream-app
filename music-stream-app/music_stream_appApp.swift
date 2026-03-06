//
//  music_stream_appApp.swift
//  music-stream-app
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.music-stream-app", category: "App")

@main
struct music_stream_appApp: App {
    @State private var modelContainerError: Error?
    
    let sharedModelContainer: ModelContainer?
    
    init() {
        let schema = Schema([
            Playlist.self,
            Song.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            logger.error("Could not create ModelContainer: \(error.localizedDescription)")
            sharedModelContainer = nil
            modelContainerError = error
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if let container = sharedModelContainer {
                ContentView()
                    .modelContainer(container)
            } else {
                DataErrorView(error: modelContainerError)
            }
        }
    }
}

struct DataErrorView: View {
    let error: Error?
    
    var body: some View {
        ContentUnavailableView {
            Label("Data Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Failed to load app data. Please restart the app or contact support.")
            if let error = error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
