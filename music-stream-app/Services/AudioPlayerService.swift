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
import os

private let logger = Logger(subsystem: "com.music-stream-app", category: "AudioPlayer")

// MARK: - API Configuration (uses AppConfig)

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

// MARK: - Persisted Playback State

struct PersistedSong: Codable {
    let id: String
    let videoId: String?
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkURL: String?
    let localFilePath: String?
    let localArtworkPath: String?
    
    init(from song: Song) {
        self.id = song.id.uuidString
        self.videoId = song.videoId
        self.title = song.title
        self.artist = song.artist
        self.album = song.album
        self.duration = song.duration
        self.artworkURL = song.artworkURL
        self.localFilePath = song.localFilePath
        self.localArtworkPath = song.localArtworkPath
    }
    
    func toSong() -> Song {
        Song(
            id: UUID(uuidString: id) ?? UUID(),
            videoId: videoId,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkURL: artworkURL,
            localFilePath: localFilePath,
            localArtworkPath: localArtworkPath
        )
    }
}

struct PersistedPlaybackState: Codable {
    let currentSong: PersistedSong?
    let queue: [PersistedSong]
    let originalQueue: [PersistedSong]
    let currentIndex: Int
    let currentTime: TimeInterval
    let playbackMode: String
    let repeatMode: String
    let currentPlaylistId: String?
}

// MARK: - Streaming Data Delegate for mTLS

private final class StreamingDataDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private let dataRequest: AVAssetResourceLoadingDataRequest
    private let loadingRequest: AVAssetResourceLoadingRequest
    private let continuation: CheckedContinuation<Void, Error>
    private let logger = Logger(subsystem: "com.music-stream-app", category: "StreamingData")
    private var totalBytesReceived = 0
    private var isFirstChunk = true
    private var isCancelled = false
    private var isCompleted = false
    private let lock = NSLock()
    
    init(dataRequest: AVAssetResourceLoadingDataRequest, 
         loadingRequest: AVAssetResourceLoadingRequest,
         continuation: CheckedContinuation<Void, Error>) {
        self.dataRequest = dataRequest
        self.loadingRequest = loadingRequest
        self.continuation = continuation
        super.init()
    }
    
    func cancel() {
        lock.withLock { isCancelled = true }
    }
    
    // MARK: - URLSessionDelegate (session-level auth challenges)
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }
    
    // MARK: - URLSessionTaskDelegate (task-level auth challenges)
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }
    
    private func handleChallenge(_ challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let authMethod = challenge.protectionSpace.authenticationMethod
        
        switch authMethod {
        case NSURLAuthenticationMethodServerTrust:
            handleServerTrustChallenge(challenge, completionHandler: completionHandler)
        case NSURLAuthenticationMethodClientCertificate:
            handleClientCertificateChallenge(challenge, completionHandler: completionHandler)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    private func handleServerTrustChallenge(_ challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        guard let pinnedCA = CertificateService.loadPinnedCACertificateSync() else {
            logger.error("Failed to load pinned CA certificate for streaming")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let anchorCertificates = [pinnedCA] as CFArray
        guard SecTrustSetAnchorCertificates(serverTrust, anchorCertificates) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(serverTrust, true) == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            logger.error("Server trust evaluation failed for streaming")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    private func handleClientCertificateChallenge(_ challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let credential = CertificateService.clientCredentialSync else {
            logger.error("Client credential not available for streaming")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, credential)
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Stream request failed with status: \(statusCode)")
            completionHandler(.cancel)
            resumeWithError(NSError(domain: "MTLSResourceLoader", code: -2, 
                userInfo: [NSLocalizedDescriptionKey: "Data request failed with status \(statusCode)"]))
            return
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let cancelled = lock.withLock { isCancelled }
        guard !cancelled else { return }
        
        // Deliver data immediately to AVPlayer as it arrives from the network
        dataRequest.respond(with: data)
        totalBytesReceived += data.count
        
        if isFirstChunk {
            logger.debug("First chunk delivered: \(data.count) bytes")
            isFirstChunk = false
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            resumeWithError(error)
        } else {
            logger.debug("Streamed \(self.totalBytesReceived) bytes total to AVPlayer")
            resumeWithSuccess()
        }
    }
    
    private func resumeWithError(_ error: Error) {
        lock.lock()
        let cancelled = isCancelled
        let completed = isCompleted
        if !completed { isCompleted = true }
        lock.unlock()
        
        if !cancelled && !completed {
            logger.error("Stream failed: \(error.localizedDescription)")
            continuation.resume(throwing: error)
        }
    }
    
    private func resumeWithSuccess() {
        lock.lock()
        let completed = isCompleted
        if !completed { isCompleted = true }
        lock.unlock()
        
        if !completed {
            continuation.resume()
        }
    }
}

// MARK: - mTLS Resource Loader Delegate

final class MTLSResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    private let logger = Logger(subsystem: "com.music-stream-app", category: "MTLSResourceLoader")
    private var pendingTasks: [AVAssetResourceLoadingRequest: Task<Void, Never>] = [:]
    private var pendingDataDelegates: [AVAssetResourceLoadingRequest: (URLSessionDataTask, StreamingDataDelegate)] = [:]
    private let lock = NSLock()
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else {
            return false
        }
        
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        components.scheme = "https"
        
        guard let httpsURL = components.url else {
            return false
        }
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.handleLoadingRequest(loadingRequest, httpsURL: httpsURL)
        }
        
        addPendingTask(task, for: loadingRequest)
        
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        cancelAndRemoveTask(for: loadingRequest)
    }
    
    // MARK: - Thread-safe task management (synchronous, not async)
    
    private func addPendingTask(_ task: Task<Void, Never>, for request: AVAssetResourceLoadingRequest) {
        lock.withLock {
            pendingTasks[request] = task
        }
    }
    
    private func removePendingTask(for request: AVAssetResourceLoadingRequest) {
        lock.withLock {
            _ = pendingTasks.removeValue(forKey: request)
            _ = pendingDataDelegates.removeValue(forKey: request)
        }
    }
    
    private func cancelAndRemoveTask(for request: AVAssetResourceLoadingRequest) {
        lock.withLock {
            if let task = pendingTasks.removeValue(forKey: request) {
                task.cancel()
            }
            if let (dataTask, delegate) = pendingDataDelegates.removeValue(forKey: request) {
                delegate.cancel()
                dataTask.cancel()
            }
        }
    }
    
    private func handleLoadingRequest(_ loadingRequest: AVAssetResourceLoadingRequest, httpsURL: URL) async {
        do {
            if let contentInfoRequest = loadingRequest.contentInformationRequest {
                try await fillContentInfo(contentInfoRequest, url: httpsURL, loadingRequest: loadingRequest)
            }
            
            if let dataRequest = loadingRequest.dataRequest {
                try await fulfillDataRequest(dataRequest, url: httpsURL, loadingRequest: loadingRequest)
            }
            
            removePendingTask(for: loadingRequest)
            loadingRequest.finishLoading()
        } catch {
            removePendingTask(for: loadingRequest)
            if !Task.isCancelled {
                logger.error("mTLS resource loading failed: \(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
            }
        }
    }
    
    private func fillContentInfo(_ contentInfoRequest: AVAssetResourceLoadingContentInformationRequest, 
                                  url: URL, 
                                  loadingRequest: AVAssetResourceLoadingRequest) async throws {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        
        let (_, response) = try await AppConfig.API.urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "MTLSResourceLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get content info"])
        }
        
        let mimeType = httpResponse.value(forHTTPHeaderField: "Content-Type")
        let uti = mimeType.map { utiFromMimeType($0) } ?? "public.mpeg-4-audio"
        contentInfoRequest.contentType = uti
        logger.debug("Content-Type: \(mimeType ?? "nil") → UTI: \(uti)")
        
        let contentRangeStr = httpResponse.value(forHTTPHeaderField: "Content-Range")
        let contentLengthStr = httpResponse.value(forHTTPHeaderField: "Content-Length")
        let acceptRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges")
        
        logger.debug("Content-Range: \(contentRangeStr ?? "nil"), Content-Length: \(contentLengthStr ?? "nil"), Accept-Ranges: \(acceptRanges ?? "nil")")
        
        if let contentRangeStr, let totalLength = parseContentRangeTotalLength(contentRangeStr) {
            contentInfoRequest.contentLength = totalLength
            logger.debug("Set contentLength from Content-Range: \(totalLength)")
        } else if let contentLengthStr, let contentLength = Int64(contentLengthStr) {
            contentInfoRequest.contentLength = contentLength
            logger.debug("Set contentLength from Content-Length: \(contentLength)")
        } else {
            logger.warning("Could not determine content length")
        }
        
        let hasContentRange = contentRangeStr != nil
        contentInfoRequest.isByteRangeAccessSupported = (acceptRanges == "bytes" || hasContentRange)
        logger.debug("Byte range supported: \(contentInfoRequest.isByteRangeAccessSupported)")
    }
    
    private func parseContentRangeTotalLength(_ contentRange: String) -> Int64? {
        let parts = contentRange.split(separator: "/")
        guard parts.count == 2, let totalStr = parts.last, totalStr != "*" else {
            return nil
        }
        return Int64(totalStr)
    }
    
    private func utiFromMimeType(_ mimeType: String) -> String {
        let cleanMime = mimeType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? mimeType.lowercased()
        switch cleanMime {
        case "audio/mp4", "audio/x-m4a", "audio/m4a":
            return "public.mpeg-4-audio"
        case "audio/mpeg", "audio/mp3":
            return "public.mp3"
        case "audio/aac":
            return "public.aac-audio"
        case "audio/wav", "audio/x-wav":
            return "com.microsoft.waveform-audio"
        case "audio/flac":
            return "org.xiph.flac"
        default:
            return "public.mpeg-4-audio"
        }
    }
    
    private func fulfillDataRequest(_ dataRequest: AVAssetResourceLoadingDataRequest,
                                     url: URL,
                                     loadingRequest: AVAssetResourceLoadingRequest) async throws {
        let requestedOffset = dataRequest.requestedOffset
        let requestedLength = dataRequest.requestedLength
        
        logger.debug("Data request: offset=\(requestedOffset), length=\(requestedLength)")
        
        var request = URLRequest(url: url)
        
        if requestedLength > 0 {
            let endOffset = requestedOffset + Int64(requestedLength) - 1
            request.setValue("bytes=\(requestedOffset)-\(endOffset)", forHTTPHeaderField: "Range")
        }
        
        // Use delegate-based streaming for efficient chunk delivery
        // Data is delivered to AVPlayer immediately as it arrives from the network
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = StreamingDataDelegate(
                dataRequest: dataRequest,
                loadingRequest: loadingRequest,
                continuation: continuation
            )
            
            // Create a dedicated session with this delegate for streaming
            let config = AppConfig.API.urlSessionConfiguration
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let dataTask = session.dataTask(with: request)
            
            // Track for cancellation
            lock.withLock {
                pendingDataDelegates[loadingRequest] = (dataTask, delegate)
            }
            
            dataTask.resume()
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
    private var resourceLoaderDelegate: MTLSResourceLoaderDelegate?
    
    private nonisolated static let playbackStateKey = "persistedPlaybackState"
    private var saveStateTask: Task<Void, Never>?
    private let saveStateDebounceInterval: Duration = .milliseconds(500)
    
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
    
    // Current playlist tracking
    var currentPlaylistId: UUID?
    
    // Playback modes
    var playbackMode: PlaybackMode = .linear {
        didSet {
            if playbackMode == .shuffle {
                shuffleQueue()
            } else {
                restoreOriginalQueue()
            }
            scheduleSavePlaybackState()
        }
    }
    var repeatMode: RepeatMode = .none {
        didSet {
            scheduleSavePlaybackState()
        }
    }
    
    private init() {
        setupAudioSession()
        setupRemoteTransportControls()
        setupInterruptionHandling()
        restorePlaybackState()
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
            logger.error("Failed to setup audio session: \(error.localizedDescription)")
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
    
    func loadAndPlay(song: Song, from playlist: [Song]? = nil, playlistId: UUID? = nil) {
        if let playlist = playlist {
            originalQueue = playlist
            if playbackMode == .shuffle {
                shuffleQueue()
            } else {
                queue = playlist
            }
            currentIndex = queue.firstIndex(where: { $0.id == song.id }) ?? 0
        }
        
        currentPlaylistId = playlistId
        loadSong(song)
        play()
    }
    
    private func loadSong(_ song: Song) {
        cleanup()
        clearError()
        
        currentSong = song
        isLoading = true
        isBuffering = true
        
        if let localURL = song.localFileURL {
            playerItem = AVPlayerItem(url: localURL)
            isBuffering = false
        } else {
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
            
            if ServerConfigService.shared.serverProtocol == "https" {
                guard var components = URLComponents(string: song.streamURL) else {
                    setError(.invalidURL)
                    isLoading = false
                    isBuffering = false
                    return
                }
                components.scheme = "mtls-stream"
                guard let mtlsURL = components.url else {
                    setError(.invalidURL)
                    isLoading = false
                    isBuffering = false
                    return
                }
                
                let asset = AVURLAsset(url: mtlsURL)
                resourceLoaderDelegate = MTLSResourceLoaderDelegate()
                asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: DispatchQueue.global(qos: .userInitiated))
                playerItem = AVPlayerItem(asset: asset)
            } else {
                playerItem = AVPlayerItem(url: url)
            }
        }
        
        player = AVPlayer(playerItem: playerItem)
        
        setupTimeObserver()
        observePlayerItem()
        updateNowPlayingInfo()
        fetchArtworkForNowPlaying(song: song)
        scheduleSavePlaybackState()
    }
    
    private func setError(_ error: PlaybackError) {
        currentError = error
        showError = true
        isPlaying = false
    }
    
    private func fetchArtworkForNowPlaying(song: Song) {
        if let localArtworkURL = song.localArtworkURL {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let strongSelf = self else { return }
                if let data = try? Data(contentsOf: localArtworkURL),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        strongSelf.updateNowPlayingArtwork(image)
                    }
                }
            }
            return
        }
        
        guard let artworkURLString = song.artworkURL,
              let artworkURL = URL(string: artworkURLString) else { return }

        guard NetworkMonitor.shared.isConnected else { return }
        
        if let cached = artworkCache[artworkURLString] {
            touchArtworkAccess(artworkURLString)
            updateNowPlayingArtwork(cached)
            return
        }
        
        Task.detached { [weak self, artworkURLString] in
            guard let strongSelf = self else { return }
            do {
                let (data, _) = try await AppConfig.API.urlSession.data(from: artworkURL)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        strongSelf.evictAndCacheArtwork(image, for: artworkURLString)
                        strongSelf.updateNowPlayingArtwork(image)
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
    
    private var lastSaveTime: TimeInterval = 0
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            MainActor.assumeIsolated {
                self.currentTime = seconds
                if let duration = self.player?.currentItem?.duration.seconds, duration.isFinite {
                    self.duration = duration
                }
                self.updateNowPlayingInfo()
                
                if abs(seconds - self.lastSaveTime) >= 5 {
                    self.lastSaveTime = seconds
                    self.scheduleSavePlaybackState()
                }
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
                    logger.debug("Player status: readyToPlay, duration: \(self.playerItem?.duration.seconds ?? -1)")
                    self.isBuffering = false
                    self.isLoading = false
                    if let duration = self.playerItem?.duration.seconds, duration.isFinite {
                        self.duration = duration
                    }
                case .failed:
                    self.isLoading = false
                    self.isBuffering = false
                    let errorMessage = self.playerItem?.error?.localizedDescription ?? "Unknown error"
                    logger.error("Player status: failed - \(errorMessage)")
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
        logger.debug("play() called, player exists: \(self.player != nil), rate: \(self.player?.rate ?? -1)")
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
        logger.debug("After play(), rate: \(self.player?.rate ?? -1)")
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
        scheduleSavePlaybackState()
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
        scheduleSavePlaybackState()
    }
    
    func playFromQueue(at index: Int) {
        guard index < queue.count else { return }
        currentIndex = index
        loadSong(queue[index])
        play()
    }
    
    func removeFromQueue(at index: Int) {
        guard index < queue.count, index != currentIndex else { return }
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        }
        scheduleSavePlaybackState()
    }
    
    func syncQueueWithPlaylist(_ playlist: [Song]) {
        let currentSongId = currentSong?.id
        let playlistIds = Set(playlist.map { $0.id })
        
        queue = queue.filter { playlistIds.contains($0.id) }
        originalQueue = originalQueue.filter { playlistIds.contains($0.id) }
        
        if let id = currentSongId {
            if let newIndex = queue.firstIndex(where: { $0.id == id }) {
                currentIndex = newIndex
            } else {
                currentSong = nil
                currentIndex = 0
                cleanup()
            }
        }
        scheduleSavePlaybackState()
    }
    
    // MARK: - State Persistence
    
    private func scheduleSavePlaybackState() {
        saveStateTask?.cancel()
        saveStateTask = Task { [weak self] in
            try? await Task.sleep(for: self?.saveStateDebounceInterval ?? .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.performSavePlaybackState()
        }
    }
    
    private func performSavePlaybackState() async {
        let state = PersistedPlaybackState(
            currentSong: currentSong.map { PersistedSong(from: $0) },
            queue: queue.map { PersistedSong(from: $0) },
            originalQueue: originalQueue.map { PersistedSong(from: $0) },
            currentIndex: currentIndex,
            currentTime: currentTime,
            playbackMode: playbackMode.rawValue,
            repeatMode: repeatMode.rawValue,
            currentPlaylistId: currentPlaylistId?.uuidString
        )
        
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        
        await Task.detached(priority: .utility) {
            UserDefaults.standard.set(encoded, forKey: AudioPlayerService.playbackStateKey)
        }.value
    }
    
    private func restorePlaybackState() {
        guard let data = UserDefaults.standard.data(forKey: Self.playbackStateKey),
              let state = try? JSONDecoder().decode(PersistedPlaybackState.self, from: data) else {
            return
        }
        
        if let persistedSong = state.currentSong {
            currentSong = persistedSong.toSong()
        }
        queue = state.queue.map { $0.toSong() }
        originalQueue = state.originalQueue.map { $0.toSong() }
        currentIndex = state.currentIndex
        currentTime = state.currentTime
        
        if let mode = PlaybackMode(rawValue: state.playbackMode) {
            playbackMode = mode
        }
        if let mode = RepeatMode(rawValue: state.repeatMode) {
            repeatMode = mode
        }
        
        if let playlistIdString = state.currentPlaylistId {
            currentPlaylistId = UUID(uuidString: playlistIdString)
        }
        
        if let song = currentSong {
            loadSongForRestore(song, seekTo: state.currentTime)
        }
    }
    
    private func loadSongForRestore(_ song: Song, seekTo time: TimeInterval) {
        clearError()
        
        currentSong = song
        isLoading = true
        isBuffering = true
        
        if let localURL = song.localFileURL {
            playerItem = AVPlayerItem(url: localURL)
            isBuffering = false
        } else {
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
            
            if ServerConfigService.shared.serverProtocol == "https" {
                guard var components = URLComponents(string: song.streamURL) else {
                    setError(.invalidURL)
                    isLoading = false
                    isBuffering = false
                    return
                }
                components.scheme = "mtls-stream"
                guard let mtlsURL = components.url else {
                    setError(.invalidURL)
                    isLoading = false
                    isBuffering = false
                    return
                }
                
                let asset = AVURLAsset(url: mtlsURL)
                resourceLoaderDelegate = MTLSResourceLoaderDelegate()
                asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: DispatchQueue.global(qos: .userInitiated))
                playerItem = AVPlayerItem(asset: asset)
            } else {
                playerItem = AVPlayerItem(url: url)
            }
        }
        
        player = AVPlayer(playerItem: playerItem)
        
        setupTimeObserver()
        observePlayerItem()
        updateNowPlayingInfo()
        fetchArtworkForNowPlaying(song: song)
        
        if time > 0 {
            let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
        resourceLoaderDelegate = nil
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
    
    func isPlayingPlaylist(_ playlistId: UUID) -> Bool {
        currentPlaylistId == playlistId && currentSong != nil
    }
}
