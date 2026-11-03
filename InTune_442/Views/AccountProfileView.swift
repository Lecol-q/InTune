import SwiftUI
import PhotosUI
import ImageIO
import UIKit

struct LocalProfile: Codable, Identifiable {
    let id: UUID
    let name: String
    let birthDate: DateComponents
    let email: String
    let bio: String
    let photo: Data

    static let calendar = Calendar(identifier: .gregorian)

    static var adultCutoff: Date {
        calendar.date(byAdding: .year, value: -18, to: calendar.startOfDay(for: .now))!
    }

    var birthday: Date? { Self.calendar.date(from: birthDate) }

    var validationError: String? {
        if name.isEmpty { return "Enter your name." }
        guard let birthday, birthday <= Self.adultCutoff else {
            return "You must be 18 or older to create a profile."
        }
        if email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil {
            return "Enter a valid email address."
        }
        if bio.isEmpty { return "Write a short bio." }
        if UIImage(data: photo) == nil { return "Choose a profile photo." }
        return nil
    }

    private static var file: URL {
        URL.applicationSupportDirectory.appending(path: "account-profile.json")
    }

    static func load() -> Self? {
        guard let data = try? Data(contentsOf: file),
              let profile = try? JSONDecoder().decode(Self.self, from: data),
              profile.validationError == nil else { return nil }
        return profile
    }

    func persist() throws {
        let file = Self.file
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: [.atomic, .completeFileProtection])
    }
}

extension EnvironmentValues {
    @Entry var localProfile: LocalProfile? = nil
    @Entry var saveLocalProfile: (LocalProfile) throws -> Void = { _ in
        throw CocoaError(.fileWriteUnknown)
    }
}

struct AccountProfileView: View {
    @Environment(\.localProfile) private var profile
    @Environment(\.saveLocalProfile) private var save
    @State private var editing = false

    var body: some View {
        Form {
            if let profile {
                Section {
                    if let image = UIImage(data: profile.photo) {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 160)
                    }
                    Text(profile.name).font(.headline)
                    Text(profile.bio)
                }
                Section("Account details") {
                    Text(profile.email)
                    if let birthday = profile.birthday {
                        LabeledContent("Date of birth", value: birthday.formatted(date: .long, time: .omitted))
                    }
                }
                Button("Edit profile") { editing = true }
                    .sheet(isPresented: $editing) {
                        NavigationStack {
                            ProfileForm(profile: profile) { updated in
                                try save(updated)
                                editing = false
                            }
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") { editing = false }
                                }
                            }
                        }
                    }
            }
        }
        .navigationTitle("Profile")
    }
}

struct ProfileForm: View {
    let profile: LocalProfile?
    let save: (LocalProfile) throws -> Void

    @State private var name: String
    @State private var birthday: Date
    @State private var confirmedDetails: Bool
    @State private var email: String
    @State private var bio: String
    @State private var photo: Data?
    @State private var selection: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var error: String?

    init(profile: LocalProfile?, save: @escaping (LocalProfile) throws -> Void) {
        self.profile = profile
        self.save = save
        _name = State(initialValue: profile?.name ?? "")
        _birthday = State(initialValue: profile?.birthday ?? LocalProfile.adultCutoff)
        _confirmedDetails = State(initialValue: false)
        _email = State(initialValue: profile?.email ?? "")
        _bio = State(initialValue: profile?.bio ?? "")
        _photo = State(initialValue: profile?.photo)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if profile == nil {
                    VStack(spacing: 6) {
                        Image("InTuneMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .accessibilityHidden(true)
                        InTuneLogoView()
                        Text("Create your profile")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Tell us a little about yourself to get started.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                card("Account details") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    Divider()
                    DatePicker("Date of birth", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                    Divider()
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                card("About you") {
                    TextField("Write a short bio", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                    Divider()
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(.rect(cornerRadius: 18))
                            .accessibilityLabel("Profile photo preview")
                    }
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(photo == nil ? "Choose profile photo" : "Change profile photo",
                              systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    if loadingPhoto { ProgressView("Loading photo…") }
                }
                Toggle("I confirm that the information above is accurate and that I am 18 years of age or older.",
                       isOn: $confirmedDetails)
                    .toggleStyle(ProfileCheckboxStyle())
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button(action: submit) {
                    Text(profile == nil ? "Create profile" : "Save changes")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(loadingPhoto)
            }
            .frame(maxWidth: 520)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            LinearGradient(colors: [InTuneBrand.pink.opacity(0.18), Color(uiColor: .systemBackground)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .tint(InTuneBrand.pink)
        .navigationTitle(profile == nil ? "" : "Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(profile == nil ? .hidden : .visible, for: .navigationBar)
        .onChange(of: name) { confirmedDetails = false }
        .onChange(of: birthday) { confirmedDetails = false }
        .onChange(of: email) { confirmedDetails = false }
        .onChange(of: bio) { confirmedDetails = false }
        .onChange(of: photo) { confirmedDetails = false }
        .task(id: selection) {
            guard let selection else { return }
            loadingPhoto = true
            error = nil
            do {
                guard let data = try await selection.loadTransferable(type: Data.self),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1024
                      ] as CFDictionary),
                      let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                guard !Task.isCancelled else { return }
                photo = jpeg
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Could not load that photo. Choose another image."
            }
            loadingPhoto = false
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(InTuneBrand.pink.opacity(0.22))
                .allowsHitTesting(false)
        }
    }

    private func submit() {
        guard confirmedDetails else {
            error = "Check the box to confirm your information and age."
            return
        }
        let updated = LocalProfile(
            id: profile?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            birthDate: LocalProfile.calendar.dateComponents([.year, .month, .day], from: birthday),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
            photo: photo ?? Data()
        )
        error = updated.validationError
        guard error == nil else { return }
        do {
            try save(updated)
        } catch {
            self.error = "Could not save your profile. Try again."
        }
    }
}

private struct ProfileCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(InTuneBrand.pink)
                    .accessibilityHidden(true)
                configuration.label
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Checked" : "Unchecked")
    }
}
