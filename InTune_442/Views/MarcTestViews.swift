import SwiftUI

struct MarcDiscoveryView: View {
    @ObservedObject private var music = MusicProfileModel.shared
    @ObservedObject private var match = MarcTestMatch.shared
    @State private var drag = CGSize.zero
    @State private var showingChat = false

    var body: some View {
        VStack(spacing: 20) {
            if music.connected {
                if match.state.matched {
                    Image(systemName: "heart.circle.fill").font(.system(size: 56)).foregroundStyle(InTuneBrand.pink)
                    Text("You matched with Marc!").font(.title2.bold())
                    Text("Local test match · no real person is contacted.").font(.footnote).foregroundStyle(.secondary)
                    Button("Message Marc") { showingChat = true }.buttonStyle(.borderedProminent)
                } else if match.state.passed {
                    ContentUnavailableView("No more profiles", systemImage: "person.crop.circle",
                        description: Text("You passed on Marc's test card."))
                    Button("Show Marc again") { match.showCardAgain() }.buttonStyle(.bordered)
                } else {
                    Label("Test profile · automatic test match", systemImage: "testtube.2")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 18) {
                        MusicArtwork(title: "Underground frequencies")
                        Text("Marc, 24").font(.largeTitle.bold())
                        Text("Crate-digging, dusty samples, and late-night beat tapes. Put me onto an underground project I haven't heard yet.")
                        GenreTags(genres: ["underground hip hop", "jazz rap", "abstract hip hop", "boom bap"])
                        Text("Looking for someone to trade deep cuts with.").foregroundStyle(.secondary)
                        Text("Photos stay hidden before matching.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(22)
                    .background(.background, in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(InTuneBrand.pink.opacity(0.25)))
                    .offset(x: drag.width)
                    .rotationEffect(.degrees(Double(drag.width / 24)))
                    .gesture(DragGesture().onChanged { drag = $0.translation }.onEnded { value in
                        if value.translation.width > 90 { likeMarc() }
                        else if value.translation.width < -90 { match.pass(connected: music.connected) }
                        withAnimation(.spring()) { drag = .zero }
                    })
                    HStack(spacing: 24) {
                        Button { match.pass(connected: music.connected) } label: {
                            Label("Pass", systemImage: "xmark")
                        }.buttonStyle(.bordered)
                        Button(action: likeMarc) {
                            Label("Like Marc", systemImage: "heart.fill")
                        }.buttonStyle(.borderedProminent)
                    }.controlSize(.large)
                    Text("Swipe right to match and open your test chat.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = match.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .sheet(isPresented: $showingChat) { MarcChatView() }
    }

    private func likeMarc() {
        if match.like(connected: music.connected) { showingChat = true }
    }
}

struct MarcChatView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var music = MusicProfileModel.shared
    @ObservedObject private var match = MarcTestMatch.shared
    @State private var draft = ""
    @FocusState private var composing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Label("Local test chat · Marc's greeting is scripted", systemImage: "testtube.2")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
                if !music.connected || !match.state.matched {
                    ContentUnavailableView("Chat unavailable", systemImage: "lock",
                        description: Text("Connect Spotify and match with Marc's test profile first."))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                Text("You matched with Marc").font(.caption).foregroundStyle(InTuneBrand.pink)
                                ForEach(match.state.messages) { message in
                                    HStack {
                                        if message.sentByMe { Spacer(minLength: 40) }
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(message.text).textSelection(.enabled)
                                            Text(message.sentByMe ? "You · saved on this device" : "Marc · scripted greeting")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        .padding(12)
                                        .background(message.sentByMe ? InTuneBrand.pink.opacity(0.18) : Color.secondary.opacity(0.10),
                                                    in: RoundedRectangle(cornerRadius: 17))
                                        if !message.sentByMe { Spacer(minLength: 40) }
                                    }.id(message.id)
                                }
                            }.padding(16)
                        }
                        .onAppear { if let last = match.state.messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                        .onChange(of: match.state.messages.count) { _, _ in
                            if let last = match.state.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                    if let error = match.error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField("Message Marc…", text: $draft, axis: .vertical)
                            .lineLimit(1...5).textFieldStyle(.roundedBorder).focused($composing)
                        Button {
                            if match.send(draft, connected: music.connected) { draft = "" }
                        } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .accessibilityLabel("Send message")
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                    }.padding(16)
                }
            }
            .navigationTitle("Marc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(InTuneBrand.pink)
    }
}
