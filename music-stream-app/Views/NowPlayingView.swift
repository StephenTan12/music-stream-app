//
//  NowPlayingView.swift
//  music-stream-app
//

import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var audioPlayer: AudioPlayerService
    
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var showQueue = false
    @State private var seekingProgress: Double? = nil
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let artworkSize = max(100, geometry.size.width - 80)
                VStack(spacing: 0) {
                    Spacer()
                    
                    artworkView(size: artworkSize)
                    
                    Spacer()
                        .frame(height: 40)
                    
                    songInfoView
                    
                    Spacer()
                        .frame(height: 30)
                    
                    progressView
                    
                    Spacer()
                        .frame(height: 20)
                    
                    controlsView
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.3), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showQueue) {
                QueueView(audioPlayer: audioPlayer)
            }
            .alert("Playback Error", isPresented: $audioPlayer.showError) {
                Button("OK") {
                    audioPlayer.clearError()
                }
                if audioPlayer.hasNextTrack {
                    Button("Skip to Next") {
                        audioPlayer.clearError()
                        audioPlayer.playNext()
                    }
                }
            } message: {
                Text(audioPlayer.currentError?.errorDescription ?? "An unknown error occurred")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .fontWeight(.semibold)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
        ZStack {
            CachedAsyncImage(url: URL(string: audioPlayer.currentSong?.artworkURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if audioPlayer.isBuffering || audioPlayer.isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text(audioPlayer.isLoading ? "Loading..." : "Buffering...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .scaleEffect(audioPlayer.isPlaying ? 1.0 : 0.95)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: audioPlayer.isPlaying)
    }
    
    private var songInfoView: some View {
        VStack(spacing: 6) {
            Text(audioPlayer.currentSong?.title ?? "Not Playing")
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
            
            Text(audioPlayer.currentSong?.artist ?? "")
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var progressView: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let displayProgress = seekingProgress ?? (isDragging ? dragProgress : audioPlayer.progress)
                
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, geometry.size.width * displayProgress), height: 6)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 18 : 14, height: isDragging ? 18 : 14)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .offset(x: calculateThumbOffset(progress: displayProgress, width: geometry.size.width))
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = clampProgress(value.location.x / geometry.size.width)
                            dragProgress = progress
                            seekingProgress = progress
                            isDragging = true
                        }
                        .onEnded { _ in
                            let finalProgress = dragProgress
                            seekingProgress = finalProgress
                            let seekTime = finalProgress * audioPlayer.duration
                            audioPlayer.seek(to: seekTime)
                            finishSeeking()
                        }
                )
            }
            .frame(height: 30)
            
            HStack {
                Text(formatTime(displayTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                Text("-\(formatTime(audioPlayer.duration - displayTime))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
    
    private var displayTime: TimeInterval {
        if let seeking = seekingProgress {
            return seeking * audioPlayer.duration
        } else if isDragging {
            return dragProgress * audioPlayer.duration
        } else {
            return audioPlayer.currentTime
        }
    }
    
    private func clampProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
    
    private func calculateThumbOffset(progress: Double, width: CGFloat) -> CGFloat {
        let thumbSize: CGFloat = isDragging ? 18 : 14
        let halfThumb = thumbSize / 2
        let position = width * progress
        return max(0, min(position - halfThumb, width - thumbSize))
    }
    
    private func finishSeeking() {
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(50))
                let currentProgress = audioPlayer.progress
                let targetProgress = dragProgress
                if abs(currentProgress - targetProgress) < 0.02 {
                    break
                }
            }
            
            withAnimation(.easeOut(duration: 0.15)) {
                isDragging = false
                seekingProgress = nil
            }
        }
    }
    
    private var controlsView: some View {
        HStack(spacing: 40) {
            Button {
                audioPlayer.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }
            .disabled(!audioPlayer.hasPreviousTrack)
            
            Button {
                audioPlayer.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .offset(x: audioPlayer.isPlaying ? 0 : 2)
                }
            }
            
            Button {
                audioPlayer.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            .disabled(!audioPlayer.hasNextTrack)
        }
        .foregroundStyle(.primary)
    }
    
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

