# AGENTS.md

> Swift 5.9+ | SwiftUI + SwiftData | iOS 17.0+ | Swift 6 concurrency

Music streaming app: .mp4 audio streaming, playlist management, background playback, lock screen controls, session persistence, dark mode UI.

## Structure

```
music-stream-app/
├── music_stream_appApp.swift      # Entry point, SwiftData container
├── ContentView.swift              # Root: navigation, mini player, loading screen, offline banner
├── Info.plist                     # Background modes, dark mode, launch screen
├── Config/AppConfig.swift         # API URLs, cache sizes, timing constants
├── Models/
│   ├── Song.swift                 # SwiftData: title, artist, streamURL, artworkURL, etc.
│   ├── Playlist.swift             # SwiftData: ordered songs via PlaylistSong join, backend sync fields
│   └── PlaylistSong.swift         # SwiftData: join model with order field for song ordering
├── Services/
│   ├── AudioPlayerService.swift   # AVPlayer, queue, lock screen, session persistence
│   ├── NetworkMonitor.swift       # NWPathMonitor connectivity
│   ├── SongService.swift          # Backend song API client
│   └── PlaylistService.swift     # Backend playlist API client with sync
├── Views/
│   ├── PlaylistListView.swift     # Backend-synced playlists, pull-to-refresh, system playlist badges
│   ├── PlaylistDetailView.swift   # Playlist songs, play/shuffle controls, scroll-aware nav title, read-only for system playlists
│   ├── AllSongsView.swift         # API songs browse, play/shuffle controls
│   ├── NowPlayingView.swift       # Full player, seek, queue access
│   ├── QueueView.swift            # Playback queue
│   ├── AddSongView.swift          # URL validation
│   ├── EditPlaylistView.swift     # Playlist editing
│   └── Components/
│       ├── MiniPlayerView.swift          # Bottom player bar
│       ├── SongRowView.swift             # Song list row
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
| **State** | `@State` (local), `@Observable` (services), `@Query` (SwiftData), `@Bindable` (binding) |
| **Concurrency** | All services `@MainActor`, use `async/await`, no callbacks |
| **Errors** | Typed enums + `LocalizedError`, handle at UI boundary |
| **Logging** | `os.Logger` not `print` |
| **Persistence** | SwiftData (models), UserDefaults (playback state) |

## Common Tasks

**New View**: Create in `Views/`, add nav destination in `ContentView`, use `AudioPlayerService.shared`

**New Model Property**: Edit model file, SwiftData auto-migrates, update UI

**New API Endpoint**: Add to `AppConfig.API.Endpoints`, create DTO if needed, add service method, configure `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` for backend snake_case

**Modify Playback**: Edit `AudioPlayerService.swift`, all methods `@MainActor`, update published properties

**Sync Backend Data**: Use `PlaylistService.shared.syncPlaylistsToLocal(modelContext:)` to fetch and sync playlists from backend

**Add Song to Playlist**: Use `playlist.addSong(song)` to add songs with proper ordering, use `playlist.removeSong(at:)` to remove, use `playlist.moveSong(from:to:)` to reorder

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

// ❌ Compare songs by UUID (fails after app restart - restored songs have same UUID but different instance)
audioPlayer.currentSong?.id == song.id

// ✅ Compare songs by videoId first, fallback to id
if let currentVideoId = audioPlayer.currentSong?.videoId, let songVideoId = song.videoId {
    return currentVideoId == songVideoId
}
return audioPlayer.currentSong?.id == song.id
```

## Testing

```swift
#Preview {
    SomeView()
        .modelContainer(for: [Playlist.self, Song.self, PlaylistSong.self], inMemory: true)
}
```

## Debug

- **Audio**: Check `AudioPlayerService.currentError`, verify background capability, check `NetworkMonitor.shared.isConnected`
- **SwiftData**: Xcode inspector, verify `@Relationship` and delete rules, check `backendId` for synced playlists, song order preserved via `PlaylistSong.order`
- **UI**: SwiftUI inspector, verify `@State`/`@Observable` updates, main actor isolation
- **Backend Sync**: Check `PlaylistService.shared.error` for sync failures, verify `isLoading` state, check backend API responses
