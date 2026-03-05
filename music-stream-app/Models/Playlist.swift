//
//  Playlist.swift
//  music-stream-app
//

import Foundation
import SwiftData

@Model
final class Playlist: Hashable {
    var id: UUID
    var name: String
    var playlistDescription: String
    var createdAt: Date
    var artworkURL: String?
    
    @Relationship(deleteRule: .nullify)
    var songs: [Song]
    
    init(
        id: UUID = UUID(),
        name: String,
        playlistDescription: String = "",
        createdAt: Date = Date(),
        artworkURL: String? = nil,
        songs: [Song] = []
    ) {
        self.id = id
        self.name = name
        self.playlistDescription = playlistDescription
        self.createdAt = createdAt
        self.artworkURL = artworkURL
        self.songs = songs
    }
}

extension Playlist {
    var songCount: Int {
        songs.count
    }
    
    var totalDuration: TimeInterval {
        songs.reduce(0) { $0 + $1.duration }
    }
    
    var formattedTotalDuration: String {
        let totalMinutes = Int(totalDuration) / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return "\(hours) hr \(minutes) min"
        }
        return "\(totalMinutes) min"
    }
}
