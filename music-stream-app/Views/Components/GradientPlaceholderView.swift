//
//  GradientPlaceholderView.swift
//  music-stream-app
//

import SwiftUI

struct GradientPlaceholderView: View {
    let iconName: String
    let iconSize: CGFloat
    let cornerRadius: CGFloat
    let gradientColors: [Color]
    
    init(
        iconName: String = "music.note.list",
        iconSize: CGFloat = 50,
        cornerRadius: CGFloat = 12,
        gradientColors: [Color]? = nil
    ) {
        self.iconName = iconName
        self.iconSize = iconSize
        self.cornerRadius = cornerRadius
        self.gradientColors = gradientColors ?? [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.3)]
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: iconSize))
                    .foregroundStyle(.white)
            }
    }
}
