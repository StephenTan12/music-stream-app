//
//  SongRowView.swift
//  music-stream-app
//

import SwiftUI

struct SongRowView: View {
    let song: Song
    let index: Int?
    let isCurrentSong: Bool
    let isActuallyPlaying: Bool
    let showMenu: Bool
    let onTap: () -> Void
    
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
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.body)
                        .fontWeight(isCurrentSong ? .semibold : .regular)
                        .foregroundStyle(isCurrentSong ? Color.accentColor : .primary)
                        .lineLimit(1)
                    
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                
                if showMenu {
                    Menu {
                        Button {
                            AudioPlayerService.shared.addToQueue(song)
                        } label: {
                            Label("Add to Queue", systemImage: "text.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("More options for \(song.title)")
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isCurrentSong ? (isActuallyPlaying ? "Currently playing" : "Paused") : "Double tap to play")
        .accessibilityAddTraits(isCurrentSong ? .isSelected : [])
    }
    
    private var accessibilityLabel: String {
        var label = "\(song.title) by \(song.artist)"
        if let index = index {
            label = "Track \(index), " + label
        }
        label += ", \(song.formattedDuration)"
        return label
    }
}
