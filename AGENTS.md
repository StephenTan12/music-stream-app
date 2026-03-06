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
│   └── Playlist.swift             # SwiftData: many-to-many with Song
├── Services/
│   ├── AudioPlayerService.swift   # AVPlayer, queue, lock screen, session persistence
│   ├── NetworkMonitor.swift       # NWPathMonitor connectivity
│   └── SongService.swift          # Backend API client
├── Views/
│   ├── PlaylistListView.swift     # Playlist grid
│   ├── PlaylistDetailView.swift   # Playlist songs, play/shuffle controls
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

**New API Endpoint**: Add to `AppConfig.API.Endpoints`, create DTO if needed, add service method

**Modify Playback**: Edit `AudioPlayerService.swift`, all methods `@MainActor`, update published properties

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
```

## Testing

```swift
#Preview {
    SomeView()
        .modelContainer(for: [Playlist.self, Song.self], inMemory: true)
}
```

## Debug

- **Audio**: Check `AudioPlayerService.currentError`, verify background capability, check `NetworkMonitor.shared.isConnected`
- **SwiftData**: Xcode inspector, verify `@Relationship` and delete rules
- **UI**: SwiftUI inspector, verify `@State`/`@Observable` updates, main actor isolation
