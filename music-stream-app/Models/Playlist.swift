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
    var backendId: Int?
    var isSystem: Bool
    var lastSyncedAt: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \PlaylistSong.playlist)
    var playlistSongs: [PlaylistSong]
    
    init(
        id: UUID = UUID(),
        name: String,
        playlistDescription: String = "",
        createdAt: Date = Date(),
        artworkURL: String? = nil,
        backendId: Int? = nil,
        isSystem: Bool = false,
        lastSyncedAt: Date? = nil,
        playlistSongs: [PlaylistSong] = []
    ) {
        self.id = id
        self.name = name
        self.playlistDescription = playlistDescription
        self.createdAt = createdAt
        self.artworkURL = artworkURL
        self.backendId = backendId
        self.isSystem = isSystem
        self.lastSyncedAt = lastSyncedAt
        self.playlistSongs = playlistSongs
    }
    
    var songs: [Song] {
        playlistSongs
            .sorted { $0.order < $1.order }
            .compactMap { $0.song }
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
    
    func addSong(_ song: Song, at order: Int? = nil) {
        let newOrder = order ?? playlistSongs.count
        let playlistSong = PlaylistSong(
            order: newOrder,
            playlist: self,
            song: song
        )
        playlistSongs.append(playlistSong)
    }
    
    func removeSong(at index: Int) {
        guard index < songs.count else { return }
        let songToRemove = songs[index]
        playlistSongs.removeAll { playlistSong in
            playlistSong.song?.id == songToRemove.id
        }
        reorderSongs()
    }
    
    func moveSong(from source: IndexSet, to destination: Int) {
        var orderedSongs = songs
        
        let movedItems = source.sorted().map { orderedSongs[$0] }
        
        for index in source.sorted(by: >) {
            orderedSongs.remove(at: index)
        }
        
        let adjustedDestination = destination > source.min()! ? destination - source.count : destination
        orderedSongs.insert(contentsOf: movedItems, at: adjustedDestination)
        
        for (index, song) in orderedSongs.enumerated() {
            if let playlistSong = playlistSongs.first(where: { $0.song?.id == song.id }) {
                playlistSong.order = index
            }
        }
    }
    
    private func reorderSongs() {
        for (index, playlistSong) in playlistSongs.sorted(by: { $0.order < $1.order }).enumerated() {
            playlistSong.order = index
        }
    }
}
