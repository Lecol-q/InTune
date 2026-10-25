import SwiftUI

struct LocalTestProfileDiscoveryView: View {
    @ObservedObject private var music = MusicProfileModel.shared
    @ObservedObject private var community = CommunityStore.shared
    @ObservedObject private var tests = LocalTestProfiles.shared
    @State private var chat: LocalTestProfile?
    @State private var drag = CGSize.zero
    private var signedIn: Bool { music.connected || community.uid != nil }

    var body: some View {
        if signedIn {
            VStack(spacing: 18) {
                Label("Fictional test profiles · instant test matches", systemImage: "testtube.2")
                    .font(.caption).foregroundStyle(.secondary)
                if let person = tests.remaining.first {
                    VStack(alignment: .leading, spacing: 18) {
                        MusicArtwork(title: person.genres.prefix(2).joined(separator: " + "))
                        Text("\(person.name), \(person.age)").font(.largeTitle.bold())
                        Text(person.bio)
                        GenreTags(genres: person.genres)
                        Text("Swipe right to match. She'll send a scripted first message.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(InTuneBrand.pink.opacity(0.25)))
                    .offset(x: drag.width)
                    .rotationEffect(.degrees(Double(drag.width / 24)))
                    .gesture(DragGesture().onChanged { drag = $0.translation }.onEnded { value in
                        if value.translation.width > 90 { like(person) }
                        else if value.translation.width < -90 { tests.pass(person, signedIn: signedIn) }
                        withAnimation(.spring()) { drag = .zero }
                    })
                    HStack(spacing: 24) {
                        Button { tests.pass(person, signedIn: signedIn) } label: { Label("Pass", systemImage: "xmark") }
                            .buttonStyle(.bordered)
                        Button { like(person) } label: { Label("Like \(person.name)", systemImage: "heart.fill") }
                            .buttonStyle(.borderedProminent)
                    }.controlSize(.large)
                    Text("\(tests.remaining.count) test profiles left").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("You've seen all three test profiles.").foregroundStyle(.secondary)
                    if tests.matched.count < LocalTestProfile.women.count {
                        Button("Show passed test profiles again") { tests.restorePassed() }
                    }
                }
                if !tests.matched.isEmpty {
                    Text("Your test matches").font(.headline)
                    ForEach(tests.matched) { person in
                        Button { chat = person } label: {
                            Label("Message \(person.name)", systemImage: "bubble.left.and.bubble.right")
                        }.buttonStyle(.bordered)
                    }
                }
                if let error = tests.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .sheet(item: $chat) { person in LocalTestChatView(profile: person) }
        }
    }
    private func like(_ profile: LocalTestProfile) {
        if tests.like(profile, signedIn: signedIn) { chat = profile }
    }
}

struct LocalTestChatView: View {
    let profile: LocalTestProfile
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var music = MusicProfileModel.shared
    @ObservedObject private var community = CommunityStore.shared
    @ObservedObject private var tests = LocalTestProfiles.shared
    @State private var draft = ""
    private var signedIn: Bool { music.connected || community.uid != nil }
    private var messages: [TestChatMessage] { tests.messages(for: profile) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Label("Fictional profile · scripted first message", systemImage: "testtube.2")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
                if signedIn && tests.isMatched(profile) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                Text("You matched with \(profile.name)!").font(.caption).foregroundStyle(InTuneBrand.pink)
                                ForEach(messages) { message in
                                    HStack {
                                        if message.sentByMe { Spacer(minLength: 40) }
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(message.text).textSelection(.enabled)
                                            Text(message.sentByMe ? "You · saved on this device" : "\(profile.name) · scripted message")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }.padding(12)
                                            .background(message.sentByMe ? InTuneBrand.pink.opacity(0.18) : Color.secondary.opacity(0.10),
                                                        in: RoundedRectangle(cornerRadius: 17))
                                        if !message.sentByMe { Spacer(minLength: 40) }
                                    }.id(message.id)
                                }
                            }.padding(16)
                        }
                        .onAppear { if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                        .onChange(of: messages.count) { _, _ in
                            if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                        }
                    }
                    if let error = tests.error { Text(error).foregroundStyle(.red).font(.footnote) }
                    HStack {
                        TextField("Message \(profile.name)…", text: $draft, axis: .vertical)
                            .lineLimit(1...5).textFieldStyle(.roundedBorder)
                        Button {
                            if tests.send(draft, to: profile, signedIn: signedIn) { draft = "" }
                        } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .accessibilityLabel("Send message")
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                    }.padding(16)
                } else {
                    ContentUnavailableView("Chat unavailable", systemImage: "lock",
                        description: Text("Sign in and match with this test profile to chat."))
                }
            }
            .navigationTitle(profile.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(InTuneBrand.pink)
    }
}
