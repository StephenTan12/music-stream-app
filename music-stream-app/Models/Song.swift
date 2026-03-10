//
//  Song.swift
//  music-stream-app
//

import Foundation
import SwiftData

@Model
final class Song {
    var id: UUID
    var videoId: String?
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var streamURL: String
    var artworkURL: String?
    var dateAdded: Date
    
    var localFilePath: String?
    var localArtworkPath: String?
    var downloadProgress: Double?
    var isDownloading: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \PlaylistSong.song)
    var playlistSongs: [PlaylistSong]?
    
    init(
        id: UUID = UUID(),
        videoId: String? = nil,
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval = 0,
        streamURL: String,
        artworkURL: String? = nil,
        dateAdded: Date = Date(),
        localFilePath: String? = nil,
        localArtworkPath: String? = nil
    ) {
        self.id = id
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.streamURL = streamURL
        self.artworkURL = artworkURL
        self.dateAdded = dateAdded
        self.localFilePath = localFilePath
        self.localArtworkPath = localArtworkPath
    }
    
    convenience init(
        videoId: String,
        title: String,
        artist: String = "Unknown Artist",
        album: String = "",
        duration: TimeInterval = 0,
        artworkURL: String? = nil
    ) {
        self.init(
            videoId: videoId,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            streamURL: AppConfig.API.Endpoints.streamSong(videoId: videoId),
            artworkURL: artworkURL
        )
    }
}

extension Song {
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var isDownloaded: Bool {
        localFilePath != nil
    }
    
    var localFileURL: URL? {
        guard let path = localFilePath else { return nil }
        return DownloadService.cachesDirectory.appendingPathComponent(path)
    }
    
    var localArtworkURL: URL? {
        guard let path = localArtworkPath else { return nil }
        return DownloadService.cachesDirectory.appendingPathComponent(path)
    }
}
