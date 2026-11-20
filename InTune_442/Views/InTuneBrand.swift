import SwiftUI

enum InTuneBrand {
    static let pink = Color(red: 0.91, green: 0.43, blue: 0.54)
}

struct InTuneLogoView: View {
    var body: some View {
        Text("InTune")
            .font(.system(size: 64, weight: .semibold, design: .rounded))
            .foregroundStyle(InTuneBrand.pink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: 280, minHeight: 90)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct InTuneCornerMark: ViewModifier {
    @State private var showingSettings = false
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Image("InTuneMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .accessibilityLabel("InTune")
                    .accessibilityAddTraits(.isImage)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

extension View {
    func inTuneCornerMark() -> some View { modifier(InTuneCornerMark()) }
}
