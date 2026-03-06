//
//  AddSongView.swift
//  music-stream-app
//

import SwiftUI
import SwiftData

struct AddSongView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let playlist: Playlist
    
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var streamURL = ""
    @State private var artworkURL = ""
    @State private var duration: TimeInterval = 0
    @State private var durationString = "0:00"
    @State private var showInvalidURLAlert = false
    @State private var invalidURLMessage = ""
    
    private var isValidStreamURL: Bool {
        guard !streamURL.isEmpty else { return false }
        guard let url = URL(string: streamURL) else { return false }
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else { return false }
        return url.host != nil
    }
    
    private var isValidArtworkURL: Bool {
        guard !artworkURL.isEmpty else { return true }
        guard let url = URL(string: artworkURL) else { return false }
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else { return false }
        return url.host != nil
    }
    
    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !artist.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidStreamURL &&
        isValidArtworkURL
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Song Details") {
                    TextField("Title", text: $title)
                    TextField("Artist", text: $artist)
                    TextField("Album", text: $album)
                }
                
                Section {
                    TextField("https://example.com/song.mp4", text: $streamURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Stream URL")
                } footer: {
                    if !streamURL.isEmpty && !isValidStreamURL {
                        Label("Please enter a valid HTTP/HTTPS URL", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    TextField("Artwork URL (optional)", text: $artworkURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextField("0:00", text: $durationString)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .onChange(of: durationString) { _, newValue in
                                duration = parseDuration(newValue)
                            }
                    }
                } header: {
                    Text("Optional")
                } footer: {
                    if !artworkURL.isEmpty && !isValidArtworkURL {
                        Label("Please enter a valid HTTP/HTTPS URL", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSong()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }
    
    private func addSong() {
        let song = Song(
            title: title.trimmingCharacters(in: .whitespaces),
            artist: artist.trimmingCharacters(in: .whitespaces),
            album: album.trimmingCharacters(in: .whitespaces),
            duration: duration,
            streamURL: streamURL.trimmingCharacters(in: .whitespaces),
            artworkURL: artworkURL.isEmpty ? nil : artworkURL.trimmingCharacters(in: .whitespaces)
        )
        
        modelContext.insert(song)
        playlist.addSong(song)
        
        dismiss()
    }
    
    private func parseDuration(_ string: String) -> TimeInterval {
        let components = string.split(separator: ":")
        if components.count == 2,
           let minutes = Int(components[0]),
           let seconds = Int(components[1]) {
            return TimeInterval(minutes * 60 + seconds)
        }
        return 0
    }
}
