import SwiftUI

struct ArtistGenreEditor: View {
    let artist: SpotifyArtist
    @ObservedObject private var model = MusicProfileModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var validation: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(artist.name) {
                    TextField("Genres, separated by commas", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                    Text("Add up to 8 specific genres. Your edits stay saved when you refresh Spotify and are labeled as your tags.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let validation { Section { Text(validation).foregroundStyle(.red) } }
                if model.hasGenreCorrection(artist) {
                    Section {
                        Button("Use catalog tags") {
                            if model.useCatalogGenres(for: artist) { dismiss() }
                            else { validation = model.error ?? "Could not restore catalog tags." }
                        }
                    }
                }
            }
            .navigationTitle("Genre tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.saveGenres(for: artist, text: text) { dismiss() }
                        else { validation = model.error ?? "Could not save tags." }
                    }
                }
            }
            .onAppear { text = (artist.genres ?? []).joined(separator: ", ") }
        }
    }
}
