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
    @State private var drag = CGSize.zero
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("People on InTune").font(.title2.bold())
            if !community.configured || community.uid == nil {
                Text("Set up your InTune account and share your profile to discover your teammates.").foregroundStyle(.secondary)
                NavigationLink("Open InTune account") { CommunityAccountView() }.buttonStyle(.borderedProminent)
            } else if community.profile?.active != true {
                Text("Share your profile to start discovering people.")
                NavigationLink("Share my profile") { CommunityAccountView() }.buttonStyle(.borderedProminent)
            } else if let person = community.candidates.first {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(person.name), \(person.age)").font(.largeTitle.bold())
                    Text(person.bio)
                    GenreTags(genres: person.genres)
                    if !person.showcase.isEmpty {
                        Label(person.showcase, systemImage: "music.note").font(.headline)
                    }
                    if !person.artists.isEmpty { Text(person.artists.joined(separator: ", ")).foregroundStyle(.secondary) }
                    Text("Photos remain hidden. Chat opens after a mutual like.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(InTuneBrand.pink.opacity(0.25)))
                .offset(x: drag.width)
                .gesture(DragGesture().onChanged { if !community.busy { drag = $0.translation } }.onEnded { value in
                    if !community.busy && abs(value.translation.width) > 90 {
                        Task { await community.swipe(person, like: value.translation.width > 0) }
                    }
                    withAnimation(.spring()) { drag = .zero }
                })
                HStack {
                    Button("Pass") { Task { await community.swipe(person, like: false) } }.buttonStyle(.bordered)
                    Spacer()
                    Button("Like") { Task { await community.swipe(person, like: true) } }.buttonStyle(.borderedProminent)
                }.disabled(community.busy)
            } else {
                Text("No new profiles yet. Ask your teammates to sign in and share their profiles on this same Firebase project.")
                    .foregroundStyle(.secondary)
            }
            if let error = community.error { Text(error).font(.footnote).foregroundStyle(.red) }
            if let notice = community.notices { Text(notice).font(.footnote).foregroundStyle(InTuneBrand.pink) }
            if community.uid != nil {
                Button("Refresh people and matches") { Task { await community.refresh() } }.disabled(community.busy)
            }
        }.task { await community.refresh() }
    }
}

struct CommunityMatchesView: View {
    @ObservedObject private var music = MusicProfileModel.shared
    @ObservedObject private var tests = LocalTestProfiles.shared
    @State private var selectedTestChat: LocalTestProfile?
    @ObservedObject private var community = CommunityStore.shared
    var body: some View {
        List {
            if (music.connected || community.uid != nil) && !tests.matched.isEmpty {
                Section("Test chats · on this device") {
                    ForEach(tests.matched) { person in
                        Button { selectedTestChat = person } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(person.name, systemImage: "bubble.left.and.bubble.right")
                                Text(tests.messages(for: person).last?.text ?? "You matched!")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            if community.uid == nil {
                NavigationLink("Sign in to InTune") { CommunityAccountView() }
            } else if community.matches.isEmpty {
                Text("No matches yet. Like someone in Discover; when they like you back, your chat appears here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(community.matches) { match in
                if let uid = community.uid, let other = match.otherID(than: uid) {
                    NavigationLink {
                        CommunityChatView(match: match, name: community.people[other]?.name ?? "Your match")
                    } label: {
                        Label(community.people[other]?.name ?? "Your match", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
            if let error = community.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Matches")
        .sheet(item: $selectedTestChat) { person in LocalTestChatView(profile: person) }
        .inTuneCornerMark()
        .refreshable { await community.refresh() }
        .task(id: community.uid) {
            while !Task.isCancelled && community.uid != nil {
                await community.refresh()
                do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { break }
            }
        }
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
