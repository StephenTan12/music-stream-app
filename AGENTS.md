# AGENTS.md

> Swift 5.9+ | SwiftUI + SwiftData | iOS 17.0+ | Swift 6 concurrency

Music streaming app: .mp4 audio streaming, playlist management, background playback, lock screen controls, session persistence, offline downloads, dark mode UI.

## Structure

```
music-stream-app/
├── music_stream_appApp.swift      # Entry point, SwiftData container
├── ContentView.swift              # Root: server config check, deferred service init
├── Info.plist                     # Background modes, dark mode, launch screen
├── Config/AppConfig.swift         # API URLs, cache size, timing constants, download paths
├── Models/
│   ├── Song.swift                 # SwiftData: title, artist, videoId, artworkURL, download state; streamURL computed dynamically
│   ├── Playlist.swift             # SwiftData: ordered songs via PlaylistSong join, backend sync fields (totalSongs, totalDuration)
│   └── PlaylistSong.swift         # SwiftData: join model with order field for song ordering
├── Services/
│   ├── AudioPlayerService.swift   # AVPlayer, queue, lock screen, session persistence, offline playback, mTLS streaming
│   ├── CertificateService.swift   # mTLS client certificates, multi-identity storage, P12 import, CA pinning
│   ├── DownloadService.swift      # Offline downloads, progress tracking, storage management
│   ├── NetworkMonitor.swift       # NWPathMonitor connectivity + server reachability
│   ├── NetworkSessionDelegate.swift # URLSession delegate for mTLS auth challenges
│   ├── ServerConfigService.swift  # User-configurable server URL (protocol, host, port) with UserDefaults persistence
│   ├── SongService.swift          # Backend song API client
│   └── PlaylistService.swift      # Backend playlist API client with sync
├── Views/
│   ├── PlaylistListView.swift     # Playlist list with metadata sync, pull-to-refresh, system playlist badges, connection status icons, settings access
│   ├── PlaylistDetailView.swift   # Playlist songs (synced on navigation), play/shuffle controls, scroll-aware nav title
│   ├── AllSongsView.swift         # API songs browse, play/shuffle controls
│   ├── NowPlayingView.swift       # Full player, seek, queue access
│   ├── QueueView.swift            # Playback queue
│   ├── AddSongView.swift          # URL validation
│   ├── EditPlaylistView.swift     # Playlist editing
│   ├── SettingsView.swift         # Server configuration sheet (protocol, host, port, certificate)
│   ├── ServerSetupView.swift      # First-launch server setup screen with certificate import for HTTPS
│   ├── CertificateImportView.swift   # P12 file import with password entry
│   ├── CertificateSelectionView.swift # Select from saved certificates or import new
│   └── Components/
│       ├── MiniPlayerView.swift          # Bottom player bar
│       ├── SongRowView.swift             # Song list row with context menu (download via long press)
│       ├── DownloadStorageView.swift     # Download management, storage stats
│       ├── CachedAsyncImage.swift        # LRU image cache
│       ├── CertificateStatusView.swift   # Certificate status display with expiration warnings
│       └── GradientPlaceholderView.swift # Missing artwork placeholder
└── Assets.xcassets/               # App assets, launch screen color
```

## Patterns

### Service Access (singletons, @MainActor)
```swift
// Use @State when reading service properties in the view body
@State private var audioPlayer = AudioPlayerService.shared
@State private var networkMonitor = NetworkMonitor.shared
@State private var playlistService = PlaylistService.shared
@State private var downloadService = DownloadService.shared
@State private var songService = SongService.shared

// Access singleton directly in methods when only writing (not reading in body)
// This avoids implicit observation that can cause cascading re-renders
func saveSettings() {
    let config = ServerConfigService.shared
    config.serverHost = host
}
```

### SwiftData
```swift
@Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
@Environment(\.modelContext) private var modelContext
```

### Navigation
```swift
NavigationStack {
    ListView()
        .navigationDestination(for: Model.self) { DetailView(item: $0) }
}
```

### Modals
```swift
.sheet(isPresented: $show) { SheetView() }
.fullScreenCover(isPresented: $show) { FullView() }
```

### Async
```swift
Task { await service.fetch() }
Task { @MainActor in AudioPlayerService.shared.play() }
```

## Conventions

| Area | Rule |
|------|------|
| **Naming** | Views: `*View.swift`, Services: `*Service.swift`, Models: `*.swift` |
| **State** | `@State` (local), `@Observable` (services), `@Query` (SwiftData), `@Bindable` (binding). Never use `@StateObject` or `@ObservedObject` - use `@State` with `@Observable` services instead |
| **Concurrency** | All services `@MainActor`, use `async/await`, no callbacks |
| **Errors** | Typed enums + `LocalizedError`, handle at UI boundary |
| **Logging** | `os.Logger` not `print` |
| **Persistence** | SwiftData (models), UserDefaults (playback state, server config), Documents (downloads) |

## Common Tasks

**New View**: Create in `Views/`, add nav destination in `ContentView`, use `AudioPlayerService.shared`

**Change Server URL**: User configures via `SettingsView` (gear icon in nav bar) or `ServerSetupView` (first launch). Settings stored in `ServerConfigService.shared` with UserDefaults persistence. `AppConfig.API.baseURL` is a computed property that reads from `ServerConfigService.shared.baseURL`. After changing server, playlists auto-refresh from the new server. Song `streamURL` is a computed property that dynamically builds URLs from `videoId` + current server config, so all synced songs immediately use the new server for streaming.

**New Model Property**: Edit model file, SwiftData auto-migrates, update UI

**New API Endpoint**: Add to `AppConfig.API.Endpoints`, create DTO if needed, add service method, configure `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` for backend snake_case

**Modify Playback**: Edit `AudioPlayerService.swift`, all methods `@MainActor`, update observable properties

**Sync Backend Data**: Playlist syncing uses a two-tier approach for efficiency:
- `PlaylistService.shared.syncPlaylistMetadata(modelContext:)` - Fetches only playlist list (name, description, isSystem, totalSongs, totalDuration) without songs. Used by `PlaylistListView` for initial load and pull-to-refresh.
- `PlaylistService.shared.syncPlaylistToLocal(_:modelContext:)` - Fetches a single playlist's songs. Used by `PlaylistDetailView` when navigating to a playlist.
- `PlaylistService.shared.syncPlaylistsToLocal(modelContext:)` - Full sync of all playlists and songs. Use sparingly as it makes N+1 API calls.

All sync methods reuse existing songs by `videoId` to preserve download paths and clean up orphaned songs without downloads. Backend-provided `totalSongs` and `totalDuration` are stored directly on the playlist and used by `songCount` and `duration` computed properties when available, falling back to local calculation.

**Add Song to Playlist**: Use `playlist.addSong(song)` to add songs with proper ordering, use `playlist.removeSong(at:)` to remove, use `playlist.moveSong(from:to:)` to reorder

**Download Song**: Use `DownloadService.shared.downloadSong(song)` to download audio and artwork to Documents directory. Automatically checks for existing files to prevent duplicates. Check `song.isDownloaded` for persisted download state, and use `DownloadService.shared.cleanupStalePaths(modelContext:)` to reconcile missing files.

**Download Playlist**: Use `DownloadService.shared.downloadPlaylist(playlist)` to download all songs in a playlist. Track progress via `downloadService.playlistDownloadProgress` (0.0-1.0) and check `downloadService.isDownloadingPlaylist(playlist)` to determine if a specific playlist is currently downloading

**Remove Downloads**: Use `DownloadService.shared.removeSongDownload(song)` for single song, `removeAllDownloads(modelContext:)` for all

**Cleanup Stale Paths**: Use `DownloadService.shared.cleanupStalePaths(modelContext:)` to clear `localFilePath`/`localArtworkPath` on songs whose files were deleted. Runs automatically on app startup via `ContentView.task`.

## Key Implementation Details

### Server Configuration

User-configurable server URL with first-launch setup:
1. **First Launch**: `ContentView` checks `ServerConfigService.shared.isConfigured`. If `false`, shows `ServerSetupView` requiring user to enter server details before accessing the app.
2. **Settings Access**: Gear icon in `PlaylistListView` toolbar opens `SettingsView` sheet to modify server anytime.
3. **Storage**: Protocol, host, port, and configured flag stored in UserDefaults via `ServerConfigService`.
4. **BaseURL**: `AppConfig.API.baseURL` is a computed property that reads from `ServerConfigService.shared.baseURL`.
5. **Post-Change Sync**: After saving settings, playlists automatically re-sync from the new server.
6. **View Pattern**: `ServerSetupView` and `SettingsView` use local `@State` for form fields and access `ServerConfigService.shared` directly in save methods (not via `@State`) to avoid observation-induced lag during typing.
7. **Deferred Init**: `ContentView` only initializes `ServerConfigService`. Heavy services (`AudioPlayerService`, `DownloadService`, `SongService`) are deferred to `MainContentView`, which only loads after server configuration is complete.

### Dynamic Stream URLs

Song `streamURL` is a computed property, not a stored value:
- **Songs with `videoId`** (synced from backend): URL computed dynamically from `AppConfig.API.Endpoints.streamSong(videoId:)` using current server config
- **Songs without `videoId`** (manually added via AddSongView): Use `storedStreamURL` fallback
- **Benefit**: Changing server settings immediately affects all synced songs without re-syncing
- **Persistence**: `PersistedSong` (for playback state) stores `videoId`, not `streamURL`; URL is reconstructed on restore

### Download Persistence

Downloads persist across app sessions through:
1. **Documents Directory**: Files stored in `FileManager.documentDirectory` (not Caches, which iOS can purge)
2. **Song Reuse**: `PlaylistService` sync methods reuse existing songs by `videoId` to preserve `localFilePath`/`localArtworkPath`
3. **Startup Cleanup**: `ContentView.task` calls `cleanupStalePaths` to verify file existence and clear stale paths
4. **Duplicate Prevention**: `DownloadService.downloadAudioFile` checks if file exists before downloading
5. **Render Performance**: `Song` download helpers return persisted paths without synchronous filesystem checks during SwiftUI view updates
6. **File I/O Isolation**: `DownloadService` performs storage scans, file moves, writes, and deletes off the main actor, then publishes results back to the UI

### Download UI

- **No inline button**: Download controls removed from `SongRowView` (no `showDownloadButton` parameter)
- **Context menu**: Long press song → "Download" option
- **Visual indicator**: Small download icon appears next to artist name when `song.isDownloaded` is true
- **Playlist toolbar**: Download all songs button in `PlaylistDetailView` toolbar
- **Playlist progress**: Use `downloadService.playlistDownloadProgress` for aggregate progress, `downloadService.isDownloadingPlaylist(playlist)` to check download state

### Download Performance

Downloads are optimized to minimize CPU and UI impact:
1. **Utility Priority**: All download tasks run with `.utility` priority to avoid competing with UI
2. **Throttled Progress**: `DownloadProgressDelegate` only reports progress every 2% change or 100ms minimum interval
3. **Coalesced UI Updates**: Both `scheduleProgressUpdate()` (playlist) and `scheduleSingleSongProgressUpdate()` (single song) batch progress updates with 50ms debounce, preventing excessive SwiftUI re-renders
4. **Debounced Storage Refresh**: `scheduleStorageRefresh()` limits expensive directory scans to max once per 2 seconds
5. **Aggregate Progress**: `playlistDownloadProgress` is maintained centrally in `DownloadService` instead of computed from individual songs, avoiding O(n) iteration on every render
6. **Async Directory Creation**: `DownloadService.init()` creates download directories via `Task.detached(priority: .utility)` to avoid blocking main thread

### Playlist Performance

Playlist loading and queue operations are optimized for large playlists:
1. **Sort by Order**: `Playlist.songs` sorts by `PlaylistSong.order` (integer comparison) instead of title (locale-aware string comparison)
2. **Batch SwiftData Lookups**: `PlaylistService.syncPlaylistToLocal` fetches all songs with videoIds in one query, then uses dictionary lookup O(1) instead of N individual fetches
3. **Set-Based Queue Sync**: `AudioPlayerService.syncQueueWithPlaylist` uses `Set<UUID>` for O(1) membership checks instead of O(n) `contains(where:)`

### Playback State Persistence

Session persistence is optimized to avoid blocking the main thread:
1. **Debounced Saves**: `scheduleSavePlaybackState()` debounces saves with 500ms delay to coalesce frequent updates
2. **Background Encoding**: `performSavePlaybackState()` encodes JSON and writes to UserDefaults via `Task.detached(priority: .utility)`
3. **Async Artwork Loading**: `fetchArtworkForNowPlaying` loads local artwork via `Task.detached` to avoid blocking main thread with `Data(contentsOf:)`

### HTTPS/mTLS Authentication

The app supports mutual TLS (mTLS) for secure server connections:

1. **Certificate Import Flow**:
   - User selects HTTPS protocol in `ServerSetupView` or `SettingsView`
   - Certificate section appears with `CertificateStatusView`
   - User taps "Add Certificate" or "Change Certificate" to open `CertificateSelectionView`
   - User can select from saved certificates or import a new one via `CertificateImportView`
   - User selects .p12 file and enters password
   - `CertificateService.importP12()` extracts identity and stores in Keychain

2. **Keychain Storage** (secure, multi-identity):
   - Multiple `SecIdentity` items stored with unique labels (`mTLS-client-<UUID>`)
   - Each identity stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
   - Identity metadata (`StoredIdentity`: id, commonName, expirationDate) persisted in UserDefaults
   - Selected identity ID tracked in UserDefaults; auto-selects next on deletion
   - P12 file data zeroed from memory after import (password NOT stored)
   - First-launch cleanup removes orphaned Keychain items; legacy single-identity migrated automatically
   - Static caching via `nonisolated(unsafe)` properties to avoid repeated Keychain lookups

3. **Network Session Authentication**:
   - `AppConfig.API.urlSession` returns `authenticatedURLSession` for HTTPS
   - Authenticated session is cached and automatically invalidated when server config changes
   - Services use `performRequestWithRetry()` to invalidate and retry on timeout errors
   - `NetworkSessionDelegate` handles two challenge types:
     - Server trust: CA pinning via embedded PEM certificate in `CertificateService`
     - Client certificate: Provides `SecIdentity` from Keychain

4. **AVPlayer mTLS Streaming**:
   - Uses custom URL scheme `mtls-stream://` for HTTPS streams
   - `MTLSResourceLoaderDelegate` (in AudioPlayerService) intercepts requests
   - Converts to `https://` and routes through authenticated `URLSession`
   - Supports byte-range requests via HTTP `Range` headers for efficient streaming
   - Implements `didCancel` to cancel in-flight requests on seek/skip
   - **Content Info Request**: Initial `Range: bytes=0-0` request fetches headers only (1 byte); `fillContentInfo` extracts `Content-Range` for total length, `Accept-Ranges` for byte-range support
   - **UTI Conversion**: `AVAssetResourceLoadingContentInformationRequest.contentType` requires UTI (e.g., `public.mpeg-4-audio`), not MIME type; `utiFromMimeType(_:)` helper converts `audio/mp4` → `public.mpeg-4-audio`, `audio/mpeg` → `public.mp3`, etc.
   - **Debug Logging**: Extensive `os.Logger` output for content info, data requests, player status changes, and `play()` invocations

5. **External P12 File Opening**:
   - App registered as .p12 file handler via Info.plist
   - `onOpenURL` in app entry point sets `CertificateService.pendingImportURL`
   - `CertificateSelectionView` offers: select from saved identities or import new (P12)
   - `CertificateImportView` checks for pending URL on appear and pre-fills the file selection
   - `pendingImportURL` is cleared only after successful import (preserved on cancel for retry)

6. **Certificate Status UI**:
   - `CertificateStatusView` shows: installed (green), expiring soon (orange), expired (red), or missing (orange)
   - Displays common name and expiration date of selected certificate
   - Remove button removes only the selected certificate (auto-selects next if available)
   - `CertificateSelectionView` lists all saved certificates with swipe-to-delete
   - Status row has VoiceOver accessibility support

**Import Certificate**: Use `CertificateService.shared.importP12(from: url, password: password)` with async/await. The URL should be from `fileImporter` with security-scoped access.

**Select Certificate**: Use `CertificateService.shared.selectIdentity(id: uuid)` to switch to a saved certificate. Use `CertificateService.shared.storedIdentities` for the list, `selectedIdentityId` for the active one.

**Remove Certificate**: Use `CertificateService.shared.removeIdentity(id: uuid)` for a single identity, or `removeAllCertificateData()` for all.

**Check Certificate Status**: Use `CertificateService.shared.isClientCertificateConfigured` to verify a certificate is available. Certificate and CA lookups are cached to avoid repeated Keychain access.

**Certificate for URLSession**: `NetworkSessionDelegate.shared` automatically uses static `nonisolated` methods on `CertificateService` (`clientCredentialSync`, `loadPinnedCACertificateSync`) for authentication challenges - these do not access the `shared` instance to avoid actor isolation issues.

### Offline Network Guardrails

- All network-dependent services must check `NetworkMonitor.shared.isConnected` before creating `URLSession` requests
- `SongService` and `PlaylistService` return early when offline (silent fail, no error alerts)
- On server errors, services set `NetworkMonitor.shared.isServerReachable = false` (reset to `true` on success)
- `PlaylistListView` shows connection status icons in nav bar: `wifi.slash` (offline) or `exclamationmark.icloud` (server down)
- `CachedAsyncImage` should skip remote image loads when offline
- `DownloadService` should reject new downloads when offline and skip optional artwork requests
- `AudioPlayerService` should avoid remote stream/artwork fetches when offline (local files/cached artwork still allowed)

## Pitfalls

```swift
// ❌ Background thread service access
Task.detached { AudioPlayerService.shared.play() }

// ✅ Main actor
Task { @MainActor in AudioPlayerService.shared.play() }

// ❌ Create Task for main queue callback when already on main actor
player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
    Task { @MainActor in self.updateTime(time) } // Unnecessary Task overhead
}

// ✅ Use MainActor.assumeIsolated for main queue callbacks
player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
    MainActor.assumeIsolated { self.updateTime(time) } // No Task allocation
}

// ❌ New instance
let player = AudioPlayerService()

// ✅ Singleton
let player = AudioPlayerService.shared

// ❌ Callbacks
func fetch(completion: @escaping (Data) -> Void)

// ✅ Async
func fetch() async -> Data

// ❌ Use @StateObject or @ObservedObject with ObservableObject
@StateObject private var songService = SongService.shared

// ✅ Use @State with @Observable services
@State private var songService = SongService.shared

// ❌ Compare songs by UUID (fails after app restart - restored songs have same UUID but different instance)
audioPlayer.currentSong?.id == song.id

// ✅ Compare songs by videoId first, fallback to id
if let currentVideoId = audioPlayer.currentSong?.videoId, let songVideoId = song.videoId {
    return currentVideoId == songVideoId
}
return audioPlayer.currentSong?.id == song.id

// ❌ Access DownloadService.cachesDirectory from non-main-actor context
let url = DownloadService.cachesDirectory // Error if cachesDirectory is @MainActor

// ✅ Use nonisolated static property for cross-actor access
nonisolated static var cachesDirectory: URL { ... }

// ❌ Call FileManager.fileExists from computed properties used in SwiftUI rows
var isDownloaded: Bool { FileManager.default.fileExists(atPath: ...) }

// ✅ Reconcile file existence once in cleanup, keep row-time checks cheap
DownloadService.shared.cleanupStalePaths(modelContext: modelContext)

// ❌ Do large file moves / directory scans directly on the main actor
totalStorageUsed = directorySize(at: downloadsURL)

// ✅ Run heavy file I/O off-main, then update observable state
Task { await refreshStorageUsage() }

// ❌ Access AppConfig from nonisolated context (Swift 6 error)
private nonisolated static func foo() {
    let path = AppConfig.Downloads.directory // Error: main actor-isolated
}

// ✅ Use local constants in nonisolated functions
private nonisolated static func foo() {
    let downloadDirectory = "Downloads" // Local constant
    let path = cachesDirectory.appendingPathComponent(downloadDirectory)
}

// ❌ Use for-in loop on FileManager.DirectoryEnumerator in async context
for case let fileURL as URL in enumerator { ... } // Error: makeIterator unavailable

// ✅ Use nextObject() for Swift 6 async contexts
while let fileURL = enumerator.nextObject() as? URL { ... }

// ❌ Use @State with @Observable singleton when only writing (causes cascading re-renders)
struct SettingsView: View {
    @State private var serverConfig = ServerConfigService.shared // Implicit observation
    @State private var host: String = ""
    func save() { serverConfig.serverHost = host }
}

// ✅ Access singleton directly in methods when not reading in body
struct SettingsView: View {
    @State private var host: String = ""
    func save() {
        let config = ServerConfigService.shared // No observation dependency
        config.serverHost = host
    }
}

// ❌ Eagerly initialize expensive services in parent when child may not need them
struct ContentView: View {
    @State private var audioPlayer = AudioPlayerService.shared // Inits AVPlayer, audio session
    @State private var downloadService = DownloadService.shared // Creates dirs, scans storage
    var body: some View {
        if needsSetup { SetupView() } // Services initialized but not used!
        else { MainView() }
    }
}

// ✅ Defer service initialization to views that actually use them
struct ContentView: View {
    var body: some View {
        if needsSetup { SetupView() }
        else { MainContentView() } // Services init only when this view appears
    }
}
struct MainContentView: View {
    @State private var audioPlayer = AudioPlayerService.shared // Deferred init
}

// ❌ Use VStack with Spacers for forms (causes gesture timeout on TextField focus)
VStack {
    Spacer()
    TextField("Host", text: $host)
    Spacer()
}

// ✅ Use ScrollView for forms with TextFields (handles keyboard gracefully)
ScrollView {
    VStack {
        TextField("Host", text: $host)
    }
}
.scrollDismissesKeyboard(.interactively)

// ❌ Add keyboard toolbar to individual TextFields (causes conflicts)
TextField("Port", text: $port)
    .toolbar {
        ToolbarItemGroup(placement: .keyboard) { Button("Done") { ... } }
    }

// ✅ Add keyboard toolbar at view level (applies to all fields consistently)
Form {
    TextField("Host", text: $host)
    TextField("Port", text: $port)
}
.toolbar {
    ToolbarItemGroup(placement: .keyboard) { Button("Done") { ... } }
}

// ❌ Store full stream URL (becomes stale when server config changes)
var streamURL: String // Stored property with full URL

// ✅ Compute stream URL dynamically from videoId + current config
var streamURL: String {
    if let videoId = videoId {
        return AppConfig.API.Endpoints.streamSong(videoId: videoId)
    }
    return storedStreamURL ?? ""
}

// ❌ Compute progress from individual songs (O(n) on every render, creates observation dependencies)
private var playlistDownloadProgress: Double {
    playlist.songs.filter { $0.isDownloading }.reduce(0.0) { $0 + ($1.downloadProgress ?? 0) }
}

// ✅ Use aggregate progress from DownloadService (single observable property)
downloadService.playlistDownloadProgress
downloadService.isDownloadingPlaylist(playlist)

// ❌ Create new Task for every progress callback (high overhead)
progressHandler { progress in
    Task { @MainActor in self.updateProgress(progress) }
}

// ✅ Batch progress updates with debouncing
progressHandler { progress in
    Task { @MainActor in self.scheduleProgressUpdate(progress) }
}

// ❌ Sort playlist.songs by title on every access (O(n log n) string comparison)
var songs: [Song] {
    playlistSongs.compactMap { $0.song }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}

// ✅ Sort by PlaylistSong.order (O(n log n) integer comparison, respects backend order)
var songs: [Song] {
    playlistSongs.sorted { $0.order < $1.order }.compactMap { $0.song }
}

// ❌ Use contains(where:) in filter (O(n×m) for large playlists)
func syncQueueWithPlaylist(_ playlist: [Song]) {
    queue = queue.filter { song in
        playlist.contains(where: { $0.id == song.id })
    }
}

// ✅ Build Set first for O(1) lookups
func syncQueueWithPlaylist(_ playlist: [Song]) {
    let playlistIds = Set(playlist.map { $0.id })
    queue = queue.filter { playlistIds.contains($0.id) }
}

// ❌ N individual SwiftData fetches in a loop
for songDTO in playlistWithSongs.songs {
    let descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.videoId == songDTO.id })
    let existingSong = try? modelContext.fetch(descriptor).first
}

// ✅ Batch fetch once, use dictionary for O(1) lookups
let allSongs = try? modelContext.fetch(FetchDescriptor<Song>(predicate: #Predicate { $0.videoId != nil }))
let songsByVideoId = Dictionary(uniqueKeysWithValues: allSongs.compactMap { ($0.videoId!, $0) })
for songDTO in playlistWithSongs.songs {
    let existingSong = songsByVideoId[songDTO.id]
}

// ❌ Synchronous JSON encode + UserDefaults write on main thread
func savePlaybackState() {
    let encoded = try? JSONEncoder().encode(state)
    UserDefaults.standard.set(encoded, forKey: key)
}

// ✅ Debounce + encode on main actor, write in background
func scheduleSavePlaybackState() {
    saveStateTask?.cancel()
    saveStateTask = Task {
        try? await Task.sleep(for: .milliseconds(500))
        await performSavePlaybackState()
    }
}
private func performSavePlaybackState() async {
    guard let encoded = try? JSONEncoder().encode(state) else { return }
    await Task.detached(priority: .utility) {
        UserDefaults.standard.set(encoded, forKey: key)
    }.value
}

// ❌ Access playlist.songs multiple times in computed property
private var allSongsDownloaded: Bool {
    guard !playlist.songs.isEmpty else { return false }
    return playlist.songs.allSatisfy { $0.isDownloaded }
}

// ✅ Cache in local variable
private var allSongsDownloaded: Bool {
    let songs = playlist.songs
    guard !songs.isEmpty else { return false }
    return songs.allSatisfy { $0.isDownloaded }
}

// ❌ Synchronous Data(contentsOf:) for local artwork on main thread
if let data = try? Data(contentsOf: localArtworkURL),
   let image = UIImage(data: data) {
    updateNowPlayingArtwork(image)
}

// ✅ Load in background task (Swift 6: use strongSelf, not self)
Task.detached(priority: .userInitiated) { [weak self] in
    guard let strongSelf = self else { return }
    if let data = try? Data(contentsOf: localArtworkURL),
       let image = UIImage(data: data) {
        await MainActor.run { strongSelf.updateNowPlayingArtwork(image) }
    }
}

// ❌ Swift 6: Use `guard let self = self` in Task.detached (creates mutable binding)
Task.detached { [weak self] in
    guard let self else { return }
    await MainActor.run { self.doWork() } // Error: Reference to captured var 'self'
}

// ✅ Swift 6: Use `guard let strongSelf = self` (immutable binding)
Task.detached { [weak self] in
    guard let strongSelf = self else { return }
    await MainActor.run { strongSelf.doWork() }
}

// ❌ Swift 6: Access file-level logger from Task.detached (main actor-isolated)
private let logger = Logger(...)
Task.detached {
    logger.error("Error") // Error: Main actor-isolated let cannot be accessed
}

// ✅ Swift 6: Capture error and log after returning to main actor
Task.detached {
    do { try work() }
    catch { return error }
}.value
if let error = result { logger.error("\(error)") }

// ❌ Swift 6: Access static property from @MainActor class in detached task
@MainActor class Service {
    private static let key = "myKey"
    func save() async {
        await Task.detached {
            UserDefaults.standard.set(data, forKey: Self.key) // Error
        }.value
    }
}

// ✅ Swift 6: Mark constant static properties as nonisolated
@MainActor class Service {
    private nonisolated static let key = "myKey"
    func save() async {
        await Task.detached {
            UserDefaults.standard.set(data, forKey: Self.key) // OK
        }.value
    }
}

// ❌ Swift 6: Encode Codable in Task.detached when type is in @MainActor file
await Task.detached {
    let encoded = try? JSONEncoder().encode(state) // Error: main actor-isolated conformance
}.value

// ✅ Swift 6: Encode on main actor, pass Data to detached task
guard let encoded = try? JSONEncoder().encode(state) else { return }
await Task.detached {
    UserDefaults.standard.set(encoded, forKey: key) // Data is Sendable
}.value

// ❌ Access @MainActor CertificateService.shared from URLSession delegate queue
func urlSession(_ session: URLSession, didReceive challenge: ...) {
    let cert = CertificateService.shared.loadPinnedCACertificate() // Error: @MainActor
}

// ✅ Use static nonisolated methods (don't access .shared from nonisolated context)
func urlSession(_ session: URLSession, didReceive challenge: ...) {
    let cert = CertificateService.loadPinnedCACertificateSync() // static nonisolated
    let credential = CertificateService.clientCredentialSync // static nonisolated
}

// ❌ Use nonisolated on mutable static properties (Swift 6 error)
private nonisolated static var cache: SecIdentity?

// ✅ Use nonisolated(unsafe) for mutable caches with controlled writes
// Only safe when writes are limited to MainActor methods (import/removal)
private nonisolated(unsafe) static var cache: SecIdentity?
private nonisolated(unsafe) static var cacheValid = false

// ❌ Store P12 file in Documents directory (security risk)
let p12Path = documentsDirectory.appendingPathComponent("client.p12")
try p12Data.write(to: p12Path)

// ✅ Import identity to Keychain, never persist P12 file
let identity = try extractIdentity(from: p12Data, password: password)
try storeIdentityInKeychain(identity)
p12Data.resetBytes(in: p12Data.startIndex..<p12Data.endIndex) // Zero memory

// ❌ Use URLCredential.Persistence.forSession (may persist longer than needed)
URLCredential(identity: identity, certificates: nil, persistence: .forSession)

// ✅ Use .none for mTLS credentials
URLCredential(identity: identity, certificates: nil, persistence: .none)

// ❌ Trust all certificates or skip server trust evaluation
SecTrustSetAnchorCertificatesOnly(serverTrust, false) // Allows system CAs

// ✅ Pin to bundled CA certificate only
SecTrustSetAnchorCertificates(serverTrust, [pinnedCA] as CFArray)
SecTrustSetAnchorCertificatesOnly(serverTrust, true) // ONLY trust our CA

// ❌ Use AVPlayerItem(url:) for HTTPS mTLS streams (no delegate support)
let item = AVPlayerItem(url: httpsURL) // Won't authenticate

// ✅ Use AVAssetResourceLoaderDelegate with custom scheme
var components = URLComponents(string: song.streamURL)!
components.scheme = "mtls-stream"
let asset = AVURLAsset(url: components.url!)
asset.resourceLoader.setDelegate(delegate, queue: .global())
let item = AVPlayerItem(asset: asset)

// ❌ Fetch entire file in AVAssetResourceLoaderDelegate (breaks streaming)
let (data, _) = try await session.data(from: url)
dataRequest.respond(with: data) // Waits for full download

// ✅ Use byte-range requests for efficient streaming
var request = URLRequest(url: url)
let endOffset = dataRequest.requestedOffset + Int64(dataRequest.requestedLength) - 1
request.setValue("bytes=\(dataRequest.requestedOffset)-\(endOffset)", forHTTPHeaderField: "Range")
let (data, _) = try await session.data(for: request)
dataRequest.respond(with: data)

// ❌ Use MIME type directly for AVAssetResourceLoadingContentInformationRequest.contentType
contentInfoRequest.contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") // "audio/mp4"

// ✅ Convert MIME type to UTI (AVPlayer expects UTI, not MIME)
func utiFromMimeType(_ mimeType: String) -> String {
    switch mimeType.lowercased() {
    case "audio/mp4", "audio/x-m4a", "audio/m4a": return "public.mpeg-4-audio"
    case "audio/mpeg", "audio/mp3": return "public.mp3"
    case "audio/aac": return "public.aac-audio"
    default: return "public.mpeg-4-audio"
    }
}
contentInfoRequest.contentType = utiFromMimeType(mimeType)
```

## Testing

```swift
#Preview {
    SomeView()
        .modelContainer(for: [Playlist.self, Song.self, PlaylistSong.self], inMemory: true)
}
```

## Debug

- **Audio**: Check `AudioPlayerService.currentError`, verify background capability, check `NetworkMonitor.shared.isConnected` and `isServerReachable`
- **SwiftData**: Xcode inspector, verify `@Relationship` and delete rules, check `backendId` for synced playlists, song order preserved via `PlaylistSong.order`
- **UI**: SwiftUI inspector, verify `@State`/`@Observable` updates, main actor isolation
- **Backend Sync**: Check `PlaylistService.shared.error` for sync failures, verify `isLoading` state, check backend API responses. `PlaylistListView` syncs metadata only; `PlaylistDetailView` syncs individual playlist songs on navigation.
- **Downloads**: Check `DownloadService.shared.activeDownloads` for individual song progress, `playlistDownloadProgress` for aggregate playlist progress, `isDownloadingPlaylist(_:)` for playlist download state, `song.isDownloaded`/`song.localFileURL` for persisted local state, storage via `formattedStorageUsed()`, and `cleanupStalePaths(modelContext:)` if files were removed outside the app. Downloads persist in Documents directory across sessions. If songs show as not downloaded after sync, check that `PlaylistService` is reusing songs by `videoId`.
- **Certificates/mTLS**: Check `CertificateService.shared.isClientCertificateConfigured` for import status, `storedIdentities` for all saved certificates, `selectedIdentityId` for active selection, `certificateCommonName`/`certificateExpirationDate` for selected cert details, `isCertificateExpired`/`isCertificateExpiringSoon` for expiration warnings. For import failures, verify P12 password is correct and file is accessible. For connection failures with HTTPS, check `NetworkSessionDelegate` logs for trust evaluation errors. CA certificate is embedded in `CertificateService.embeddedCACertificatePEM`. If streaming fails on HTTPS, verify `MTLSResourceLoaderDelegate` is receiving requests (check for `mtls-stream://` scheme conversion).
- **Streaming**: Debug logs show the full streaming flow:
  1. `Content-Type: audio/mp4 → UTI: public.mpeg-4-audio` - MIME to UTI conversion
  2. `Content-Range: bytes 0-0/TOTAL, Content-Length: 1` - Initial probe request
  3. `Set contentLength from Content-Range: TOTAL` - Total file size extracted
  4. `Byte range supported: true` - Server supports partial content
  5. `Data request: offset=X, length=Y` - AVPlayer requesting data chunk
  6. `Received N bytes, responding to AVPlayer` - Data delivered to player
  7. `Player status: readyToPlay, duration: X.X` - AVPlayer ready
  8. `play() called, player exists: true, rate: 0.0` → `After play(), rate: 1.0` - Playback started
  
  If rate stays `0.0` after `play()`, AVPlayer is refusing to play (check for codec issues, corrupted data, or missing audio track). Check nginx logs for `206 Partial Content` responses and backend logs for streaming requests.
