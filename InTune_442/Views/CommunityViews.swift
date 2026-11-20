import SwiftUI

struct CommunityAccountView: View {
    @ObservedObject private var community = CommunityStore.shared
    @ObservedObject private var music = MusicProfileModel.shared
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var name = ""
    @State private var age = 21
    @State private var bio = ""

    var body: some View {
        Form {
            if !community.configured {
                Section("Team setup required") {
                    Text("Everyone needs the same Firebase project. Add its project ID and Web API key to CommunityConfig.json, enable Email/Password authentication, and deploy the supplied Firestore rules.")
                    Text("Shared profiles are unavailable until that setup is complete.").foregroundStyle(.secondary)
                }
            } else if community.uid == nil {
                Section("Your InTune account") {
                    Text("Spotify supplies your music. A separate InTune account lets you share a profile and find your teammates across devices.")
                    Toggle("Create a new account", isOn: $creating)
                    TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(creating ? .newPassword : .password)
                    Button(creating ? "Create account" : "Sign in") {
                        Task {
                            await community.signIn(email: email, password: password, create: creating)
                            password = ""
                            fillProfile()
                        }
                    }.disabled(community.busy || email.isEmpty || password.isEmpty)
                }
            } else {
                Section("Your shared profile") {
                    TextField("Name", text: $name).textContentType(.givenName)
                    Stepper("Age: \(age)", value: $age, in: 18...120)
                    TextField("Biography", text: $bio, axis: .vertical).lineLimit(3...5)
                    Text("Sharing publishes your name, age, bio, top artists, genre tags, and showcase song to signed-in users in this InTune project. Photos, email, and Spotify tokens are not included.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if music.taste == nil {
                        Text("Connect Spotify in My music to include your listening tastes. You can share a basic profile now.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(community.profile?.active == true ? "Update shared profile" : "Share my profile") {
                        Task { await community.publish(name: name, age: age, bio: bio, taste: music.taste) }
                    }.disabled(community.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if community.profile?.active == true {
                        Button("Hide my profile", role: .destructive) { Task { await community.hideProfile() } }.disabled(community.busy)
                    }
                }
                Section {
                    Button("Sign out of InTune", role: .destructive) { community.signOut() }.disabled(community.busy)
                    Text("Hiding your profile removes it from discovery. Signing out alone keeps an already shared profile visible.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if community.busy { ProgressView("Updating shared profiles…") }
            if let error = community.error { Section { Text(error).foregroundStyle(.red) } }
            if let notice = community.notices { Section { Text(notice) } }
        }
        .navigationTitle("InTune account")
        .task { await community.refresh(); fillProfile() }
    }
    private func fillProfile() {
        if let p = community.profile { name = p.name; age = p.age; bio = p.bio }
    }
}

struct CommunityDiscoveryView: View {
    @ObservedObject private var community = CommunityStore.shared
    let onRestartDemoCards: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("People on InTune").font(.title3.bold())
                Spacer()
                Button("Restart demo cards", action: onRestartDemoCards).font(.caption2).lineLimit(1)
            }
            if !community.configured || community.uid == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Set up your InTune account and share your profile to discover your teammates.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("Open InTune account") { CommunityAccountView() }
                        .buttonStyle(.borderedProminent).tint(InTuneBrand.pink)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
            } else if community.profile?.active != true {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Share your profile to start discovering people.").font(.subheadline)
                    NavigationLink("Share my profile") { CommunityAccountView() }
                        .buttonStyle(.borderedProminent).tint(InTuneBrand.pink)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
            } else if let person = community.candidates.first {
                VStack(alignment: .leading, spacing: 9) {
                    if let showcaseSong = ShowcaseSong.shared(person.showcase) {
                        SongAlbumArtwork(song: showcaseSong)
                    } else {
                        MusicArtwork(title: "InTune Sessions")
                    }
                    HStack(spacing: 8) {
                        Text("\(person.name), \(person.age)").font(.title2.bold()).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "headphones").foregroundStyle(InTuneBrand.pink)
                    }
                    Text(person.bio).font(.subheadline).lineLimit(3)
                    if let song = ShowcaseSong.shared(person.showcase) {
                        ShowcaseSongCard(song: song, compact: true)
                    } else if !person.showcase.isEmpty {
                        Label(person.showcase, systemImage: "music.note").font(.subheadline).lineLimit(1)
                    }
                    if !person.genres.isEmpty {
                        GenreTags(genres: Array(person.genres.prefix(4)), compact: true)
                        if person.genres.count > 4 {
                            Text("+\(person.genres.count - 4) more genres")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if !person.artists.isEmpty {
                        Text(person.artists.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text("Photos stay hidden before a mutual match.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(InTuneBrand.pink.opacity(0.2)))
                .shadow(color: InTuneBrand.pink.opacity(0.1), radius: 12, y: 5)
                .id(person.id)
                .horizontalCardSwipe(enabled: !community.busy) { liked in
                    Task { await community.swipe(person, like: liked) }
                }
                HStack(spacing: 14) {
                    Button { Task { await community.swipe(person, like: false) } } label: {
                        Label("Skip", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.secondary)
                    Button { Task { await community.swipe(person, like: true) } } label: {
                        Label("Like", systemImage: "heart.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(InTuneBrand.pink)
                }
                .controlSize(.regular)
                .padding(.horizontal, 20)
                Text("Swipe left to skip, right to like.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
                if community.busy { ProgressView().frame(maxWidth: .infinity) }
            } else {
                Text("No new profiles yet. Ask your teammates to sign in and share their profiles on this same InTune project.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = community.error { Text(error).font(.footnote).foregroundStyle(.red) }
            if let notice = community.notices { Text(notice).font(.footnote).foregroundStyle(InTuneBrand.pink) }
            if community.uid != nil {
                Button("Refresh people and matches") { Task { await community.refresh() } }
                    .disabled(community.busy).font(.caption)
            }
        }
        .task { await community.refresh() }
    }
}

struct CommunityChatView: View {
    let match: CommunityMatch
    let name: String
    @ObservedObject private var community = CommunityStore.shared
    @State private var messages: [CommunityMessage] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var sending = false
    @State private var pendingMessageID: String?
    @State private var pendingText: String?

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            HStack {
                                if message.senderID == community.uid { Spacer(minLength: 40) }
                                Text(message.text).textSelection(.enabled).padding(12)
                                    .background(message.senderID == community.uid ? InTuneBrand.pink.opacity(0.18) : Color.secondary.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 16))
                                if message.senderID != community.uid { Spacer(minLength: 40) }
                            }.id(message.id)
                        }
                    }.padding(16)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
            HStack {
                TextField("Message…", text: $draft, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder).disabled(sending)
                Button {
                    Task { await send() }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                .accessibilityLabel("Send message")
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000 || community.uid == nil)
            }.padding(16)
        }
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
        .task(id: community.uid) {
            while !Task.isCancelled && community.uid != nil {
                await loadMessages()
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
            }
        }
        .onChange(of: community.uid) { _, _ in messages = []; draft = "" }
    }
    private func loadMessages() async {
        guard let expectedUID = community.uid else { messages = []; return }
        do {
            let loaded = try await community.messages(in: match)
            guard community.uid == expectedUID, !Task.isCancelled else { return }
            messages = loaded; error = nil
        } catch {
            guard community.uid == expectedUID, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
    private func send() async {
        sending = true
        defer { sending = false }
        // Reuse the ID on a retry if a response was lost, preventing duplicate deliveries.
        if pendingText != draft { pendingText = draft; pendingMessageID = UUID().uuidString }
        guard let id = pendingMessageID else { return }
        do {
            try await community.send(draft, in: match, messageID: id)
            draft = ""; pendingText = nil; pendingMessageID = nil
            await loadMessages()
        } catch {
            await loadMessages()
            if messages.contains(where: { $0.id == id }) {
                draft = ""; pendingText = nil; pendingMessageID = nil; self.error = nil
            } else { self.error = error.localizedDescription }
        }
    }
}
