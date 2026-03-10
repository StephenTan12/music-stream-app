//
//  DownloadStorageView.swift
//  music-stream-app
//

import SwiftUI
import SwiftData

struct DownloadStorageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var downloadService = DownloadService.shared
    @State private var showRemoveAllConfirmation = false
    
    @Query(filter: #Predicate<Song> { $0.localFilePath != nil }, sort: \Song.title)
    private var downloadedSongs: [Song]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Storage Used", systemImage: "internaldrive")
                        Spacer()
                        Text(downloadService.formattedStorageUsed())
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Downloaded Songs", systemImage: "music.note")
                        Spacer()
                        Text("\(downloadedSongs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !downloadedSongs.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            showRemoveAllConfirmation = true
                        } label: {
                            Label("Remove All Downloads", systemImage: "trash")
                        }
                    } footer: {
                        Text("This will remove all downloaded songs from your device. You can download them again when connected to the internet.")
                    }
                    
                    Section("Downloaded Songs") {
                        ForEach(downloadedSongs) { song in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(song.title)
                                        .lineLimit(1)
                                    Text(song.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Button {
                                    downloadService.removeSongDownload(song)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Remove All Downloads",
                isPresented: $showRemoveAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove All", role: .destructive) {
                    downloadService.removeAllDownloads(modelContext: modelContext)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to remove all downloaded songs? This action cannot be undone.")
            }
            .onAppear {
                downloadService.cleanupStalePaths(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    DownloadStorageView()
        .modelContainer(for: [Song.self, Playlist.self, PlaylistSong.self], inMemory: true)
}
