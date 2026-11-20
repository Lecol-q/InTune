import SwiftUI

struct MusicCardView: View {
    @ObservedObject private var demo = DemoSession.shared
    @ObservedObject private var swipeFeedback = CardSwipeFeedback.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ScrollView {
                VStack(spacing: 10) {
                    if let person = demo.remaining.first {
                        DemoBadge()
                        HStack(alignment: .firstTextBaseline) {
                            Text("Find your frequency").font(.title3.bold())
                            Spacer()
                            Text("\(demo.remaining.count) left").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            if let track = person.taste.showcaseTrack {
                                SongAlbumArtwork(song: .selected(track))
                            } else {
                                MusicArtwork(title: "InTune Sessions")
                            }
                            HStack(spacing: 8) {
                                Text("\(person.name), \(person.age)").font(.title2.bold()).lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "headphones").foregroundStyle(InTuneBrand.pink)
                            }
                            Text(person.bio).font(.subheadline).lineLimit(3)
                            if let song = person.taste.showcaseTrack {
                                HStack(spacing: 7) {
                                    Image(systemName: "music.note").foregroundStyle(InTuneBrand.pink)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(song.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(song.artists.map(\.name).joined(separator: ", "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            Text(person.taste.summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            let shared = demo.sharedGenres(with: person)
                            Label(shared.isEmpty ? "A new sound to explore" : "You share: " + shared.prefix(3).joined(separator: ", "),
                                  systemImage: "waveform.path")
                                .font(.caption).foregroundStyle(InTuneBrand.pink).lineLimit(1)
                            Text("Photos stay hidden before a mutual match.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(minHeight: max(340, geometry.size.height - 185), alignment: .topLeading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(InTuneBrand.pink.opacity(0.2)))
                        .shadow(color: InTuneBrand.pink.opacity(0.1), radius: 12, y: 5)
                        .id(person.id)
                        .horizontalCardSwipe { like in
                            demo.decide(person, like: like)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 14) {
                            Button { demo.decide(person, like: false) } label: {
                                Label("Skip", systemImage: "xmark").frame(maxWidth: .infinity)
                            }.tint(.secondary).buttonStyle(.bordered)
                            Button { demo.decide(person, like: true) } label: {
                                Label("Like", systemImage: "heart.fill").frame(maxWidth: .infinity)
                            }.tint(InTuneBrand.pink).buttonStyle(.borderedProminent)
                        }
                        .controlSize(.regular)
                        .padding(.horizontal, 20)
                        Text("Swipe left to skip, right to like. Likes appear on Home.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        CommunityDiscoveryView(onRestartDemoCards: demo.resetCards)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
                .frame(maxWidth: 560)
                .frame(minHeight: geometry.size.height, alignment: .top)
                .frame(maxWidth: .infinity)
                }
                if swipeFeedback.horizontalOffset != 0 {
                    let swipingLeft = swipeFeedback.horizontalOffset < 0
                    let tint: Color = swipingLeft ? .red : .green
                    LinearGradient(
                        stops: [
                            .init(color: tint.opacity(swipeFeedback.intensity), location: 0),
                            .init(color: tint.opacity(swipeFeedback.intensity * 0.55), location: 0.35),
                            .init(color: .clear, location: 0.8),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: swipingLeft ? .leading : .trailing,
                        endPoint: swipingLeft ? .trailing : .leading
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height)
                    .frame(maxWidth: .infinity, alignment: swipingLeft ? .leading : .trailing)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
        .background(InTuneBrand.pink.opacity(0.035))
        .navigationTitle("Discover")
        .inTuneCornerMark()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DemoBadge: View {
    var body: some View {
        Label("DEMO · Fictional people and music", systemImage: "sparkles")
            .font(.caption.bold()).foregroundStyle(InTuneBrand.pink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(InTuneBrand.pink.opacity(0.09), in: Capsule())
    }
}

/// Original decorative artwork, not an album cover or a playback control.
struct MusicArtwork: View {
    let title: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [.indigo, InTuneBrand.pink, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(alignment: .center, spacing: 6) {
                ForEach(0..<17) { index in
                    Capsule().fill(.white.opacity(0.65))
                        .frame(width: 5, height: CGFloat([18, 36, 54, 28, 72, 42, 88][index % 7]))
                }
            }.accessibilityHidden(true)
            VStack { Spacer(); Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).padding(12).lineLimit(1) }
        }
        .frame(height: 104)
        .accessibilityLabel("Decorative music artwork for \(title)")
    }
}
