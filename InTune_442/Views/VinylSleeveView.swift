import SwiftUI

/// A compact record sleeve treatment tied to actual preview playback, not autoplay.
struct VinylSleeveView: View {
    let artworkURL: URL?
    let isExpanded: Bool
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var accumulatedDegrees: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width / 1.65, geometry.size.height - 12)
            let inset = max(0, (geometry.size.width - side * 1.59) / 2)
            ZStack(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || reduceMotion)) { context in
                    record(size: side * 0.96)
                        .rotationEffect(.degrees(reduceMotion ? 0 : rotation(at: context.date)))
                }
                .offset(x: side * (isExpanded ? 0.63 : 0.06))

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(InTuneBrand.pink.opacity(0.10))
                    AsyncImage(url: artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "music.note")
                            .font(.largeTitle).foregroundStyle(InTuneBrand.pink)
                    }
                    .frame(width: side, height: side)
                    .clipped()
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 3, y: 4)
            }
            .frame(width: side * 1.59, height: geometry.size.height, alignment: .leading)
            .offset(x: inset)
            .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.86), value: isExpanded)
        }
        .aspectRatio(1.55, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear { if isPlaying { startedAt = Date() } }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                startedAt = Date()
            } else if let start = startedAt {
                accumulatedDegrees = (accumulatedDegrees + max(0, Date().timeIntervalSince(start)) * 36)
                    .truncatingRemainder(dividingBy: 360)
                startedAt = nil
            }
        }
    }

    private func rotation(at date: Date) -> Double {
        accumulatedDegrees + (startedAt.map { max(0, date.timeIntervalSince($0)) * 36 } ?? 0)
    }

    private func record(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.08))
            ForEach(0..<8) { index in
                Circle().stroke(.white.opacity(0.065), lineWidth: 0.7)
                    .padding(size * (0.065 + CGFloat(index) * 0.038))
            }
            Circle().trim(from: 0.04, to: 0.18)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: size * 0.055))
                .padding(size * 0.12)
            Circle().trim(from: 0.54, to: 0.65)
                .stroke(.white.opacity(0.07), style: StrokeStyle(lineWidth: size * 0.08))
                .padding(size * 0.18)
            Circle().fill(InTuneBrand.pink).frame(width: size * 0.31, height: size * 0.31)
            Circle().fill(Color(white: 0.94)).frame(width: size * 0.045, height: size * 0.045)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
    }
}
