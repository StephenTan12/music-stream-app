//
//  MiniPlayerView.swift
//  music-stream-app
//

import SwiftUI

struct MiniPlayerView: View {
    @Bindable var audioPlayer: AudioPlayerService
    @Binding var showNowPlaying: Bool
    
    var body: some View {
        if let song = audioPlayer.currentSong {
            miniPlayerContent(for: song)
        }
    }
    
    @ViewBuilder
    private func miniPlayerContent(for song: Song) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                    
                    if audioPlayer.duration > 0 && !audioPlayer.isBuffering && !audioPlayer.isLoading {
                        let safeProgress = min(max(audioPlayer.progress, 0), 1)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * safeProgress)
                    }
                }
            }
            .frame(height: 2)
            
            HStack(spacing: 12) {
                Button {
                    showNowPlaying = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            CachedAsyncImage(url: URL(string: song.artworkURL ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay {
                                        Image(systemName: "music.note")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            if audioPlayer.isBuffering || audioPlayer.isLoading {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            
                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(song.title) by \(song.artist)")
                .accessibilityHint("Tap to open Now Playing")
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
                    
                    Button {
                        audioPlayer.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                    }
                    .disabled(!audioPlayer.hasNextTrack)
                    .accessibilityLabel("Next track")
                }
                .foregroundStyle(.primary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}
