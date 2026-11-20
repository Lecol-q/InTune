import SwiftUI

/// The Matches tab as a restrained jukebox selection board; every tile opens its chat.
struct CommunityMatchesView: View {
    @ObservedObject private var music = MusicProfileModel.shared
    @ObservedObject private var tests = LocalTestProfiles.shared
    @ObservedObject private var community = CommunityStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedTestChat: LocalTestProfile?
    private var testMatches: [LocalTestProfile] { music.connected || community.uid != nil ? tests.matched : [] }
    private var sharedMatches: [CommunityMatch] { community.uid != nil ? community.matches : [] }
    private var count: Int { testMatches.count + sharedMatches.count }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 135), spacing: 12, alignment: .top)]
    }
    private var cabinet: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 38, bottomLeadingRadius: 20,
                               bottomTrailingRadius: 20, topTrailingRadius: 38)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your jukebox").font(.title.bold())
                        Text("Pick a connection. Start a conversation.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "music.note.list").font(.title2).foregroundStyle(InTuneBrand.pink)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label("IN TUNE", systemImage: "waveform").font(.caption.bold()).tracking(2)
                        Spacer()
                        Text("\(count) \(count == 1 ? "selection" : "selections")")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .foregroundStyle(InTuneBrand.pink)
                    Divider().overlay(InTuneBrand.pink.opacity(0.15))

                    if count == 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your jukebox is quiet").font(.title3.bold())
                            Text("Match with someone in Discover and their song will appear here. Tap their selection to chat.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 22)
                    }
                    if !testMatches.isEmpty {
                        Label("Test selections · on this device", systemImage: "testtube.2")
                            .font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(testMatches) { person in
                                Button { selectedTestChat = person } label: {
                                    JukeboxMatchTile(code: selectionCode(for: person), name: person.name,
                                        song: person.showcaseSong.title, artist: person.showcaseSong.artist,
                                        hasUnread: tests.unreadCount(for: person) > 0, isTest: true)
                                }.buttonStyle(JukeboxSelectionStyle())
                            }
                        }
                    }
                    if !sharedMatches.isEmpty {
                        Text("Your matches").font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(sharedMatches.enumerated()), id: \.element.id) { index, match in
                                if let uid = community.uid, let other = match.otherID(than: uid) {
                                    let person = community.people[other]
                                    let song = person.flatMap { ShowcaseSong.shared($0.showcase) }
                                    NavigationLink {
                                        CommunityChatView(match: match, name: person?.name ?? "Your match")
                                    } label: {
                                        JukeboxMatchTile(code: "B\(index + 1)", name: person?.name ?? "Your match",
                                            song: song?.title ?? (person?.showcase.isEmpty == false ? (person?.showcase ?? "") : "No showcase song yet"),
                                            artist: song?.artist ?? "", hasUnread: false, isTest: false)
                                    }.buttonStyle(JukeboxSelectionStyle())
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: cabinet)
                .overlay(cabinet.strokeBorder(InTuneBrand.pink.opacity(0.23), lineWidth: 1))

                if community.uid == nil {
                    NavigationLink("Connect your InTune account for shared matches") { CommunityAccountView() }
                        .font(.footnote)
                }
                if let error = community.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Matches")
        .navigationBarTitleDisplayMode(.inline)
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
    private func selectionCode(for person: LocalTestProfile) -> String {
        "A\((LocalTestProfile.women.firstIndex { $0.id == person.id } ?? 0) + 1)"
    }
}

private struct JukeboxMatchTile: View {
    let code: String
    let name: String
    let song: String
    let artist: String
    let hasUnread: Bool
    let isTest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(code).font(.caption.bold()).monospaced().foregroundStyle(InTuneBrand.pink)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(InTuneBrand.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                Spacer(minLength: 0)
                Circle().fill(hasUnread ? InTuneBrand.pink : Color.secondary.opacity(0.20))
                    .frame(width: 7, height: 7)
                    .shadow(color: hasUnread ? InTuneBrand.pink.opacity(0.4) : .clear, radius: 4)
                    .accessibilityHidden(true)
            }
            Text(name).font(.title3.bold()).foregroundStyle(.primary).lineLimit(2)
            VStack(alignment: .leading, spacing: 4) {
                Text(song).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                if !artist.isEmpty { Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
            Label(hasUnread ? "New message" : "Open chat", systemImage: hasUnread ? "bubble.left.fill" : "arrow.up.right")
                .font(.caption).foregroundStyle(hasUnread ? InTuneBrand.pink : .secondary)
        }
        .padding(15).frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(InTuneBrand.pink.opacity(0.6))
                .frame(width: 3).padding(.vertical, 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(code). \(name). \(song). \(artist). \(hasUnread ? "New message." : "Open chat.")\(isTest ? " Fictional test profile." : "")")
    }
}

private struct JukeboxSelectionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
