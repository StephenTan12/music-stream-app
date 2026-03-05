# NOTE: ALL OF THIS IS VIBECODED

# Music Stream App

A SwiftUI-based iOS music streaming application that plays audio from remote .mp4 endpoints with full background playback support.

## Features

- **Playlist Management** - Create, edit, and delete playlists to organize your music
- **Audio Streaming** - Stream .mp4 files from remote URLs
- **Background Playback** - Continue listening when the app is minimized
- **Lock Screen Controls** - Play, pause, skip, and seek from the lock screen with artwork
- **Playback Modes** - Switch between linear and shuffle playback with visual feedback
- **Shuffle Playback** - Randomizes both playback order and starting song
- **Repeat Modes** - Off, repeat all, or repeat one track
- **Queue Management** - View and manage the current playback queue
- **Error Handling** - User-friendly error messages for playback failures
- **Network Monitoring** - Offline detection with visual indicator
- **Buffering Indicators** - Visual feedback during loading and buffering
- **Image Caching** - Efficient artwork caching to reduce network usage
- **Accessibility** - VoiceOver support with descriptive labels and hints

## Documentation

- **[AI_AGENT_GUIDE.md](AI_AGENT_GUIDE.md)** - Quick reference for AI agents and developers

## Project Structure

```
music-stream-app/
├── Models/
│   ├── Song.swift               # Song data model (SwiftData)
│   └── Playlist.swift           # Playlist data model (SwiftData)
├── Services/
│   ├── AudioPlayerService.swift # Core audio player (AVPlayer-based)
│   ├── NetworkMonitor.swift     # Network connectivity monitoring
│   └── SongService.swift        # Backend API client
├── Views/
│   ├── ContentView.swift        # Root view with navigation + mini player
│   ├── PlaylistListView.swift   # Grid of playlists
│   ├── PlaylistDetailView.swift # Songs within a playlist
│   ├── NowPlayingView.swift     # Full-screen player
│   ├── QueueView.swift          # Playback queue
│   ├── AllSongsView.swift       # Browse songs from API
│   ├── AddSongView.swift        # Add songs with URL validation
│   ├── EditPlaylistView.swift   # Edit playlist details
│   └── Components/
│       ├── MiniPlayerView.swift     # Bottom mini player bar
│       ├── SongRowView.swift        # Song list row
│       └── CachedAsyncImage.swift   # LRU-cached image loader
└── music_stream_appApp.swift    # App entry point
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

### AudioPlayerService

The core audio service handles:
- AVPlayer setup and management
- Background audio session configuration
- Remote command center (lock screen controls)
- Now Playing info with LRU-bounded artwork cache (20 images)
- Queue management with shuffle support
- Playback state observation with proper observer lifecycle (stored tokens, scoped cleanup)
- Audio interruption handling isolated from per-track resource cleanup
- Error handling with user-friendly messages
- Network connectivity checks before streaming
- Swift 6 strict concurrency compliance

### NetworkMonitor

Real-time network connectivity monitoring using `NWPathMonitor`:
- Detects WiFi, cellular, and wired connections
- Shows offline banner when disconnected
- Prevents playback attempts without internet

### CachedAsyncImage

Efficient image loading and caching:
- LRU cache with 50 image capacity
- Async loading with placeholder support
- Reduces network requests for repeated images

### Data Persistence

Uses SwiftData for local storage of:
- Playlists with metadata (nullify delete rule)
- Songs with streaming URLs
- Playlist-song relationships

## Background Audio

Background playback requires configuration in Xcode:

### Setup (Required)
1. Select the project in Xcode's navigator
2. Select the **music-stream-app** target
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability** and add **Background Modes**
5. Check **Audio, AirPlay, and Picture in Picture**

### How it works
- AVAudioSession configured with `.playback` category
- MPRemoteCommandCenter for lock screen controls
- MPNowPlayingInfoCenter with artwork display

## Accessibility

The app includes VoiceOver support:
- Descriptive labels for all interactive elements
- Play state announcements
- Track information read aloud
- Proper accessibility hints and traits

## License

MIT License
