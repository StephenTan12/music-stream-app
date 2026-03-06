# Music Stream App

A SwiftUI-based iOS music streaming application that plays audio from remote .mp4 endpoints with full background playback support.

## Features

- **Backend Playlist Sync** - Automatically sync playlists from backend API on app launch and pull-to-refresh
- **System Playlists** - Read-only system playlists (like "All Songs") shown prominently with star badge
- **Playlist Management** - View backend-synced playlists with full song details
- **Audio Streaming** - Stream .mp4 files from remote URLs
- **Background Playback** - Continue listening when the app is minimized
- **Control Center & Lock Screen** - Play, pause, skip, and seek from Control Center and Lock Screen with artwork display
- **Loading Screen** - Smooth dark loading screen on app launch
- **Playback Modes** - Switch between linear and shuffle playback with visual feedback
- **Shuffle Playback** - Randomizes both playback order and starting song
- **Repeat Modes** - Off, repeat all, or repeat one track
- **Queue Management** - View and manage the current playback queue
- **Error Handling** - User-friendly error messages for playback failures
- **Network Monitoring** - Offline detection with visual indicator
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
│       ├── MiniPlayerView.swift        # Bottom mini player bar
│       ├── SongRowView.swift           # Song list row
│       ├── CachedAsyncImage.swift      # LRU-cached image loader
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
- Playback state persistence across app sessions
- Swift 6 strict concurrency compliance

### PlaylistService

Backend playlist synchronization service:
- Fetches playlists from backend API (`GET /playlists`)
- Fetches full playlist details with songs (`GET /playlists/{id}`)
- Syncs to local SwiftData storage
- Replaces local playlists with backend data on each sync
- Automatic sync on app launch and manual pull-to-refresh
- Handles system playlists (read-only, shown prominently)
- Snake_case to camelCase JSON decoding
- Typed error handling with user-friendly messages

### NetworkMonitor

Real-time network connectivity monitoring using `NWPathMonitor`:
- Detects WiFi, cellular, and wired connections
- Shows offline banner when disconnected
- Prevents playback attempts without internet

### CachedAsyncImage

Efficient image loading and caching:
- LRU cache with configurable capacity
- Async loading with placeholder support
- Reduces network requests for repeated images
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
- Current song and queue
- Playback position
- Shuffle and repeat mode settings
- Automatically restored on app launch

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

## Error Handling

The app gracefully handles errors:
- **Data initialization failures** - Shows a user-friendly error view instead of crashing
- **Playback errors** - Displays error alerts with skip-to-next option
- **Image loading failures** - Falls back to gradient placeholders with debug logging
- **Network issues** - Detects offline state and prevents failed stream attempts

## Accessibility

The app includes VoiceOver support:
- Descriptive labels for all interactive elements
- Play state announcements
- Track information read aloud
- Proper accessibility hints and traits

## License

MIT License
