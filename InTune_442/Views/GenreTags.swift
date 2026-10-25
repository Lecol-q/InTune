import SwiftUI

struct GenreTags: View {
    let genres: [String]
    var body: some View {
        // Adaptive columns preserve readability for long, specific genre names.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Array(Set(genres)).sorted(), id: \.self) { genre in
                Text(genre)
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .foregroundStyle(.primary)
                    .background(InTuneBrand.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
