//
//  PlaylistService.swift
//  music-stream-app
//

import Foundation
import SwiftData
import Combine

struct PlaylistDTO: Codable {
    let id: Int
    let name: String
    let description: String?
    let isSystem: Bool
    let createdAt: String
    let updatedAt: String
    let totalSongs: Int?
    let totalDuration: Double?
}

struct PlaylistWithSongsDTO: Codable {
    let id: Int
    let name: String
    let description: String?
    let isSystem: Bool
    let createdAt: String
    let updatedAt: String
    let totalSongs: Int?
    let totalDuration: Double?
    let songs: [SongDTO]
}

enum PlaylistServiceError: LocalizedError {
    case invalidURL
    case networkError(String)
    case decodingError(String)
    case syncError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .syncError(let message):
            return "Sync error: \(message)"
        }
    }
}

@MainActor
class PlaylistService: ObservableObject {
    static let shared = PlaylistService()
    
    @Published var playlists: [PlaylistDTO] = []
    @Published var isLoading = false
    @Published var error: PlaylistServiceError?
    
    private init() {}
    
    func fetchPlaylists() async -> [PlaylistDTO]? {
        let urlString = AppConfig.API.Endpoints.getPlaylists()
        guard let url = URL(string: urlString) else {
            error = .invalidURL
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                error = .networkError("Server returned an error")
                return nil
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let playlistsResponse = try decoder.decode([PlaylistDTO].self, from: data)
            
            playlists = playlistsResponse
            return playlistsResponse
            
        } catch let decodingError as DecodingError {
            error = .decodingError(decodingError.localizedDescription)
            return nil
        } catch {
            self.error = .networkError(error.localizedDescription)
            return nil
        }
    }
    
    func fetchPlaylist(id: Int) async -> PlaylistWithSongsDTO? {
        let urlString = AppConfig.API.Endpoints.getPlaylist(playlistId: id)
        guard let url = URL(string: urlString) else {
            error = .invalidURL
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                error = .networkError("Server returned an error")
                return nil
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let playlist = try decoder.decode(PlaylistWithSongsDTO.self, from: data)
            
            return playlist
            
        } catch let decodingError as DecodingError {
            error = .decodingError(decodingError.localizedDescription)
            return nil
        } catch {
            self.error = .networkError(error.localizedDescription)
            return nil
        }
    }
    
    /// Syncs only playlist metadata (name, description, isSystem) without fetching individual playlist songs.
    /// Use this for pull-to-refresh on the playlist list view.
    func syncPlaylistMetadata(modelContext: ModelContext) async {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        guard let playlistDTOs = await fetchPlaylists() else {
            return
        }
        
        var syncedPlaylistIds: Set<Int> = []
        
        for playlistDTO in playlistDTOs {
            let backendId = playlistDTO.id
            syncedPlaylistIds.insert(backendId)
            
            let playlistFetchDescriptor = FetchDescriptor<Playlist>(
                predicate: #Predicate<Playlist> { playlist in
                    playlist.backendId == backendId
                }
            )
            
            let existingPlaylist = try? modelContext.fetch(playlistFetchDescriptor).first
            
            let dateFormatter = ISO8601DateFormatter()
            let createdAt = dateFormatter.date(from: playlistDTO.createdAt) ?? Date()
            
            if let existingPlaylist = existingPlaylist {
                existingPlaylist.name = playlistDTO.name
                existingPlaylist.playlistDescription = playlistDTO.description ?? ""
                existingPlaylist.isSystem = playlistDTO.isSystem
                existingPlaylist.totalSongs = playlistDTO.totalSongs
                existingPlaylist.totalDuration = playlistDTO.totalDuration.map { TimeInterval($0) }
                existingPlaylist.lastSyncedAt = Date()
            } else {
                let playlist = Playlist(
                    name: playlistDTO.name,
                    playlistDescription: playlistDTO.description ?? "",
                    createdAt: createdAt
                )
                playlist.backendId = playlistDTO.id
                playlist.isSystem = playlistDTO.isSystem
                playlist.totalSongs = playlistDTO.totalSongs
                playlist.totalDuration = playlistDTO.totalDuration.map { TimeInterval($0) }
                playlist.lastSyncedAt = Date()
                modelContext.insert(playlist)
            }
        }
        
        do {
            let fetchDescriptor = FetchDescriptor<Playlist>()
            let existingPlaylists = try modelContext.fetch(fetchDescriptor)
            for playlist in existingPlaylists {
                if let backendId = playlist.backendId, !syncedPlaylistIds.contains(backendId) {
                    modelContext.delete(playlist)
                }
            }
            
            try modelContext.save()
        } catch {
            self.error = .syncError("Failed to sync playlists: \(error.localizedDescription)")
        }
    }
    
    /// Syncs a single playlist's songs from the backend.
    /// Use this when navigating to a playlist detail view.
    func syncPlaylistToLocal(_ playlist: Playlist, modelContext: ModelContext) async {
        guard let backendId = playlist.backendId else { return }
        
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        guard let playlistWithSongs = await fetchPlaylist(id: backendId) else {
            return
        }
        
        playlist.name = playlistWithSongs.name
        playlist.playlistDescription = playlistWithSongs.description ?? ""
        playlist.isSystem = playlistWithSongs.isSystem
        playlist.totalSongs = playlistWithSongs.totalSongs
        playlist.totalDuration = playlistWithSongs.totalDuration.map { TimeInterval($0) }
        playlist.lastSyncedAt = Date()
        
        for playlistSong in playlist.playlistSongs {
            modelContext.delete(playlistSong)
        }
        
        var playlistSongs: [PlaylistSong] = []
        for (index, songDTO) in playlistWithSongs.songs.enumerated() {
            let videoId = songDTO.id
            let songFetchDescriptor = FetchDescriptor<Song>(
                predicate: #Predicate<Song> { song in
                    song.videoId == videoId
                }
            )
            
            let existingSong = try? modelContext.fetch(songFetchDescriptor).first
            
            let song: Song
            if let existingSong = existingSong {
                existingSong.title = songDTO.title
                existingSong.artist = songDTO.artist ?? "Unknown Artist"
                existingSong.duration = TimeInterval(songDTO.duration)
                song = existingSong
            } else {
                song = Song(
                    videoId: songDTO.id,
                    title: songDTO.title,
                    artist: songDTO.artist ?? "Unknown Artist",
                    duration: TimeInterval(songDTO.duration)
                )
                modelContext.insert(song)
            }

            let playlistSong = PlaylistSong(
                order: index,
                playlist: playlist,
                song: song
            )
            modelContext.insert(playlistSong)
            playlistSongs.append(playlistSong)
        }
        
        playlist.playlistSongs = playlistSongs
        
        do {
            try modelContext.save()
            cleanupOrphanedSongs(modelContext: modelContext)
        } catch {
            self.error = .syncError("Failed to sync playlist: \(error.localizedDescription)")
        }
    }
    
    /// Full sync that fetches all playlists and their songs.
    /// Use this for initial load or when navigating to a playlist detail view.
    func syncPlaylistsToLocal(modelContext: ModelContext) async {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        guard let playlistDTOs = await fetchPlaylists() else {
            return
        }
        
        var syncedPlaylistIds: Set<Int> = []
        
        for playlistDTO in playlistDTOs {
            guard let playlistWithSongs = await fetchPlaylist(id: playlistDTO.id) else {
                continue
            }
            
            let backendId = playlistWithSongs.id
            syncedPlaylistIds.insert(backendId)
            
            // Check if playlist with this backendId already exists
            let playlistFetchDescriptor = FetchDescriptor<Playlist>(
                predicate: #Predicate<Playlist> { playlist in
                    playlist.backendId == backendId
                }
            )
            
            let existingPlaylist = try? modelContext.fetch(playlistFetchDescriptor).first
            
            let dateFormatter = ISO8601DateFormatter()
            let createdAt = dateFormatter.date(from: playlistWithSongs.createdAt) ?? Date()
            
            let playlist: Playlist
            if let existingPlaylist = existingPlaylist {
                // Update existing playlist
                existingPlaylist.name = playlistWithSongs.name
                existingPlaylist.playlistDescription = playlistWithSongs.description ?? ""
                existingPlaylist.isSystem = playlistWithSongs.isSystem
                existingPlaylist.totalSongs = playlistWithSongs.totalSongs
                existingPlaylist.totalDuration = playlistWithSongs.totalDuration.map { TimeInterval($0) }
                existingPlaylist.lastSyncedAt = Date()
                playlist = existingPlaylist
            } else {
                // Create new playlist
                playlist = Playlist(
                    name: playlistWithSongs.name,
                    playlistDescription: playlistWithSongs.description ?? "",
                    createdAt: createdAt
                )
                playlist.backendId = playlistWithSongs.id
                playlist.isSystem = playlistWithSongs.isSystem
                playlist.totalSongs = playlistWithSongs.totalSongs
                playlist.totalDuration = playlistWithSongs.totalDuration.map { TimeInterval($0) }
                playlist.lastSyncedAt = Date()
                modelContext.insert(playlist)
            }
            
            // Clear existing playlist songs for this playlist
            for playlistSong in playlist.playlistSongs {
                modelContext.delete(playlistSong)
            }
            
            var playlistSongs: [PlaylistSong] = []
            for (index, songDTO) in playlistWithSongs.songs.enumerated() {
                // Check if song with this videoId already exists (to preserve download paths)
                let videoId = songDTO.id
                let songFetchDescriptor = FetchDescriptor<Song>(
                    predicate: #Predicate<Song> { song in
                        song.videoId == videoId
                    }
                )
                
                let existingSong = try? modelContext.fetch(songFetchDescriptor).first
                
                let song: Song
                if let existingSong = existingSong {
                    // Reuse existing song to preserve download paths
                    existingSong.title = songDTO.title
                    existingSong.artist = songDTO.artist ?? "Unknown Artist"
                    existingSong.duration = TimeInterval(songDTO.duration)
                    song = existingSong
                } else {
                    // Create new song
                    song = Song(
                        videoId: songDTO.id,
                        title: songDTO.title,
                        artist: songDTO.artist ?? "Unknown Artist",
                        duration: TimeInterval(songDTO.duration)
                    )
                    modelContext.insert(song)
                }

                let playlistSong = PlaylistSong(
                    order: index,
                    playlist: playlist,
                    song: song
                )
                modelContext.insert(playlistSong)
                playlistSongs.append(playlistSong)
            }
            
            playlist.playlistSongs = playlistSongs
        }
        
        do {
            // Remove playlists that are no longer on the backend
            let fetchDescriptor = FetchDescriptor<Playlist>()
            let existingPlaylists = try modelContext.fetch(fetchDescriptor)
            for playlist in existingPlaylists {
                if let backendId = playlist.backendId, !syncedPlaylistIds.contains(backendId) {
                    modelContext.delete(playlist)
                }
            }
            
            try modelContext.save()
            
            // Clean up orphaned songs that have no downloads
            cleanupOrphanedSongs(modelContext: modelContext)
        } catch {
            self.error = .syncError("Failed to sync playlists: \(error.localizedDescription)")
        }
    }
    
    private func cleanupOrphanedSongs(modelContext: ModelContext) {
        let songFetchDescriptor = FetchDescriptor<Song>()
        guard let allSongs = try? modelContext.fetch(songFetchDescriptor) else { return }
        
        for song in allSongs {
            // Keep songs that have downloads or are in a playlist
            let hasDownload = song.localFilePath != nil
            let isInPlaylist = (song.playlistSongs?.isEmpty == false)
            
            if !hasDownload && !isInPlaylist {
                modelContext.delete(song)
            }
        }
    }
}
