//
//  SongRowView.swift
//  music-stream-app
//

import SwiftUI

struct SongRowView: View {
    @Bindable var song: Song
    let index: Int?
    let isCurrentSong: Bool
    let isActuallyPlaying: Bool
    let showMenu: Bool
    let onTap: () -> Void
    
    @State private var downloadService = DownloadService.shared
    
    init(song: Song, index: Int? = nil, isPlaying: Bool = false, isActuallyPlaying: Bool = false, showMenu: Bool = true, onTap: @escaping () -> Void) {
        self.song = song
        self.index = index
        self.isCurrentSong = isPlaying
        self.isActuallyPlaying = isActuallyPlaying
        self.showMenu = showMenu
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let index = index {
                    Text("\(index)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                
                artworkView
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.body)
                        .fontWeight(isCurrentSong ? .semibold : .regular)
                        .foregroundStyle(isCurrentSong ? Color.accentColor : .primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        if song.isDownloaded {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(song.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if isCurrentSong {
                    if isActuallyPlaying {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "play.fill")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }
                
                Text(song.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if showMenu {
                Button {
                    AudioPlayerService.shared.addToQueue(song)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }
                
                Divider()
                
                if song.isDownloaded {
                    Button(role: .destructive) {
                        downloadService.removeSongDownload(song)
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } else if song.isDownloading {
                    Button(role: .destructive) {
                        downloadService.cancelDownload(for: song)
                    } label: {
                        Label("Cancel Download", systemImage: "xmark.circle")
                    }
                } else {
                    Button {
                        Task {
                            try? await downloadService.downloadSong(song)
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isCurrentSong ? (isActuallyPlaying ? "Currently playing" : "Paused") : "Double tap to play")
        .accessibilityAddTraits(isCurrentSong ? .isSelected : [])
    }
    
    @ViewBuilder
    private var artworkView: some View {
        if let localArtworkURL = song.localArtworkURL {
            AsyncImage(url: localArtworkURL) { image in
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
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
        } else {
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
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
        }
    }
    
    
    private var accessibilityLabel: String {
        var label = "\(song.title) by \(song.artist)"
        if let index = index {
            label = "Track \(index), " + label
        }
        label += ", \(song.formattedDuration)"
        if song.isDownloaded {
            label += ", downloaded"
        }
        return label
    }
}
