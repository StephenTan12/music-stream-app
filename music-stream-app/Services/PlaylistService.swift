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
}

struct PlaylistWithSongsDTO: Codable {
    let id: Int
    let name: String
    let description: String?
    let isSystem: Bool
    let createdAt: String
    let updatedAt: String
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
    
    func syncPlaylistsToLocal(modelContext: ModelContext) async {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        guard let playlistDTOs = await fetchPlaylists() else {
            return
        }
        
        var newPlaylists: [Playlist] = []
        
        for playlistDTO in playlistDTOs {
            guard let playlistWithSongs = await fetchPlaylist(id: playlistDTO.id) else {
                continue
            }
            
            let dateFormatter = ISO8601DateFormatter()
            let createdAt = dateFormatter.date(from: playlistWithSongs.createdAt) ?? Date()
            
            let playlist = Playlist(
                name: playlistWithSongs.name,
                playlistDescription: playlistWithSongs.description ?? "",
                createdAt: createdAt
            )
            playlist.backendId = playlistWithSongs.id
            playlist.isSystem = playlistWithSongs.isSystem
            playlist.lastSyncedAt = Date()
            
            var playlistSongs: [PlaylistSong] = []
            for (index, songDTO) in playlistWithSongs.songs.enumerated() {
                let song = Song(
                    videoId: songDTO.id,
                    title: songDTO.title,
                    artist: songDTO.artist ?? "Unknown Artist",
                    duration: TimeInterval(songDTO.duration)
                )
                
                let playlistSong = PlaylistSong(
                    order: index,
                    playlist: playlist,
                    song: song
                )
                
                playlistSongs.append(playlistSong)
            }
            
            playlist.playlistSongs = playlistSongs
            
            newPlaylists.append(playlist)
        }
        
        do {
            let fetchDescriptor = FetchDescriptor<Playlist>()
            let existingPlaylists = try modelContext.fetch(fetchDescriptor)
            for playlist in existingPlaylists {
                modelContext.delete(playlist)
            }
            
            for playlist in newPlaylists {
                modelContext.insert(playlist)
            }
            
            try modelContext.save()
        } catch {
            self.error = .syncError("Failed to sync playlists: \(error.localizedDescription)")
        }
    }
}
