//
//  ContentView.swift
//  music-stream-app
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var audioPlayer = AudioPlayerService.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var songService = SongService.shared
    @State private var showNowPlaying = false
    
    var body: some View {
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
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && oldPhase == .background {
                Task {
                    await songService.refresh()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Playlist.self, Song.self], inMemory: true)
}
