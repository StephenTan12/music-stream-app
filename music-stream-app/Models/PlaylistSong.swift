//
//  PlaylistSong.swift
//  music-stream-app
//

import Foundation
import SwiftData

@Model
final class PlaylistSong {
    var id: UUID
    var order: Int
    var addedAt: Date
    
    var playlist: Playlist?
    var song: Song?
    
    init(
        id: UUID = UUID(),
        order: Int,
        addedAt: Date = Date(),
        playlist: Playlist? = nil,
        song: Song? = nil
    ) {
        self.id = id
        self.order = order
        self.addedAt = addedAt
        self.playlist = playlist
        self.song = song
    }
}
