//
//  PlaylistDetailView.swift
//  music-stream-app
//

import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var playlist: Playlist
    @Bindable var audioPlayer: AudioPlayerService
    
    @State private var showAddSong = false
    @State private var showEditPlaylist = false
    @State private var showDeleteConfirmation = false
    @State private var selectedPlayMode: PlayMode? = nil
    @State private var showNavigationTitle = false
    
    enum PlayMode {
        case play
        case shuffle
    }
    
    private var hasMiniPlayer: Bool {
        audioPlayer.currentSong != nil
    }
    
    var body: some View {
        Group {
            if playlist.songs.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        headerSection
                        controlsSection
                        songsSection
                    }
                }
                .onPreferenceChange(TitleOffsetPreferenceKey.self) { value in
                    let threshold: CGFloat = 80
                    let shouldShow = value < threshold
                    if shouldShow != showNavigationTitle {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showNavigationTitle = shouldShow
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if hasMiniPlayer {
                        Color.clear.frame(height: 60)
                    }
                }
            }
        }
        .navigationTitle(showNavigationTitle ? playlist.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(showNavigationTitle ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if !playlist.isSystem {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showAddSong = true
                        } label: {
                            Label("Add Song", systemImage: "plus")
                        }
                        
                        Button {
                            showEditPlaylist = true
                        } label: {
                            Label("Edit Playlist", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Playlist",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deletePlaylist()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \"\(playlist.name)\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showAddSong) {
            AddSongView(playlist: playlist)
        }
        .sheet(isPresented: $showEditPlaylist) {
            EditPlaylistView(playlist: playlist)
        }
        .onChange(of: playlist.songs) { [audioPlayer] _, newSongs in
            audioPlayer.syncQueueWithPlaylist(newSongs)
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Songs", systemImage: "music.note")
        } description: {
            Text(playlist.isSystem ? "This playlist is empty" : "Add songs to this playlist")
        } actions: {
            if !playlist.isSystem {
                Button {
                    showAddSong = true
                } label: {
                    Label("Add Song", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            CachedAsyncImage(url: URL(string: playlist.artworkURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                GradientPlaceholderView()
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 4) {
                Text(playlist.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: TitleOffsetPreferenceKey.self,
                                value: geometry.frame(in: .global).minY
                            )
                        }
                    )
                
                Text("\(playlist.songCount) songs • \(playlist.formattedTotalDuration)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .padding(.top, 8)
    }
    
    private var controlsSection: some View {
        HStack(spacing: 12) {
            Button {
                selectedPlayMode = .play
                playAll(shuffle: false)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Play")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedPlayMode == .play ? Color.blue : Color.gray.opacity(0.2))
                .foregroundStyle(selectedPlayMode == .play ? .white : .primary)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            Button {
                selectedPlayMode = .shuffle
                playAll(shuffle: true)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                    Text("Shuffle")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedPlayMode == .shuffle ? Color.blue : Color.gray.opacity(0.2))
                .foregroundStyle(selectedPlayMode == .shuffle ? .white : .primary)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    private var songsSection: some View {
        LazyVStack(spacing: 0) {
            if playlist.isSystem {
                ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
                    SongRowView(
                        song: song,
                        index: index + 1,
                        isPlaying: isCurrentlyPlaying(song),
                        isActuallyPlaying: isCurrentlyPlaying(song) && audioPlayer.isPlaying
                    ) {
                        audioPlayer.loadAndPlay(song: song, from: playlist.songs)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    
                    if index < playlist.songs.count - 1 {
                        Divider()
                            .padding(.leading, 92)
                    }
                }
            } else {
                ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
                    SongRowView(
                        song: song,
                        index: index + 1,
                        isPlaying: isCurrentlyPlaying(song),
                        isActuallyPlaying: isCurrentlyPlaying(song) && audioPlayer.isPlaying
                    ) {
                        audioPlayer.loadAndPlay(song: song, from: playlist.songs)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .contextMenu {
                        Button(role: .destructive) {
                            removeSongs(offsets: IndexSet(integer: index))
                        } label: {
                            Label("Remove from Playlist", systemImage: "trash")
                        }
                    }
                    
                    if index < playlist.songs.count - 1 {
                        Divider()
                            .padding(.leading, 92)
                    }
                }
            }
        }
    }
    
    private func playAll(shuffle: Bool) {
        guard !playlist.songs.isEmpty,
              let songToPlay = shuffle ? playlist.songs.randomElement() : playlist.songs.first else {
            return
        }
        audioPlayer.playbackMode = shuffle ? .shuffle : .linear
        audioPlayer.loadAndPlay(song: songToPlay, from: playlist.songs)
    }
    
    private func removeSongs(offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            playlist.removeSong(at: index)
        }
    }
    
    private func moveSongs(from source: IndexSet, to destination: Int) {
        playlist.moveSong(from: source, to: destination)
    }
    
    private func isCurrentlyPlaying(_ song: Song) -> Bool {
        guard let currentSong = audioPlayer.currentSong else { return false }
        
        if let currentVideoId = currentSong.videoId, let songVideoId = song.videoId {
            return currentVideoId == songVideoId
        }
        
        return currentSong.id == song.id
    }
    
    private func deletePlaylist() {
        modelContext.delete(playlist)
        dismiss()
    }
}

struct TitleOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
