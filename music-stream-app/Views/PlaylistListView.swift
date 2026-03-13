//
//  PlaylistListView.swift
//  music-stream-app
//

import SwiftUI
import SwiftData

struct PlaylistListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    
    @State private var audioPlayer = AudioPlayerService.shared
    @State private var playlistService = PlaylistService.shared
    @State private var downloadService = DownloadService.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var hasLoadedOnce = false
    @State private var isInitialLoad = true
    @State private var showDownloadStorage = false
    @State private var showSettings = false
    
    private var hasMiniPlayer: Bool {
        audioPlayer.currentSong != nil
    }
    
    private var sortedPlaylists: [Playlist] {
        playlists.sorted { lhs, rhs in
            if lhs.isSystem != rhs.isSystem {
                return lhs.isSystem
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
    
    var body: some View {
        Group {
            if isInitialLoad && playlistService.isLoading && playlists.isEmpty {
                loadingView
            } else if playlists.isEmpty && !playlistService.isLoading {
                emptyStateView
            } else {
                playlistsView
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !networkMonitor.isConnected {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.secondary)
                } else if !networkMonitor.isServerReachable {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showDownloadStorage = true
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .accessibilityLabel("Downloads")
                .id("downloads-storage-button")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showDownloadStorage) {
            DownloadStorageView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView {
                hasLoadedOnce = false
                isInitialLoad = true
                Task {
                    await playlistService.syncPlaylistMetadata(modelContext: modelContext)
                    hasLoadedOnce = true
                    isInitialLoad = false
                }
            }
        }
        .task {
            if !hasLoadedOnce {
                await playlistService.syncPlaylistMetadata(modelContext: modelContext)
                hasLoadedOnce = true
                isInitialLoad = false
            }
        }
        .alert("Error", isPresented: Binding(
            get: { playlistService.error != nil },
            set: { if !$0 { playlistService.error = nil } }
        )) {
            Button("OK") {
                playlistService.error = nil
            }
        } message: {
            if let error = playlistService.error {
                Text(error.localizedDescription)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading playlists...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Playlists", systemImage: "music.note.list")
        } description: {
            Text("Pull to refresh to sync playlists from the server")
        }
    }
    
    private var playlistsView: some View {
        List {
            ForEach(sortedPlaylists) { playlist in
                NavigationLink(value: playlist) {
                    PlaylistRowView(playlist: playlist)
                }
            }
        }
        .contentMargins(.bottom, hasMiniPlayer ? 60 : 0, for: .scrollContent)
        .refreshable {
            await playlistService.syncPlaylistMetadata(modelContext: modelContext)
        }
    }
    
}

struct PlaylistRowView: View {
    let playlist: Playlist
    @State private var audioPlayer = AudioPlayerService.shared
    
    private var isCurrentPlaylist: Bool {
        audioPlayer.isPlayingPlaylist(playlist.id)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: playlist.artworkURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                GradientPlaceholderView(iconSize: 24, cornerRadius: 8)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(playlist.name)
                        .font(.body)
                        .fontWeight(isCurrentPlaylist ? .semibold : .medium)
                        .lineLimit(1)
                        .foregroundStyle(isCurrentPlaylist ? Color.accentColor : .primary)
                    
                    if playlist.isSystem {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                
                Text("\(playlist.songCount) songs • \(playlist.formattedTotalDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isCurrentPlaylist {
                if audioPlayer.isPlaying {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "play.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
