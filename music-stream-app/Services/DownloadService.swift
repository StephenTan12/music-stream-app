//
//  DownloadService.swift
//  music-stream-app
//

import Foundation
import Observation
import SwiftData
import os

private let logger = Logger(subsystem: "com.music-stream-app", category: "DownloadService")

enum DownloadError: LocalizedError {
    case invalidURL
    case downloadFailed(String)
    case fileSystemError(String)
    case noVideoId
    case noInternet
    case alreadyDownloading
    case alreadyDownloaded
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid download URL"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        case .noVideoId:
            return "Song has no video ID"
        case .noInternet:
            return "No internet connection"
        case .alreadyDownloading:
            return "Song is already downloading"
        case .alreadyDownloaded:
            return "Song is already downloaded"
        }
    }
}

@Observable
@MainActor
final class DownloadService {
    static let shared = DownloadService()
    
    // Note: Despite the name, this uses Documents directory for persistent storage
    nonisolated static var cachesDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var downloadTasks: [String: Task<Void, Error>] = [:]
    
    var activeDownloads: [String: Double] = [:]
    var totalStorageUsed: Int64 = 0
    
    private init() {
        createDownloadDirectories()
        Task {
            await refreshStorageUsage()
        }
    }
    
    private func createDownloadDirectories() {
        do {
            try Self.createDownloadDirectoriesIfNeeded()
        } catch {
            logger.error("Failed to create download directories: \(error.localizedDescription)")
        }
    }
    
    private func audioDestinationURL(for videoId: String) -> URL {
        Self.cachesDirectory.appendingPathComponent("\(AppConfig.Downloads.directory)/\(videoId).mp4")
    }
    
    private func artworkDestinationURL(for videoId: String) -> URL {
        Self.cachesDirectory.appendingPathComponent("\(AppConfig.Downloads.artworkDirectory)/\(videoId).jpg")
    }
    
    func downloadSong(_ song: Song) async throws {
        guard NetworkMonitor.shared.isConnected else {
            throw DownloadError.noInternet
        }

        guard let videoId = song.videoId else {
            throw DownloadError.noVideoId
        }
        
        if song.isDownloaded {
            throw DownloadError.alreadyDownloaded
        }
        
        if song.isDownloading || activeDownloads[videoId] != nil {
            throw DownloadError.alreadyDownloading
        }
        
        song.isDownloading = true
        song.downloadProgress = 0
        activeDownloads[videoId] = 0
        
        let task = Task<Void, Error> {
            do {
                try await downloadAudioFile(for: song, videoId: videoId)
                try await downloadArtwork(for: song, videoId: videoId)
                
                await MainActor.run {
                    song.isDownloading = false
                    song.downloadProgress = nil
                    activeDownloads.removeValue(forKey: videoId)
                    downloadTasks.removeValue(forKey: videoId)
                }
                await refreshStorageUsage()
                
                logger.info("Successfully downloaded song: \(song.title)")
            } catch {
                try? await Self.removeItemsIfPresent(at: [
                    audioDestinationURL(for: videoId),
                    artworkDestinationURL(for: videoId)
                ])
                
                await MainActor.run {
                    song.isDownloading = false
                    song.downloadProgress = nil
                    song.localFilePath = nil
                    song.localArtworkPath = nil
                    activeDownloads.removeValue(forKey: videoId)
                    downloadTasks.removeValue(forKey: videoId)
                }
                await refreshStorageUsage()
                throw error
            }
        }
        
        downloadTasks[videoId] = task
        try await task.value
    }
    
    private func downloadAudioFile(for song: Song, videoId: String) async throws {
        guard let url = URL(string: song.streamURL) else {
            throw DownloadError.invalidURL
        }
        
        let relativePath = "\(AppConfig.Downloads.directory)/\(videoId).mp4"
        let destinationURL = audioDestinationURL(for: videoId)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            song.localFilePath = relativePath
            logger.info("Audio file already exists for \(song.title), skipping download")
            return
        }
        
        let (tempURL, response) = try await AppConfig.API.urlSession.download(from: url, delegate: DownloadProgressDelegate { [weak self] progress in
            Task { @MainActor in
                self?.activeDownloads[videoId] = progress * 0.9
                song.downloadProgress = progress * 0.9
            }
        })
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.downloadFailed("Invalid server response")
        }
        
        do {
            try await Self.moveDownloadedItem(from: tempURL, to: destinationURL)
            song.localFilePath = relativePath
        } catch {
            throw DownloadError.fileSystemError(error.localizedDescription)
        }
    }
    
    private func downloadArtwork(for song: Song, videoId: String) async throws {
        guard let artworkURLString = song.artworkURL,
              let artworkURL = URL(string: artworkURLString) else {
            await MainActor.run {
                activeDownloads[videoId] = 1.0
                song.downloadProgress = 1.0
            }
            return
        }

        guard NetworkMonitor.shared.isConnected else {
            await MainActor.run {
                activeDownloads[videoId] = 1.0
                song.downloadProgress = 1.0
            }
            return
        }
        
        let relativePath = "\(AppConfig.Downloads.artworkDirectory)/\(videoId).jpg"
        let destinationURL = artworkDestinationURL(for: videoId)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            song.localArtworkPath = relativePath
            activeDownloads[videoId] = 1.0
            song.downloadProgress = 1.0
            return
        }
        
        do {
            let (data, response) = try await AppConfig.API.urlSession.data(from: artworkURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                await MainActor.run {
                    activeDownloads[videoId] = 1.0
                    song.downloadProgress = 1.0
                }
                return
            }
            
            try await Self.writeDownloadedData(data, to: destinationURL)
            song.localArtworkPath = relativePath
            activeDownloads[videoId] = 1.0
            song.downloadProgress = 1.0
        } catch {
            logger.warning("Failed to download artwork for \(song.title): \(error.localizedDescription)")
            activeDownloads[videoId] = 1.0
            song.downloadProgress = 1.0
        }
    }
    
    func downloadPlaylist(_ playlist: Playlist) async throws {
        let songs = playlist.songs.filter { !$0.isDownloaded && !$0.isDownloading }
        
        for song in songs {
            do {
                try await downloadSong(song)
            } catch DownloadError.alreadyDownloaded, DownloadError.alreadyDownloading {
                continue
            } catch {
                logger.error("Failed to download song \(song.title) in playlist: \(error.localizedDescription)")
            }
        }
    }
    
    func cancelDownload(for song: Song) {
        guard let videoId = song.videoId else { return }
        
        downloadTasks[videoId]?.cancel()
        downloadTasks.removeValue(forKey: videoId)
        activeDownloads.removeValue(forKey: videoId)
        
        let urlsToRemove = [song.localFilePath, song.localArtworkPath]
            .compactMap { $0 }
            .map { Self.cachesDirectory.appendingPathComponent($0) }
        
        song.isDownloading = false
        song.downloadProgress = nil
        song.localFilePath = nil
        song.localArtworkPath = nil
        
        Task {
            try? await Self.removeItemsIfPresent(at: urlsToRemove)
            await refreshStorageUsage()
        }
    }
    
    func cancelPlaylistDownload(_ playlist: Playlist) {
        for song in playlist.songs {
            if song.isDownloading {
                cancelDownload(for: song)
            }
        }
    }
    
    func removeSongDownload(_ song: Song) {
        let urlsToRemove = [song.localFilePath, song.localArtworkPath]
            .compactMap { $0 }
            .map { Self.cachesDirectory.appendingPathComponent($0) }
        
        song.localFilePath = nil
        song.localArtworkPath = nil
        song.isDownloading = false
        song.downloadProgress = nil
        
        Task {
            try? await Self.removeItemsIfPresent(at: urlsToRemove)
            await refreshStorageUsage()
        }
    }
    
    func removeAllDownloads(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Song>()
        if let songs = try? modelContext.fetch(descriptor) {
            for song in songs {
                song.localFilePath = nil
                song.localArtworkPath = nil
                song.isDownloading = false
                song.downloadProgress = nil
            }
        }
        
        activeDownloads.removeAll()
        downloadTasks.values.forEach { $0.cancel() }
        downloadTasks.removeAll()
        totalStorageUsed = 0
        
        Task {
            try? await Self.resetDownloadDirectories()
            await refreshStorageUsage()
        }
    }
    
    func formattedStorageUsed() -> String {
        let bytes = Double(totalStorageUsed)
        
        if bytes < 1024 {
            return "\(Int(bytes)) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", bytes / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", bytes / (1024 * 1024))
        } else {
            return String(format: "%.2f GB", bytes / (1024 * 1024 * 1024))
        }
    }
    
    func cleanupStalePaths(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Song>()
        guard let songs = try? modelContext.fetch(descriptor) else { return }
        let downloadedSongs = songs.compactMap { song -> (UUID, String, String?)? in
            guard let localFilePath = song.localFilePath else { return nil }
            return (song.id, localFilePath, song.localArtworkPath)
        }
        
        Task {
            let staleSongIDs = await Self.findStaleDownloadIDs(in: downloadedSongs)
            for song in songs where staleSongIDs.contains(song.id) {
                song.localFilePath = nil
                song.localArtworkPath = nil
            }
            await refreshStorageUsage()
        }
    }
    
    private func refreshStorageUsage() async {
        totalStorageUsed = await Self.computeTotalStorageUsed()
    }
    
    private nonisolated static func computeTotalStorageUsed() async -> Int64 {
        let downloadDirectory = "Downloads"
        let artworkDirectory = "Downloads/Artwork"
        async let downloadsSize = directorySize(at: cachesDirectory.appendingPathComponent(downloadDirectory))
        async let artworkSize = directorySize(at: cachesDirectory.appendingPathComponent(artworkDirectory))
        return await downloadsSize + artworkSize
    }
    
    private nonisolated static func directorySize(at url: URL) async -> Int64 {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            var totalSize: Int64 = 0
            
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return 0
            }
            
            while let fileURL = enumerator.nextObject() as? URL {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
            
            return totalSize
        }.value
    }
    
    private nonisolated static func createDownloadDirectoriesIfNeeded() throws {
        let downloadDirectory = "Downloads"
        let artworkDirectory = "Downloads/Artwork"
        let downloadsURL = cachesDirectory.appendingPathComponent(downloadDirectory)
        let artworkURL = cachesDirectory.appendingPathComponent(artworkDirectory)
        
        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: artworkURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    private nonisolated static func moveDownloadedItem(from sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }.value
    }
    
    private nonisolated static func writeDownloadedData(_ data: Data, to destinationURL: URL) async throws {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: destinationURL, options: .atomic)
        }.value
    }
    
    private nonisolated static func removeItemsIfPresent(at urls: [URL]) async throws {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            for url in urls where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }.value
    }
    
    private nonisolated static func resetDownloadDirectories() async throws {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let downloadDirectory = "Downloads"
            let artworkDirectory = "Downloads/Artwork"
            let downloadsURL = cachesDirectory.appendingPathComponent(downloadDirectory)
            let artworkURL = cachesDirectory.appendingPathComponent(artworkDirectory)
            
            if fileManager.fileExists(atPath: downloadsURL.path) {
                try fileManager.removeItem(at: downloadsURL)
            }
            if fileManager.fileExists(atPath: artworkURL.path) {
                try fileManager.removeItem(at: artworkURL)
            }
            
            try createDownloadDirectoriesIfNeeded()
        }.value
    }
    
    private nonisolated static func findStaleDownloadIDs(
        in downloadedSongs: [(id: UUID, localFilePath: String, localArtworkPath: String?)]
    ) async -> Set<UUID> {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            return Set(downloadedSongs.compactMap { song in
                let audioURL = cachesDirectory.appendingPathComponent(song.localFilePath)
                guard fileManager.fileExists(atPath: audioURL.path) else {
                    return song.id
                }
                return nil
            })
        }.value
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let progressHandler: (Double) -> Void
    private weak var observedTask: URLSessionTask?
    
    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
        super.init()
    }
    
    deinit {
        observedTask?.removeObserver(self, forKeyPath: "countOfBytesReceived")
    }
    
    func urlSession(
        _ session: URLSession,
        didCreateTask task: URLSessionTask
    ) {
        observedTask = task
        task.addObserver(self, forKeyPath: "countOfBytesReceived", options: .new, context: nil)
    }
    
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "countOfBytesReceived", let task = object as? URLSessionTask {
            let received = task.countOfBytesReceived
            let expected = task.countOfBytesExpectedToReceive
            if expected > 0 {
                let progress = Double(received) / Double(expected)
                progressHandler(progress)
            }
        }
    }
}
