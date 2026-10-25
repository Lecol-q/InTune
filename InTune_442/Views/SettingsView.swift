import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "intune.appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var community = CommunityStore.shared
    @ObservedObject private var music = MusicProfileModel.shared
    @ObservedObject private var demo = DemoSession.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    private var selection: AppAppearance { AppAppearance(rawValue: appearance) ?? .system }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account and shared profiles") {
                    NavigationLink("InTune account") { CommunityAccountView() }
                }
                if !music.connected && community.uid == nil {
                    Section("Demo") {
                        Toggle("Demo mode", isOn: $demo.enabled).disabled(music.busy)
                        Text("Show fictional profiles and sample music. Turn off to hide all demo content throughout the app.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your iPhone's appearance. Light and Dark apply across InTune and stay selected when you reopen the app.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(InTuneBrand.pink)
        .preferredColorScheme(selection.colorScheme)
    }
}
