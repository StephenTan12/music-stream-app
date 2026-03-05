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
                List {
                    headerSection
                    controlsSection
                    songsSection
                }
                .listStyle(.plain)
                .contentMargins(.bottom, hasMiniPlayer ? 60 : 0, for: .scrollContent)
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            Text("Add songs to this playlist")
        } actions: {
            Button {
                showAddSong = true
            } label: {
                Label("Add Song", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var headerSection: some View {
        Section {
            VStack(spacing: 16) {
                CachedAsyncImage(url: URL(string: playlist.artworkURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 50))
                                .foregroundStyle(.white)
                        }
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                
                VStack(spacing: 4) {
                    Text(playlist.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("\(playlist.songCount) songs • \(playlist.formattedTotalDuration)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
    
    private var controlsSection: some View {
        Section {
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
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 16, trailing: 20))
        }
    }
    
    private var songsSection: some View {
        Section {
            ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
                SongRowView(
                    song: song,
                    index: index + 1,
                    isPlaying: audioPlayer.currentSong?.id == song.id,
                    isActuallyPlaying: audioPlayer.currentSong?.id == song.id && audioPlayer.isPlaying
                ) {
                    audioPlayer.loadAndPlay(song: song, from: playlist.songs)
                }
            }
            .onDelete(perform: removeSongs)
            .onMove(perform: moveSongs)
        }
    }
    
    private func playAll(shuffle: Bool) {
        guard !playlist.songs.isEmpty else { return }
        audioPlayer.playbackMode = shuffle ? .shuffle : .linear
        
        let songToPlay = shuffle ? playlist.songs.randomElement()! : playlist.songs.first!
        audioPlayer.loadAndPlay(song: songToPlay, from: playlist.songs)
    }
    
    private func removeSongs(offsets: IndexSet) {
        for index in offsets {
            playlist.songs.remove(at: index)
        }
    }
    
    private func moveSongs(from source: IndexSet, to destination: Int) {
        playlist.songs.move(fromOffsets: source, toOffset: destination)
    }
    
    private func deletePlaylist() {
        modelContext.delete(playlist)
        dismiss()
    }
}
