//
//  AppConfig.swift
//  music-stream-app
//

import Foundation

enum AppConfig {
    enum API {
        static var baseURL: String = "http://localhost:8000"
        static let defaultPageSize = 20
        
        enum Endpoints {
            static func streamSong(videoId: String) -> String {
                return "\(baseURL)/songs/stream/\(videoId)"
            }
            
            static func getSong(videoId: String) -> String {
                return "\(baseURL)/songs/\(videoId)"
            }
            
            static func downloadSong(videoId: String) -> String {
                return "\(baseURL)/songs/\(videoId)"
            }
            
            static func deleteSong(videoId: String) -> String {
                return "\(baseURL)/songs/\(videoId)"
            }
            
            static func getSongs(page: Int, pageSize: Int) -> String {
                return "\(baseURL)/songs?page=\(page)&page_size=\(pageSize)"
            }
            
            static func getPlaylists() -> String {
                return "\(baseURL)/playlists"
            }
            
            static func getPlaylist(playlistId: Int) -> String {
                return "\(baseURL)/playlists/\(playlistId)"
            }
        }
    }
    
    enum Cache {
        static let maxImageCacheSize = 50
        static let maxArtworkCacheSize = 20
    }
    
    enum Playback {
        static let seekPollingIterations = 10
        static let seekPollingIntervalMs = 50
    }
}
