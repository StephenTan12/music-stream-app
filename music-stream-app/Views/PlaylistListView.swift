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
    
    private var hasMiniPlayer: Bool {
        audioPlayer.currentSong != nil
    }
    
    var body: some View {
        Group {
            if playlists.isEmpty {
                AllSongsView(audioPlayer: audioPlayer)
            } else {
                playlistsView
            }
        }
    }
    
    private var playlistsView: some View {
        List {
            ForEach(playlists) { playlist in
                NavigationLink(value: playlist) {
                    PlaylistRowView(playlist: playlist)
                }
            }
            .onDelete(perform: deletePlaylists)
        }
        .contentMargins(.bottom, hasMiniPlayer ? 60 : 0, for: .scrollContent)
        .navigationTitle("Playlists")
    }
    
    private func deletePlaylists(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(playlists[index])
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("\(playlist.songCount) songs • \(playlist.formattedTotalDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
