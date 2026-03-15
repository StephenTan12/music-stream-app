//
//  AppConfig.swift
//  music-stream-app
//

import Foundation
import os

enum AppConfig {
    enum API {
        private static let logger = Logger(subsystem: "com.music-stream-app", category: "AppConfig.API")
        
        static var baseURL: String {
            ServerConfigService.shared.baseURL
        }
        static let defaultPageSize = 50
        static let requestTimeoutSeconds: TimeInterval = 3
        static let resourceTimeoutSeconds: TimeInterval = 6
        static let streamingTimeoutSeconds: TimeInterval = 60
        
        private static let lock = NSLock()
        
        /// URL session configuration for streaming requests with longer timeouts
        static var urlSessionConfiguration: URLSessionConfiguration {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = streamingTimeoutSeconds
            config.timeoutIntervalForResource = streamingTimeoutSeconds * 10
            return config
        }
        private static var _authenticatedSession: URLSession?
        private static var _sessionConfigHash: String?
        
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
            configuration.timeoutIntervalForResource = resourceTimeoutSeconds
            return URLSession(configuration: configuration)
        }()
        
        private static var authenticatedURLSession: URLSession {
            lock.lock()
            defer { lock.unlock() }
            
            let currentConfigHash = ServerConfigService.shared.baseURL
            
            if let session = _authenticatedSession, _sessionConfigHash == currentConfigHash {
                return session
            }
            
            if let oldSession = _authenticatedSession {
                logger.debug("Invalidating stale authenticated session")
                oldSession.invalidateAndCancel()
            }
            
            logger.debug("Creating new authenticated session for: \(currentConfigHash)")
            let session = createAuthenticatedSession()
            _authenticatedSession = session
            _sessionConfigHash = currentConfigHash
            return session
        }
        
        private static func createAuthenticatedSession() -> URLSession {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = requestTimeoutSeconds
            configuration.timeoutIntervalForResource = resourceTimeoutSeconds
            configuration.waitsForConnectivity = true
            return URLSession(configuration: configuration, delegate: NetworkSessionDelegate.shared, delegateQueue: nil)
        }
        
        /// Invalidates the current authenticated session, forcing a new one to be created on next use.
        /// Call this after connection errors to clear stale connections.
        static func invalidateAuthenticatedSession() {
            lock.lock()
            defer { lock.unlock() }
            
            if let session = _authenticatedSession {
                logger.debug("Force invalidating authenticated session")
                session.invalidateAndCancel()
                _authenticatedSession = nil
                _sessionConfigHash = nil
            }
        }
        
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
