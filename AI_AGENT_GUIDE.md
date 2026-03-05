# AI Agent Quick Start Guide

This guide provides a concise overview for AI agents working with this codebase. For detailed documentation, see the README files in each directory.

## Quick Facts

- **Language**: Swift 5.9+ (Swift 6 compatible)
- **Framework**: SwiftUI + SwiftData
- **Platform**: iOS 17.0+
- **Architecture**: Service-oriented with singleton services
- **Concurrency**: Strict Swift 6 concurrency (@MainActor)
- **State Management**: @Observable services, @Query for data

## Project Overview

A music streaming iOS app that:
- Streams .mp4 audio from remote URLs
- Manages playlists with SwiftData persistence
- Provides background playback with lock screen controls
- Includes network monitoring and error handling

## Key Files to Know

### Entry Point
- `music_stream_appApp.swift` - App initialization, SwiftData container setup

### Core Services (Singletons)
- `AudioPlayerService.swift` - Audio playback, queue management, lock screen controls
- `NetworkMonitor.swift` - Real-time network connectivity monitoring
- `SongService.swift` - Backend API client for fetching songs

### Data Models
- `Song.swift` - SwiftData model for songs (title, artist, streamURL, etc.)
- `Playlist.swift` - SwiftData model for playlists (many-to-many with Song)

### Main Views
- `ContentView.swift` - Root view with navigation, mini player, offline banner
- `PlaylistListView.swift` - Grid of all playlists
- `PlaylistDetailView.swift` - Songs in a playlist with play/shuffle controls (active state styling)
- `AllSongsView.swift` - Browse songs from API with play/shuffle controls (active state styling)
- `NowPlayingView.swift` - Full-screen player with seek, controls, queue access
- `QueueView.swift` - Playback queue
- `AddSongView.swift` - Add songs with URL validation
- `EditPlaylistView.swift` - Edit playlist details

### Reusable Components
- `MiniPlayerView.swift` - Persistent bottom player bar
- `SongRowView.swift` - Reusable song list row with artwork
- `CachedAsyncImage.swift` - LRU-cached image loading component

## Common Tasks

### Adding a New View
1. Create SwiftUI view file in `Views/`
2. Add navigation destination in `ContentView` if needed
3. Access services via `@State private var audioPlayer = AudioPlayerService.shared`
4. Access SwiftData via `@Query` or `@Environment(\.modelContext)`

### Modifying Playback Logic
1. Edit `AudioPlayerService.swift`
2. All methods are `@MainActor` isolated
3. Update published properties for UI reactivity
4. Handle cleanup in `cleanup()` method
5. Note: Shuffle mode starts with a random song (uses `randomElement()` in views)

### Adding a New Model Property
1. Edit model file (`Song.swift` or `Playlist.swift`)
2. SwiftData handles migration automatically
3. Update any computed properties if needed
4. Update UI to display new property

### Adding a New API Endpoint
1. Add endpoint to `APIConfig.Endpoints` in `AudioPlayerService.swift`
2. Create DTO struct if needed (see `SongDTO` in `SongService.swift`)
3. Add service method to fetch/post data
4. Handle errors with typed error enums

## Code Patterns

### Service Access
```swift
@State private var audioPlayer = AudioPlayerService.shared
@State private var networkMonitor = NetworkMonitor.shared
```

### SwiftData Queries
```swift
@Query(sort: \Playlist.createdAt, order: .reverse) 
private var playlists: [Playlist]

@Environment(\.modelContext) private var modelContext
```

### Navigation
```swift
NavigationStack {
    ListView()
        .navigationDestination(for: Model.self) { item in
            DetailView(item: item)
        }
}
```

### Modal Presentation
```swift
.sheet(isPresented: $showSheet) { SheetView() }
.fullScreenCover(isPresented: $showCover) { CoverView() }
```

### Button State Tracking
```swift
@State private var selectedPlayMode: PlayMode? = nil

enum PlayMode {
    case play
    case shuffle
}

// In button action
Button {
    selectedPlayMode = .play
    playAll(shuffle: false)
} label: {
    // Dynamic styling based on state
    .background(selectedPlayMode == .play ? Color.blue : Color.gray.opacity(0.2))
    .foregroundStyle(selectedPlayMode == .play ? .white : .primary)
}
.buttonStyle(.plain)
```

### Async Operations
```swift
Task {
    await service.fetchData()
}

// Background work
Task.detached {
    let result = await heavyOperation()
    await MainActor.run {
        self.updateUI(result)
    }
}
```

## Important Conventions

### Naming
- Views: `SomethingView.swift`
- Models: `Something.swift`
- Services: `SomethingService.swift`
- Components: Descriptive names in `Views/Components/`

### State Management
- Use `@State` for view-local state
- Use `@Observable` for shared service state
- Use `@Query` for SwiftData queries
- Use `@Bindable` for two-way binding to models

### Concurrency
- All services are `@MainActor` isolated
- Use `async/await` for asynchronous work
- No completion handlers or callbacks
- Structured concurrency with `Task`

### Error Handling
- Use typed error enums conforming to `LocalizedError`
- Provide user-friendly error messages
- Handle errors at UI boundary (alerts, inline messages)

## Architecture Decisions

### Why Singletons?
Services use singletons because:
- Shared state (audio player must be consistent)
- System resources (one AVPlayer instance)
- Simplicity (no dependency injection needed)

### Why SwiftData?
- Modern Swift-first API
- Automatic schema generation
- Native SwiftUI integration with `@Query`
- Less boilerplate than Core Data

### Why @Observable?
- More efficient than `ObservableObject`
- No `@Published` boilerplate needed
- Better performance for SwiftUI

## Common Pitfalls

### ❌ Don't Do This
```swift
// Don't access services from background threads
Task.detached {
    AudioPlayerService.shared.play() // ❌ Not main-actor-isolated
}

// Don't create multiple service instances
let player = AudioPlayerService() // ❌ Use .shared

// Don't use completion handlers
func fetchData(completion: @escaping (Data) -> Void) // ❌ Use async/await
```

### ✅ Do This Instead
```swift
// Access services on main actor
Task { @MainActor in
    AudioPlayerService.shared.play() // ✅
}

// Use singleton
let player = AudioPlayerService.shared // ✅

// Use async/await
func fetchData() async -> Data // ✅
```

## Testing

### SwiftUI Previews
```swift
#Preview {
    SomeView()
        .modelContainer(for: [Playlist.self, Song.self], inMemory: true)
}
```

### Mock Data
Create sample models for testing:
```swift
let sampleSong = Song(
    title: "Test Song",
    artist: "Test Artist",
    streamURL: "https://example.com/audio.mp4"
)
```

## Debugging Tips

### Audio Issues
- Check `AudioPlayerService.currentError` for playback errors
- Verify background audio capability is enabled in Xcode
- Check network connectivity with `NetworkMonitor.shared.isConnected`

### SwiftData Issues
- Use Xcode's SwiftData inspector
- Check model relationships are properly configured
- Verify `@Relationship` and delete rules

### UI Issues
- Use SwiftUI inspector in Xcode
- Check `@State` and `@Observable` updates
- Verify main actor isolation for UI updates

## Quick Reference

### File Locations
```
Models:     music-stream-app/Models/
Services:   music-stream-app/Services/
Views:      music-stream-app/Views/
Components: music-stream-app/Views/Components/
```

### Key Classes
```
AudioPlayerService - Playback engine
NetworkMonitor     - Connectivity
SongService        - API client
Song               - Song model
Playlist           - Playlist model
```

### Important Enums
```
PlaybackMode  - Linear, Shuffle (shuffle starts with random song)
RepeatMode    - None, All, One
PlaybackError - Audio errors
PlayMode      - UI state for play/shuffle button selection
```

## Next Steps

1. **Read ARCHITECTURE.md** for high-level design overview
2. **Browse directory READMEs** for detailed component documentation
3. **Run the app** to understand user flows
4. **Check SwiftUI previews** for quick component testing

## Getting Help

- **Architecture questions**: See `ARCHITECTURE.md`
- **Service details**: See `Services/README.md`
- **View structure**: See `Views/README.md`
- **Component usage**: See `Views/Components/README.md`
- **Model relationships**: See `Models/README.md`

## Summary

This is a well-structured SwiftUI app with:
- ✅ Modern Swift 6 concurrency
- ✅ SwiftData persistence
- ✅ Service-oriented architecture
- ✅ Comprehensive error handling
- ✅ Full accessibility support
- ✅ Background audio playback
- ✅ Network monitoring
- ✅ Efficient caching

The codebase follows iOS best practices and is designed for maintainability and extensibility.
