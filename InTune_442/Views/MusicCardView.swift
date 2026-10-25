import SwiftUI

struct MusicCardView: View {
    @ObservedObject private var music = MusicProfileModel.shared
    @ObservedObject private var demo = DemoSession.shared
    @State private var drag = CGSize.zero

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if demo.isActive { DemoBadge() }
                if music.connected {
                    MarcDiscoveryView()
                } else if !demo.isActive {
                    ContentUnavailableView("No profiles to discover yet", systemImage: "person.2",
                        description: Text("Real profiles will appear here when InTune's shared profile service is ready."))
                } else if let person = demo.remaining.first {
                    HStack {
                        Text("Find your frequency").font(.title2.bold())
                        Spacer()
                        Text("\(demo.remaining.count) left").foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        MusicArtwork(title: person.taste.showcaseTrack?.name ?? "InTune Sessions")
                        HStack {
                            Text("\(person.name), \(person.age)").font(.largeTitle.bold())
                            Spacer()
                            Image(systemName: "headphones").foregroundStyle(InTuneBrand.pink)
                        }
                        Text(person.bio).font(.body)
                        if let song = person.taste.showcaseTrack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("SHOWCASE SONG", systemImage: "music.note").font(.caption.bold()).foregroundStyle(.secondary)
                                Text(song.name).font(.headline)
                                Text(song.artists.map(\.name).joined(separator: ", ")).foregroundStyle(.secondary)
                            }
                        }
                        Text(person.taste.summary).font(.subheadline)
                        let shared = demo.sharedGenres(with: person)
                        Label(shared.isEmpty ? "A new sound to explore" : "You share: " + shared.prefix(3).joined(separator: ", "),
                              systemImage: "waveform.path").font(.subheadline).foregroundStyle(InTuneBrand.pink)
                        Text("Photos stay hidden before a mutual match.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(22)
                    .background(.background, in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(InTuneBrand.pink.opacity(0.2)))
                    .shadow(color: InTuneBrand.pink.opacity(0.1), radius: 16, y: 8)
                    .offset(x: drag.width)
                    .rotationEffect(.degrees(Double(drag.width / 24)))
                    .gesture(DragGesture().onChanged { drag = $0.translation }.onEnded { value in
                        if abs(value.translation.width) > 90 { demo.decide(person, like: value.translation.width > 0) }
                        withAnimation(.spring()) { drag = .zero }
                    })
                    HStack(spacing: 30) {
                        Button { demo.decide(person, like: false) } label: {
                            Label("Pass", systemImage: "xmark").frame(minWidth: 85)
                        }.tint(.secondary).buttonStyle(.bordered)
                        Button { demo.decide(person, like: true) } label: {
                            Label("Like", systemImage: "heart.fill").frame(minWidth: 85)
                        }.tint(InTuneBrand.pink).buttonStyle(.borderedProminent)
                    }.controlSize(.large)
                    Text("Swipe left to pass, right to like. Likes appear on Home.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("You're all caught up", systemImage: "checkmark.circle",
                        description: Text("You've explored every sample profile. Your demo likes are on Home."))
                    Button("Restart demo cards") { demo.resetCards() }.buttonStyle(.borderedProminent)
                }
            }.padding(20)
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
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(InTuneBrand.pink.opacity(0.09), in: Capsule())
    }
}

/// Original decorative artwork, not an album cover or a playback control.
struct MusicArtwork: View {
    let title: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [.indigo, InTuneBrand.pink, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(alignment: .center, spacing: 7) {
                ForEach(0..<17) { index in
                    Capsule().fill(.white.opacity(0.65))
                        .frame(width: 6, height: CGFloat([22, 44, 70, 36, 90, 55, 110][index % 7]))
                }
            }.accessibilityHidden(true)
            VStack { Spacer(); Text(title).font(.headline).foregroundStyle(.white).padding(16) }
        }
        .frame(height: 190)
        .accessibilityLabel("Decorative music artwork for \(title)")
    }
}
