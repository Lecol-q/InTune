import SwiftUI

struct GenreTags: View {
    let genres: [String]
    var compact = false
    var body: some View {
        // Adaptive columns preserve readability for long, specific genre names.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 112 : 130), alignment: .leading)], alignment: .leading, spacing: compact ? 5 : 8) {
            ForEach(Array(Set(genres)).sorted(), id: \.self) { genre in
                Text(genre)
                    .font(compact ? .caption2 : .caption)
                    .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 5 : 7)
                    .foregroundStyle(.primary)
                    .background(InTuneBrand.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
