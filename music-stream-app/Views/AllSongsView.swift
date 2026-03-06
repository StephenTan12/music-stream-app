//
//  AllSongsView.swift
//  music-stream-app
//

import SwiftUI

struct AllSongsView: View {
    @StateObject private var songService = SongService.shared
    @Bindable var audioPlayer: AudioPlayerService
    
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
            if songService.songs.isEmpty && !songService.isLoading {
                emptyStateView
            } else {
                songsList
            }
        }
        .navigationTitle("Songs")
        .task {
            if songService.songs.isEmpty {
                await songService.fetchSongs(page: 1, reset: true)
            }
        }
        .refreshable {
            await songService.refresh()
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Songs", systemImage: "music.note")
        } description: {
            if let error = songService.error {
                Text(error.localizedDescription)
            } else {
                Text("No songs available from the server")
            }
        } actions: {
            Button {
                Task {
                    await songService.refresh()
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var songsList: some View {
        List {
            headerSection
            controlsSection
            songsSection
            
            if songService.currentPage < songService.totalPages {
                loadMoreSection
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, hasMiniPlayer ? 60 : 0, for: .scrollContent)
    }
    
    private var headerSection: some View {
        Section {
            VStack(spacing: 16) {
                GradientPlaceholderView()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                
                VStack(spacing: 4) {
                    Text("All Songs")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("\(songService.songs.count) songs")
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
                .disabled(songService.songs.isEmpty)
                
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
                .disabled(songService.songs.isEmpty)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 16, trailing: 20))
        }
    }
    
    private var songsSection: some View {
        Section {
            ForEach(Array(songService.songs.enumerated()), id: \.element.id) { index, song in
                SongRowView(
                    song: song,
                    index: index + 1,
                    isPlaying: audioPlayer.currentSong?.videoId == song.videoId,
                    isActuallyPlaying: audioPlayer.currentSong?.videoId == song.videoId && audioPlayer.isPlaying
                ) {
                    if audioPlayer.currentSong?.videoId == song.videoId {
                        audioPlayer.togglePlayPause()
                    } else {
                        audioPlayer.loadAndPlay(song: song, from: songService.songs)
                    }
                }
            }
        }
    }
    
    private var loadMoreSection: some View {
        Section {
            HStack {
                Spacer()
                if songService.isLoading {
                    ProgressView()
                        .padding()
                } else {
                    Button("Load More") {
                        Task {
                            await songService.loadNextPage()
                        }
                    }
                    .padding()
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .onAppear {
                Task {
                    await songService.loadNextPage()
                }
            }
        }
    }
    
    private func playAll(shuffle: Bool) {
        guard !songService.songs.isEmpty,
              let songToPlay = shuffle ? songService.songs.randomElement() : songService.songs.first else {
            return
        }
        audioPlayer.playbackMode = shuffle ? .shuffle : .linear
        audioPlayer.loadAndPlay(song: songToPlay, from: songService.songs)
    }
}
