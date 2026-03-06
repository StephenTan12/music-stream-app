//
//  CachedAsyncImage.swift
//  music-stream-app
//

import SwiftUI
import UIKit
import os

private let logger = Logger(subsystem: "com.music-stream-app", category: "ImageCache")

actor ImageCache {
    static let shared = ImageCache()
    
    private var cache: [URL: Image] = [:]
    private let maxCacheSize = AppConfig.Cache.maxImageCacheSize
    private var accessOrder: [URL] = []
    
    func image(for url: URL) -> Image? {
        if let image = cache[url] {
            if let index = accessOrder.firstIndex(of: url) {
                accessOrder.remove(at: index)
                accessOrder.append(url)
            }
            return image
        }
        return nil
    }
    
    func setImage(_ image: Image, for url: URL) {
        if cache.count >= maxCacheSize, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
        
        cache[url] = image
        accessOrder.append(url)
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var cachedImage: Image?
    @State private var isLoading = false
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = cachedImage {
                content(image)
            } else {
                placeholder()
                    .task(id: url) {
                        await loadImage()
                    }
            }
        }
    }
    
    private func loadImage() async {
        guard let url = url else { return }
        
        if let cached = await ImageCache.shared.image(for: url) {
            cachedImage = cached
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let uiImage = UIImage(data: data) {
                let image = Image(uiImage: uiImage)
                await ImageCache.shared.setImage(image, for: url)
                await MainActor.run {
                    cachedImage = image
                }
            }
        } catch {
            logger.debug("Image load failed for \(url.absoluteString): \(error.localizedDescription)")
        }
    }
}
