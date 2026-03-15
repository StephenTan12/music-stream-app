//
//  PlaylistService.swift
//  music-stream-app
//

import Foundation
import SwiftData
import Observation
import os

private let timeoutErrorCode = -1001

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

@Observable
@MainActor
final class PlaylistService {
    static let shared = PlaylistService()
    
    private let logger = Logger(subsystem: "com.music-stream-app", category: "PlaylistService")
    
    var playlists: [PlaylistDTO] = []
    var isLoading = false
    var error: PlaylistServiceError?
    
    private init() {}
    
    func fetchPlaylists() async -> [PlaylistDTO]? {
        guard NetworkMonitor.shared.isConnected else {
            return nil
        }

        let urlString = AppConfig.API.Endpoints.getPlaylists()
        guard let url = URL(string: urlString) else {
            error = .invalidURL
            return nil
        }
        
        do {
            let (data, response) = try await performRequestWithRetry(url: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                NetworkMonitor.shared.isServerReachable = false
                return nil
            }
            
            NetworkMonitor.shared.isServerReachable = true
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let playlistsResponse = try decoder.decode([PlaylistDTO].self, from: data)
            
            playlists = playlistsResponse
            return playlistsResponse
            
        } catch let decodingError as DecodingError {
            error = .decodingError(decodingError.localizedDescription)
            return nil
        } catch {
            NetworkMonitor.shared.isServerReachable = false
            return nil
        }
    }
    
    func fetchPlaylist(id: Int) async -> PlaylistWithSongsDTO? {
        guard NetworkMonitor.shared.isConnected else {
            return nil
        }

        let urlString = AppConfig.API.Endpoints.getPlaylist(playlistId: id)
        guard let url = URL(string: urlString) else {
            error = .invalidURL
            return nil
        }
        
        do {
            let (data, response) = try await performRequestWithRetry(url: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                NetworkMonitor.shared.isServerReachable = false
                return nil
            }
            
            NetworkMonitor.shared.isServerReachable = true
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let playlist = try decoder.decode(PlaylistWithSongsDTO.self, from: data)
            
            return playlist
            
        } catch let decodingError as DecodingError {
            error = .decodingError(decodingError.localizedDescription)
            return nil
        } catch {
            NetworkMonitor.shared.isServerReachable = false
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
        
        // Batch fetch all existing songs with videoIds to avoid N individual fetches
        let songFetchDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { song in
                song.videoId != nil
            }
        )
        let existingSongs = (try? modelContext.fetch(songFetchDescriptor)) ?? []
        let existingSongsByVideoId = Dictionary(
            uniqueKeysWithValues: existingSongs.compactMap { song -> (String, Song)? in
                guard let videoId = song.videoId else { return nil }
                return (videoId, song)
            }
        )
        
        var playlistSongs: [PlaylistSong] = []
        for (index, songDTO) in playlistWithSongs.songs.enumerated() {
            let videoId = songDTO.id
            
            let song: Song
            if let existingSong = existingSongsByVideoId[videoId] {
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
        
        // Batch fetch all existing songs with videoIds once before processing playlists
        let songFetchDescriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { song in
                song.videoId != nil
            }
        )
        let existingSongs = (try? modelContext.fetch(songFetchDescriptor)) ?? []
        var existingSongsByVideoId = Dictionary(
            uniqueKeysWithValues: existingSongs.compactMap { song -> (String, Song)? in
                guard let videoId = song.videoId else { return nil }
                return (videoId, song)
            }
        )
        
        for playlistDTO in playlistDTOs {
            guard let playlistWithSongs = await fetchPlaylist(id: playlistDTO.id) else {
                continue
            }
            
            let backendId = playlistWithSongs.id
            syncedPlaylistIds.insert(backendId)
            
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
                existingPlaylist.name = playlistWithSongs.name
                existingPlaylist.playlistDescription = playlistWithSongs.description ?? ""
                existingPlaylist.isSystem = playlistWithSongs.isSystem
                existingPlaylist.totalSongs = playlistWithSongs.totalSongs
                existingPlaylist.totalDuration = playlistWithSongs.totalDuration.map { TimeInterval($0) }
                existingPlaylist.lastSyncedAt = Date()
                playlist = existingPlaylist
            } else {
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
            
            for playlistSong in playlist.playlistSongs {
                modelContext.delete(playlistSong)
            }
            
            var playlistSongs: [PlaylistSong] = []
            for (index, songDTO) in playlistWithSongs.songs.enumerated() {
                let videoId = songDTO.id
                
                let song: Song
                if let existingSong = existingSongsByVideoId[videoId] {
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
                    existingSongsByVideoId[videoId] = song
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
    
    private func performRequestWithRetry(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await AppConfig.API.urlSession.data(from: url)
        } catch let nsError as NSError where nsError.code == timeoutErrorCode {
            logger.warning("Request timed out, invalidating session and retrying: \(url.absoluteString)")
            AppConfig.API.invalidateAuthenticatedSession()
            return try await AppConfig.API.urlSession.data(from: url)
        }
    }
}
