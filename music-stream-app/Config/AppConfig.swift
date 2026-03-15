//
//  AppConfig.swift
//  music-stream-app
//

import Foundation

enum AppConfig {
    enum API {
        static var baseURL: String {
            ServerConfigService.shared.baseURL
        }
        static let defaultPageSize = 50
        static let requestTimeoutSeconds: TimeInterval = 3.0
        
        static var urlSession: URLSession {
            if ServerConfigService.shared.serverProtocol == "https" {
                return authenticatedURLSession
            } else {
                return defaultURLSession
            }
        }
        
        private static let defaultURLSession: URLSession = {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = requestTimeoutSeconds
            configuration.timeoutIntervalForResource = requestTimeoutSeconds
            return URLSession(configuration: configuration)
        }()
        
        private static let authenticatedURLSession: URLSession = {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = requestTimeoutSeconds
            configuration.timeoutIntervalForResource = requestTimeoutSeconds
            return URLSession(configuration: configuration, delegate: NetworkSessionDelegate.shared, delegateQueue: nil)
        }()
        
        enum Endpoints {
            static func streamSong(videoId: String) -> String {
                return "\(baseURL)/songs/stream/\(videoId)"
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
    }
    
    enum Playback {
        static let seekPollingIterations = 10
        static let seekPollingIntervalMs = 50
    }
    
    enum Downloads {
        static let directory = "Downloads"
        static let artworkDirectory = "Downloads/Artwork"
    }
    
    enum Certificates {
        static let pinnedCAResource = "ca"
        static let pinnedCAExtension = "crt"
    }
}
