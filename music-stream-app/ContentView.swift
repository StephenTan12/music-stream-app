//
//  ContentView.swift
//  music-stream-app
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var audioPlayer = AudioPlayerService.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var songService = SongService.shared
    @State private var showNowPlaying = false
    @State private var isInitialLoading = true
    
    var body: some View {
        ZStack {
            NavigationStack {
                PlaylistListView()
                    .navigationDestination(for: Playlist.self) { playlist in
                        PlaylistDetailView(playlist: playlist, audioPlayer: audioPlayer)
                    }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !networkMonitor.isConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("No Internet Connection")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .foregroundStyle(.white)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayerView(audioPlayer: audioPlayer, showNowPlaying: $showNowPlaying)
            }
            .fullScreenCover(isPresented: $showNowPlaying) {
                NowPlayingView(audioPlayer: audioPlayer)
            }
            .task {
                await songService.refresh()
                withAnimation {
                    isInitialLoading = false
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active && oldPhase == .background {
                    Task {
                        await songService.refresh()
                    }
                }
            }
            .opacity(isInitialLoading ? 0 : 1)
            
            if isInitialLoading {
                LoadingView()
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Playlist.self, Song.self, PlaylistSong.self], inMemory: true)
}
