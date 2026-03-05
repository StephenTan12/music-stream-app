//
//  AudioPlayerService.swift
//  music-stream-app
//

import Foundation
import AVFoundation
import MediaPlayer
import Observation
import Combine
import UIKit

// MARK: - API Configuration

enum APIConfig {
    static var baseURL: String = "http://localhost:8000"
    
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
    }
}

enum PlaybackMode: String, CaseIterable {
    case linear = "Linear"
    case shuffle = "Shuffle"
    
    var icon: String {
        switch self {
        case .linear: return "arrow.right"
        case .shuffle: return "shuffle"
        }
    }
}

enum RepeatMode: String, CaseIterable {
    case none = "Off"
    case all = "All"
    case one = "One"
    
    var icon: String {
        switch self {
        case .none: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

enum PlaybackError: LocalizedError, Equatable {
    case invalidURL
    case networkError(String)
    case playbackFailed(String)
    case noInternet
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid stream URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .playbackFailed(let message):
            return "Playback failed: \(message)"
        case .noInternet:
            return "No internet connection"
        }
    }
}

@Observable
@MainActor
final class AudioPlayerService {
    static let shared = AudioPlayerService()
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var interruptionCancellable: AnyCancellable?
    private var itemObservers: [NSObjectProtocol] = []
    private var artworkCache: [String: UIImage] = [:]
    private var artworkAccessOrder: [String] = []
    private let maxArtworkCacheSize = 20
    
    // Playback state
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isBuffering: Bool = false
    var isLoading: Bool = false
    
    // Error state
    var currentError: PlaybackError?
    var showError: Bool = false
    
    // Queue management - store song IDs for thread safety
    var currentSong: Song?
    var queue: [Song] = []
    var originalQueue: [Song] = []
    var currentIndex: Int = 0
    
    // Playback modes
    var playbackMode: PlaybackMode = .linear {
        didSet {
            if playbackMode == .shuffle {
                shuffleQueue()
            } else {
                restoreOriginalQueue()
            }
        }
    }
    var repeatMode: RepeatMode = .none
    
    private init() {
        setupAudioSession()
        setupRemoteTransportControls()
        setupInterruptionHandling()
    }
    
    func clearError() {
        currentError = nil
        showError = false
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Remote Control Setup
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playNext()
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playPrevious()
            }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.seek(to: event.positionTime)
            }
            return .success
        }
    }
    
    private func setupInterruptionHandling() {
        interruptionCancellable = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.handleInterruption(notification)
                }
            }
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                play()
            }
        @unknown default:
            break
        }
    }
    
    // MARK: - Playback Controls
    
    func loadAndPlay(song: Song, from playlist: [Song]? = nil) {
        if let playlist = playlist {
            originalQueue = playlist
            if playbackMode == .shuffle {
                shuffleQueue()
            } else {
                queue = playlist
            }
            currentIndex = queue.firstIndex(where: { $0.id == song.id }) ?? 0
        }
        
        loadSong(song)
        play()
    }
    
    private func loadSong(_ song: Song) {
        cleanup()
        clearError()
        
        currentSong = song
        isLoading = true
        isBuffering = true
        
        if !NetworkMonitor.shared.isConnected {
            setError(.noInternet)
            isLoading = false
            isBuffering = false
            return
        }
        
        guard let url = URL(string: song.streamURL) else {
            setError(.invalidURL)
            isLoading = false
            isBuffering = false
            return
        }
        
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        setupTimeObserver()
        observePlayerItem()
        updateNowPlayingInfo()
        fetchArtworkForNowPlaying(song: song)
    }
    
    private func setError(_ error: PlaybackError) {
        currentError = error
        showError = true
        isPlaying = false
    }
    
    private func fetchArtworkForNowPlaying(song: Song) {
        guard let artworkURLString = song.artworkURL,
              let artworkURL = URL(string: artworkURLString) else { return }
        
        if let cached = artworkCache[artworkURLString] {
            touchArtworkAccess(artworkURLString)
            updateNowPlayingArtwork(cached)
            return
        }
        
        Task.detached { [weak self, artworkURLString] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.evictAndCacheArtwork(image, for: artworkURLString)
                        self.updateNowPlayingArtwork(image)
                    }
                }
            } catch {
                // Artwork fetch failed silently - not critical
            }
        }
    }
    
    private func touchArtworkAccess(_ key: String) {
        artworkAccessOrder.removeAll { $0 == key }
        artworkAccessOrder.append(key)
    }
    
    private func evictAndCacheArtwork(_ image: UIImage, for key: String) {
        if artworkCache.count >= maxArtworkCacheSize, let oldest = artworkAccessOrder.first {
            artworkCache.removeValue(forKey: oldest)
            artworkAccessOrder.removeFirst()
        }
        artworkCache[key] = image
        touchArtworkAccess(key)
    }
    
    private func updateNowPlayingArtwork(_ image: UIImage) {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            Task { @MainActor in
                self.currentTime = seconds
                if let duration = self.player?.currentItem?.duration.seconds, duration.isFinite {
                    self.duration = duration
                }
                self.updateNowPlayingInfo()
            }
        }
    }
    
    private func observePlayerItem() {
        guard let playerItem = playerItem else { return }
        
        let endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handlePlaybackEnded()
            }
        }
        itemObservers.append(endObserver)
        
        let failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let errorMessage = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "Unknown error"
            Task { @MainActor in
                self.setError(.playbackFailed(errorMessage))
            }
        }
        itemObservers.append(failObserver)
        
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    self.isBuffering = false
                    self.isLoading = false
                    if let duration = self.playerItem?.duration.seconds, duration.isFinite {
                        self.duration = duration
                    }
                case .failed:
                    self.isLoading = false
                    self.isBuffering = false
                    let errorMessage = self.playerItem?.error?.localizedDescription ?? "Unknown error"
                    self.setError(.playbackFailed(errorMessage))
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                guard let self = self else { return }
                if !self.isLoading {
                    self.isBuffering = isEmpty
                }
            }
            .store(in: &cancellables)
        
        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLikelyToKeepUp in
                guard let self = self else { return }
                if isLikelyToKeepUp {
                    self.isBuffering = false
                }
            }
            .store(in: &cancellables)
    }
    
    func play() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }
    
    func playNext() {
        guard !queue.isEmpty else { return }
        
        if currentIndex < queue.count - 1 {
            currentIndex += 1
            loadSong(queue[currentIndex])
            play()
        } else if repeatMode == .all {
            currentIndex = 0
            loadSong(queue[currentIndex])
            play()
        }
    }
    
    func playPrevious() {
        guard !queue.isEmpty else { return }
        
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        
        if currentIndex > 0 {
            currentIndex -= 1
            loadSong(queue[currentIndex])
            play()
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
            loadSong(queue[currentIndex])
            play()
        }
    }
    
    private func handlePlaybackEnded() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            play()
        case .all:
            playNext()
        case .none:
            if currentIndex < queue.count - 1 {
                playNext()
            } else {
                isPlaying = false
            }
        }
    }
    
    // MARK: - Queue Management
    
    private func shuffleQueue() {
        guard !originalQueue.isEmpty else {
            queue = []
            currentIndex = 0
            return
        }
        
        guard let current = currentSong else {
            queue = originalQueue.shuffled()
            currentIndex = 0
            return
        }
        
        var shuffled = originalQueue.filter { $0.id != current.id }.shuffled()
        shuffled.insert(current, at: 0)
        queue = shuffled
        currentIndex = 0
    }
    
    private func restoreOriginalQueue() {
        guard !originalQueue.isEmpty else {
            queue = []
            currentIndex = 0
            return
        }
        
        guard let current = currentSong else {
            queue = originalQueue
            currentIndex = 0
            return
        }
        
        queue = originalQueue
        currentIndex = queue.firstIndex(where: { $0.id == current.id }) ?? 0
    }
    
    func addToQueue(_ song: Song) {
        queue.append(song)
        if !originalQueue.contains(where: { $0.id == song.id }) {
            originalQueue.append(song)
        }
    }
    
    func playFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        currentIndex = index
        loadSong(queue[index])
        play()
    }
    
    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count, index != currentIndex else { return }
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        }
    }
    
    func syncQueueWithPlaylist(_ playlist: [Song]) {
        let currentSongId = currentSong?.id
        
        queue = queue.filter { song in
            playlist.contains(where: { $0.id == song.id })
        }
        originalQueue = originalQueue.filter { song in
            playlist.contains(where: { $0.id == song.id })
        }
        
        if let id = currentSongId {
            if let newIndex = queue.firstIndex(where: { $0.id == id }) {
                currentIndex = newIndex
            } else {
                currentSong = nil
                currentIndex = 0
                cleanup()
            }
        }
    }
    
    // MARK: - Now Playing Info
    
    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = song.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = song.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = song.album
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        for observer in itemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        itemObservers.removeAll()
        
        cancellables.removeAll()
        
        player?.pause()
        player = nil
        playerItem = nil
        currentTime = 0
        duration = 0
        isLoading = false
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var hasNextTrack: Bool {
        guard !queue.isEmpty else { return false }
        return currentIndex < queue.count - 1 || repeatMode == .all
    }
    
    var hasPreviousTrack: Bool {
        guard !queue.isEmpty else { return false }
        return currentIndex > 0 || repeatMode == .all || currentTime > 3
    }
}
