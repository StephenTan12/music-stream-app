//
//  SongService.swift
//  music-stream-app
//

import Foundation
import Combine

struct PaginatedSongsResponse: Codable {
    let songs: [SongDTO]
    let total: Int
    let page: Int
    let pageSize: Int
    let totalPages: Int
}

struct SongDTO: Codable {
    let id: String
    let title: String
    let artist: String?
    let duration: Int
    let tags: [String]
    let fulltitle: String
    let filesize: Int
    
    enum CodingKeys: String, CodingKey {
        case id, title, artist, duration, tags, fulltitle, filesize
    }
    
    func toSong() -> Song {
        Song(
            videoId: id,
            title: title,
            artist: artist ?? "Unknown Artist",
            duration: TimeInterval(duration)
        )
    }
}

enum SongServiceError: LocalizedError {
    case invalidURL
    case networkError(String)
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        }
    }
}

@MainActor
class SongService: ObservableObject {
    static let shared = SongService()
    
    @Published var songs: [Song] = []
    @Published var isLoading = false
    @Published var error: SongServiceError?
    @Published var currentPage = 1
    @Published var totalPages = 1
    
    var hasMorePages: Bool { currentPage < totalPages }
    
    private let pageSize = AppConfig.API.defaultPageSize
    
    private init() {}
    
    func fetchSongs(page: Int = 1, reset: Bool = false) async {
        guard !isLoading else { return }
        
        if reset {
            songs = []
            currentPage = 1
        }
        
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        let urlString = AppConfig.API.Endpoints.getSongs(page: page, pageSize: pageSize)
        guard let url = URL(string: urlString) else {
            error = .invalidURL
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                error = .networkError("Server returned an error")
                return
            }
            
            let decoder = JSONDecoder()
            let paginatedResponse = try decoder.decode(PaginatedSongsResponse.self, from: data)
            
            let newSongs = paginatedResponse.songs.map { $0.toSong() }
            
            if reset || page == 1 {
                songs = newSongs
            } else {
                songs.append(contentsOf: newSongs)
            }
            
            currentPage = paginatedResponse.page
            totalPages = paginatedResponse.totalPages
            
        } catch let decodingError as DecodingError {
            error = .decodingError(decodingError.localizedDescription)
        } catch {
            self.error = .networkError(error.localizedDescription)
        }
    }
    
    func loadNextPage() async {
        guard currentPage < totalPages else { return }
        await fetchSongs(page: currentPage + 1)
    }
    
    func refresh() async {
        await fetchSongs(page: 1, reset: true)
    }
}
