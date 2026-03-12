# AGENTS.md

> Swift 5.9+ | SwiftUI + SwiftData | iOS 17.0+ | Swift 6 concurrency

Music streaming app: .mp4 audio streaming, playlist management, background playback, lock screen controls, session persistence, offline downloads, dark mode UI.

## Structure

```
music-stream-app/
├── music_stream_appApp.swift      # Entry point, SwiftData container
├── ContentView.swift              # Root: navigation, mini player, loading screen
├── Info.plist                     # Background modes, dark mode, launch screen
├── Config/AppConfig.swift         # API URLs, cache size, timing constants, download paths
├── Models/
│   ├── Song.swift                 # SwiftData: title, artist, streamURL, artworkURL, download state
│   ├── Playlist.swift             # SwiftData: ordered songs via PlaylistSong join, backend sync fields (totalSongs, totalDuration)
│   └── PlaylistSong.swift         # SwiftData: join model with order field for song ordering
├── Services/
│   ├── AudioPlayerService.swift   # AVPlayer, queue, lock screen, session persistence, offline playback
│   ├── DownloadService.swift      # Offline downloads, progress tracking, storage management
│   ├── NetworkMonitor.swift       # NWPathMonitor connectivity + server reachability
│   ├── SongService.swift          # Backend song API client
│   └── PlaylistService.swift      # Backend playlist API client with sync
├── Views/
│   ├── PlaylistListView.swift     # Playlist list with metadata sync, pull-to-refresh, system playlist badges, connection status icons
│   ├── PlaylistDetailView.swift   # Playlist songs (synced on navigation), play/shuffle controls, scroll-aware nav title
│   ├── AllSongsView.swift         # API songs browse, play/shuffle controls
│   ├── NowPlayingView.swift       # Full player, seek, queue access
│   ├── QueueView.swift            # Playback queue
│   ├── AddSongView.swift          # URL validation
│   ├── EditPlaylistView.swift     # Playlist editing
│   └── Components/
│       ├── MiniPlayerView.swift          # Bottom player bar
│       ├── SongRowView.swift             # Song list row with context menu (download via long press)
│       ├── DownloadStorageView.swift     # Download management, storage stats
│       ├── CachedAsyncImage.swift        # LRU image cache
│       └── GradientPlaceholderView.swift # Missing artwork placeholder
└── Assets.xcassets/               # App assets, launch screen color
```

## Patterns

### Service Access (singletons, @MainActor)
```swift
@State private var audioPlayer = AudioPlayerService.shared
@State private var networkMonitor = NetworkMonitor.shared
@State private var playlistService = PlaylistService.shared
@State private var downloadService = DownloadService.shared
@State private var songService = SongService.shared
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
| **Persistence** | SwiftData (models), UserDefaults (playback state), Documents (downloads) |

## Common Tasks

**New View**: Create in `Views/`, add nav destination in `ContentView`, use `AudioPlayerService.shared`

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

**Download Playlist**: Use `DownloadService.shared.downloadPlaylist(playlist)` to download all songs in a playlist

**Remove Downloads**: Use `DownloadService.shared.removeSongDownload(song)` for single song, `removeAllDownloads(modelContext:)` for all

**Cleanup Stale Paths**: Use `DownloadService.shared.cleanupStalePaths(modelContext:)` to clear `localFilePath`/`localArtworkPath` on songs whose files were deleted. Runs automatically on app startup via `ContentView.task`.

## Key Implementation Details

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
- **Downloads**: Check `DownloadService.shared.activeDownloads` for progress, `song.isDownloaded`/`song.localFileURL` for persisted local state, storage via `formattedStorageUsed()`, and `cleanupStalePaths(modelContext:)` if files were removed outside the app. Downloads persist in Documents directory across sessions. If songs show as not downloaded after sync, check that `PlaylistService` is reusing songs by `videoId`.
