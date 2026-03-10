//
//  PlaylistDetailView.swift
//  music-stream-app
//

import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @Bindable var audioPlayer: AudioPlayerService
    @Environment(\.modelContext) private var modelContext
    
    @State private var playlistService = PlaylistService.shared
    @State private var selectedPlayMode: PlayMode? = nil
    @State private var showNavigationTitle = false
    @State private var downloadService = DownloadService.shared
    @State private var isDownloadingPlaylist = false
    @State private var showRemoveDownloadsConfirmation = false
    @State private var hasSyncedPlaylist = false
    
    enum PlayMode {
        case play
        case shuffle
    }
    
    private var hasMiniPlayer: Bool {
        audioPlayer.currentSong != nil
    }
    
    private var downloadedSongsCount: Int {
        playlist.songs.filter { $0.isDownloaded }.count
    }
    
    private var downloadingSongsCount: Int {
        playlist.songs.filter { $0.isDownloading }.count
    }
    
    private var allSongsDownloaded: Bool {
        !playlist.songs.isEmpty && downloadedSongsCount == playlist.songs.count
    }
    
    private var playlistDownloadProgress: Double {
        guard !playlist.songs.isEmpty else { return 0 }
        let downloadedProgress = Double(downloadedSongsCount)
        let downloadingProgress = playlist.songs.filter { $0.isDownloading }.reduce(0.0) { $0 + ($1.downloadProgress ?? 0) }
        return (downloadedProgress + downloadingProgress) / Double(playlist.songs.count)
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
            ToolbarItem(placement: .primaryAction) {
                if !playlist.songs.isEmpty {
                    playlistDownloadButton
                }
            }
        }
        .alert(
            "Remove Downloads",
            isPresented: $showRemoveDownloadsConfirmation
        ) {
            Button("Remove All Downloads", role: .destructive) {
                for song in playlist.songs {
                    downloadService.removeSongDownload(song)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Remove all downloaded songs from \"\(playlist.name)\"?")
        }
        .onChange(of: playlist.songs) { [audioPlayer] _, newSongs in
            audioPlayer.syncQueueWithPlaylist(newSongs)
        }
        .task {
            if !hasSyncedPlaylist {
                await playlistService.syncPlaylistToLocal(playlist, modelContext: modelContext)
                hasSyncedPlaylist = true
            }
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Songs", systemImage: "music.note")
        } description: {
            Text("This playlist is empty")
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
            ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
                SongRowView(
                    song: song,
                    isPlaying: isCurrentlyPlaying(song),
                    isActuallyPlaying: isCurrentlyPlaying(song) && audioPlayer.isPlaying
                ) {
                    handleSongTap(song)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                
                if index < playlist.songs.count - 1 {
                    Divider()
                        .padding(.leading, 72)
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
        audioPlayer.loadAndPlay(song: songToPlay, from: playlist.songs, playlistId: playlist.id)
    }
    
    private func isCurrentlyPlaying(_ song: Song) -> Bool {
        guard let currentSong = audioPlayer.currentSong else { return false }
        
        if let currentVideoId = currentSong.videoId, let songVideoId = song.videoId {
            return currentVideoId == songVideoId
        }
        
        return currentSong.id == song.id
    }
    
    private func handleSongTap(_ song: Song) {
        if isCurrentlyPlaying(song) {
            audioPlayer.togglePlayPause()
        } else {
            audioPlayer.loadAndPlay(song: song, from: playlist.songs, playlistId: playlist.id)
        }
    }
    
    @ViewBuilder
    private var playlistDownloadButton: some View {
        if downloadingSongsCount > 0 {
            Button {
                downloadService.cancelPlaylistDownload(playlist)
                isDownloadingPlaylist = false
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    Circle()
                        .trim(from: 0, to: playlistDownloadProgress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(-90))
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Downloading playlist, tap to cancel")
        } else if allSongsDownloaded {
            Button {
                showRemoveDownloadsConfirmation = true
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .accessibilityLabel("All songs downloaded, tap to remove downloads")
        } else {
            Button {
                isDownloadingPlaylist = true
                Task {
                    try? await downloadService.downloadPlaylist(playlist)
                    isDownloadingPlaylist = false
                }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .accessibilityLabel("Download all songs")
        }
    }
}

struct TitleOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
