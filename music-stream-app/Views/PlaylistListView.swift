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
    @State private var hasLoadedOnce = false
    @State private var isInitialLoad = true
    
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
        .task {
            if !hasLoadedOnce {
                await playlistService.syncPlaylistsToLocal(modelContext: modelContext)
                hasLoadedOnce = true
                isInitialLoad = false
            }
        }
        .alert("Error", isPresented: .constant(playlistService.error != nil)) {
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
            .onDelete(perform: deletePlaylists)
        }
        .contentMargins(.bottom, hasMiniPlayer ? 60 : 0, for: .scrollContent)
        .navigationTitle("Playlists")
        .refreshable {
            await playlistService.syncPlaylistsToLocal(modelContext: modelContext)
        }
    }
    
    private func deletePlaylists(offsets: IndexSet) {
        let playlistsToDelete = offsets.map { sortedPlaylists[$0] }
        for playlist in playlistsToDelete {
            if !playlist.isSystem {
                modelContext.delete(playlist)
            }
        }
    }
}

struct PlaylistRowView: View {
    let playlist: Playlist
    
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
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
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
        }
        .padding(.vertical, 4)
    }
}
