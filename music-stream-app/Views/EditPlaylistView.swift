//
//  EditPlaylistView.swift
//  music-stream-app
//

import SwiftUI

struct EditPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var playlist: Playlist
    
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var artworkURL: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist Details") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Artwork") {
                    TextField("Artwork URL", text: $artworkURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    if !artworkURL.isEmpty {
                        AsyncImage(url: URL(string: artworkURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                name = playlist.name
                description = playlist.playlistDescription
                artworkURL = playlist.artworkURL ?? ""
            }
        }
    }
    
    private func saveChanges() {
        playlist.name = name
        playlist.playlistDescription = description
        playlist.artworkURL = artworkURL.isEmpty ? nil : artworkURL
        dismiss()
    }
}
