# Music Stream App

A SwiftUI-based iOS music streaming application that plays audio from remote .mp4 endpoints with full background playback support.

## Features

- **Backend Playlist Sync** - Automatically sync playlists from backend API on app launch and pull-to-refresh
- **System Playlists** - Read-only system playlists (like "All Songs") shown prominently with star badge
- **Playlist Management** - View backend-synced playlists with full song details
- **Audio Streaming** - Stream .mp4 files from remote URLs
- **Offline Playback** - Download songs for offline listening with progress tracking
- **Background Playback** - Continue listening when the app is minimized
- **Control Center & Lock Screen** - Play, pause, skip, and seek from Control Center and Lock Screen with artwork display
- **Loading Screen** - Smooth dark loading screen on app launch
- **Playback Modes** - Switch between linear and shuffle playback with visual feedback
- **Shuffle Playback** - Randomizes both playback order and starting song
- **Repeat Modes** - Off, repeat all, or repeat one track
- **Queue Management** - View and manage the current playback queue
- **Error Handling** - User-friendly error messages for playback failures
- **Network Monitoring** - Offline and server status detection with nav bar icons
- **Buffering Indicators** - Visual feedback during loading and buffering
- **Session Persistence** - Resume playback where you left off after app restart
- **Image Caching** - Efficient artwork caching to reduce network usage
- **Dark Mode** - Full dark mode UI configured at system level
- **Accessibility** - VoiceOver support with descriptive labels and hints
- **Structured Logging** - Uses `os.Logger` for diagnostics

## Documentation

- **[AGENTS.md](AGENTS.md)** - Quick reference for AI agents and developers

## Project Structure

```
music-stream-app/
├── Info.plist                   # App configuration (background modes, dark mode, launch screen)
├── Assets.xcassets/
│   └── LaunchScreenBackground.colorset/  # Dark launch screen color
├── Config/
│   └── AppConfig.swift          # Centralized app configuration constants
├── Models/
│   ├── Song.swift               # Song data model (SwiftData)
│   ├── Playlist.swift           # Playlist data model with backend sync fields (SwiftData)
│   └── PlaylistSong.swift       # Join model for ordered playlist-song relationships
├── Services/
│   ├── AudioPlayerService.swift # Core audio player (AVPlayer-based)
│   ├── DownloadService.swift    # Offline download management
│   ├── NetworkMonitor.swift     # Network connectivity monitoring
│   ├── SongService.swift        # Backend song API client
│   └── PlaylistService.swift    # Backend playlist API client with sync
├── ContentView.swift            # Root view with navigation, mini player, and loading screen
├── Views/
│   ├── PlaylistListView.swift   # Backend-synced playlists with pull-to-refresh
│   ├── PlaylistDetailView.swift # Songs within a playlist, scroll-aware nav title (read-only for system playlists)
│   ├── NowPlayingView.swift     # Full-screen player
│   ├── QueueView.swift          # Playback queue
│   ├── AllSongsView.swift       # Browse songs from API
│   ├── AddSongView.swift        # Add songs with URL validation
│   ├── EditPlaylistView.swift   # Edit playlist details
│   └── Components/
│       ├── MiniPlayerView.swift          # Bottom mini player bar
│       ├── SongRowView.swift             # Song list row with context menu
│       ├── DownloadStorageView.swift     # Download management and storage stats
│       ├── CachedAsyncImage.swift        # LRU-cached image loader
│       └── GradientPlaceholderView.swift # Reusable gradient placeholder
└── music_stream_appApp.swift    # App entry point with model container setup
```

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+ (Swift 6 compatible)

## Setup

1. Open `music-stream-app.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run (Cmd+R)

The app includes mock data that loads automatically on first launch with sample MP4 files from Google's public test video bucket.

## Configuration

App-wide settings are centralized in `Config/AppConfig.swift`:

| Setting | Default | Description |
|---------|---------|-------------|
| `API.baseURL` | `http://localhost:8000` | Backend API base URL |
| `API.defaultPageSize` | `20` | Songs per page for pagination |
| `API.Endpoints.getPlaylists()` | `/playlists` | Fetch all playlists endpoint |
| `API.Endpoints.getPlaylist(id)` | `/playlists/{id}` | Fetch playlist with songs endpoint |
| `Cache.maxImageCacheSize` | `50` | Max images in LRU cache |
| `Cache.maxArtworkCacheSize` | `20` | Max artwork images for Now Playing |
| `Playback.seekPollingIterations` | `10` | Seek UI sync iterations |
| `Playback.seekPollingIntervalMs` | `50` | Seek polling interval (ms) |
| `Downloads.directory` | `Downloads` | Downloaded audio files directory |
| `Downloads.artworkDirectory` | `Downloads/Artwork` | Downloaded artwork directory |

## Adding Songs

When adding songs to a playlist, provide:

| Field | Required | Description |
|-------|----------|-------------|
| Title | Yes | Song title |
| Artist | Yes | Artist name |
| Stream URL | Yes | Valid HTTP/HTTPS URL to .mp4 file |
| Album | No | Album name |
| Artwork URL | No | Valid HTTP/HTTPS URL to artwork image |
| Duration | No | Length in m:ss format |

URLs are validated before saving - invalid URLs will show an inline error message.

## Architecture

### AppConfig

Centralized configuration for the entire app:
- API endpoints and pagination settings
- Cache size limits for images and artwork
- Playback timing constants

### AudioPlayerService

The core audio service handles:
- AVPlayer setup and management
- Background audio session configuration
- Remote command center (lock screen controls)
- Now Playing info with LRU-bounded artwork cache
- Queue management with shuffle support
- Playback state observation with proper observer lifecycle (stored tokens, scoped cleanup)
- Audio interruption handling isolated from per-track resource cleanup
- Error handling with user-friendly messages
- Network connectivity checks before streaming
- **Offline playback** - Prefers local files when available, falls back to streaming
- Playback state persistence across app sessions (including local file paths)
- Swift 6 strict concurrency compliance

### DownloadService

Offline download management:
- Downloads songs and artwork to Documents directory for persistent storage
- Reuses existing downloaded files to prevent duplicates
- Progress tracking for individual songs and playlists
- Cancel in-progress downloads
- Remove individual or all downloads
- Storage usage statistics with formatted display
- Uses URLSession with delegate for progress updates
- Singleton pattern with `@MainActor` isolation
- Heavy file moves, writes, deletes, and storage scans run off the main actor
- Automatic cleanup of stale paths on app startup and when opening download management
- Preserves download information across app sessions

### PlaylistService

Backend playlist synchronization service:
- Fetches playlists from backend API (`GET /playlists`)
- Fetches full playlist details with songs (`GET /playlists/{id}`)
- Syncs to local SwiftData storage
- Updates existing playlists and songs to preserve download information
- Reuses songs by `videoId` to maintain download paths across syncs
- Automatic sync on app launch and manual pull-to-refresh
- Handles system playlists (read-only, shown prominently)
- Cleans up orphaned songs without downloads
- Snake_case to camelCase JSON decoding
- Typed error handling with user-friendly messages

### NetworkMonitor

Real-time network connectivity and server reachability monitoring using `NWPathMonitor`:
- Detects WiFi, cellular, and wired connections
- Tracks server reachability (`isServerReachable`) based on API response success/failure
- Connection status shown via nav bar icons:
  - `wifi.slash` (gray) - Device is offline
  - `exclamationmark.icloud` (orange) - Device online but server unreachable
- Prevents streaming playback attempts without internet
- Used as a preflight guard so network-dependent services can skip requests while offline

### CachedAsyncImage

Efficient image loading and caching:
- LRU cache with configurable capacity
- Async loading with placeholder support
- Reduces network requests for repeated images
- Skips remote image fetches entirely while offline
- Debug logging for load failures

### GradientPlaceholderView

Reusable placeholder component:
- Configurable gradient colors, icon, and corner radius
- Used throughout the app for missing artwork

### Data Persistence

Uses SwiftData for local storage of:
- Playlists with metadata and backend sync fields (backendId, isSystem, lastSyncedAt)
- Songs with streaming URLs
- Playlist-song relationships (nullify delete rule)
- Backend playlists synced automatically on app launch

Uses UserDefaults for playback state persistence:
- Current song and queue (including local file paths)
- Playback position
- Shuffle and repeat mode settings
- Automatically restored on app launch

Uses Documents directory for offline downloads:
- Downloaded audio files (`Downloads/`)
- Downloaded artwork (`Downloads/Artwork/`)
- Persists across app sessions
- Stale paths are reconciled on startup before UI uses persisted download metadata

## Background Audio & Control Center

Background playback and Control Center/Lock Screen controls are pre-configured via Info.plist.

### Configuration (Already Set Up)
The following are configured in `Info.plist`:
- `UIBackgroundModes` - Audio background mode enabled
- `UILaunchScreen` - Dark launch screen with custom background color
- `UIUserInterfaceStyle` - System-wide dark mode

### How it works
- AVAudioSession configured with `.playback` category
- MPRemoteCommandCenter for Control Center and Lock Screen controls
- MPNowPlayingInfoCenter displays song title, artist, album, artwork, and playback progress
- Controls appear in Control Center (swipe down) and on Lock Screen when audio is playing

## Offline Playback

Download songs for offline listening:

### Downloading
- **Individual songs** - Long press on any song and select "Download" from the context menu
- **Entire playlists** - Use the download button in the playlist toolbar
- **Progress tracking** - Visual progress indicators during downloads
- **Cancel downloads** - Stop in-progress downloads via context menu
- **Duplicate prevention** - Automatically reuses existing downloaded files

### Managing Downloads
- **Storage view** - Access via the download icon in the playlist list toolbar
- **Storage statistics** - See total space used and number of downloaded songs
- **Remove downloads** - Delete individual songs via context menu or clear all downloads
- **Downloaded badge** - Small download icon appears next to artist name for downloaded songs
- **Persistent storage** - Downloads persist across app restarts and are stored in Documents directory
- **Stale file recovery** - Missing files are cleared from SwiftData during cleanup so the UI stays in sync

### Playback Behavior
- Downloaded songs play from local storage without network
- Playback automatically uses local files when available, including artwork in Now Playing and on the lock screen
- Session persistence includes local file paths for seamless restore
- Restored playback does not attempt remote stream URLs when offline
- Lock-screen artwork fetch is skipped when offline (uses local/cached artwork only)
- Downloads persist across app sessions in Documents directory
- Stale download paths are cleaned up automatically on app startup
- Download-state rendering avoids synchronous `FileManager` checks in SwiftUI rows

### Offline Network Guardrails
- When disconnected (no WiFi/cellular, including airplane mode), the app short-circuits network calls before `URLSession` is used
- `SongService` skips paginated song fetches while offline (silent fail, no error alerts)
- `PlaylistService` skips playlist list/detail sync requests while offline (silent fail, no error alerts)
- On server errors, services set `NetworkMonitor.shared.isServerReachable = false` to show the server status icon
- `CachedAsyncImage` skips remote artwork fetches while offline
- `DownloadService` blocks new downloads while offline and avoids artwork requests during disconnected states
- `AudioPlayerService` skips remote artwork requests and restored streaming attempts while offline

## Error Handling

The app gracefully handles errors:
- **Data initialization failures** - Shows a user-friendly error view instead of crashing
- **Playback errors** - Displays error alerts with skip-to-next option
- **Image loading failures** - Falls back to gradient placeholders with debug logging
- **Network issues** - Detects offline state and prevents failed stream attempts
- **Download failures** - Shows error alerts when downloads fail

## Accessibility

The app includes VoiceOver support:
- Descriptive labels for all interactive elements
- Play state announcements
- Track information read aloud
- Proper accessibility hints and traits

## License

MIT License
