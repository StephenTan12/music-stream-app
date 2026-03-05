//
//  QueueView.swift
//  music-stream-app
//

import SwiftUI

struct QueueView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var audioPlayer: AudioPlayerService
    
    var body: some View {
        NavigationStack {
            List {
                if let currentSong = audioPlayer.currentSong {
                    Section("Now Playing") {
                        SongRowView(song: currentSong, isPlaying: true, isActuallyPlaying: audioPlayer.isPlaying, showMenu: false) {
                            audioPlayer.togglePlayPause()
                        }
                    }
                }
                
                if !upNextSongs.isEmpty {
                    Section("Up Next") {
                        ForEach(Array(upNextSongs.enumerated()), id: \.element.id) { index, song in
                            SongRowView(song: song, isPlaying: false, showMenu: false) {
                                let actualIndex = audioPlayer.currentIndex + 1 + index
                                audioPlayer.playFromQueue(at: actualIndex)
                            }
                        }
                        .onDelete(perform: removeFromQueue)
                    }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if audioPlayer.currentSong == nil {
                    ContentUnavailableView(
                        "Queue Empty",
                        systemImage: "music.note.list",
                        description: Text("Start playing a song to see the queue")
                    )
                }
            }
        }
    }
    
    private var upNextSongs: [Song] {
        guard audioPlayer.currentIndex < audioPlayer.queue.count - 1 else { return [] }
        return Array(audioPlayer.queue[(audioPlayer.currentIndex + 1)...])
    }
    
    private func removeFromQueue(offsets: IndexSet) {
        for index in offsets {
            let actualIndex = audioPlayer.currentIndex + 1 + index
            audioPlayer.removeFromQueue(at: actualIndex)
        }
    }
}
