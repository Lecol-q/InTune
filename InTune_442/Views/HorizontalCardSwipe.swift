import SwiftUI

private struct HorizontalCardSwipe: ViewModifier {
    let enabled: Bool
    let onSwipe: (Bool) -> Void
    @State private var intent = CardSwipeIntent()
    @State private var horizontalOffset: CGFloat = 0
    @GestureState private var dragging = false

    func body(content: Content) -> some View {
        content
            .offset(x: horizontalOffset)
            .rotationEffect(.degrees(Double(horizontalOffset / 24)))
            // Simultaneous recognition lets the surrounding vertical ScrollView work
            // even when the finger starts on the face or edge of a card.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .updating($dragging) { _, active, _ in active = true }
                    .onChanged { value in
                        guard enabled else { return }
                        intent.update(x: value.translation.width, y: value.translation.height)
                        if intent.axis == .horizontal { horizontalOffset = value.translation.width }
                    }
                    .onEnded { value in
                        let decision = enabled ? intent.decision(x: value.translation.width, y: value.translation.height) : nil
                        reset()
                        if let decision { onSwipe(decision == .like) }
                    }
            )
            .onChange(of: dragging) { _, active in if !active { reset() } }
            .onChange(of: enabled) { _, active in if !active { reset() } }
    }
    private func reset() {
        intent = CardSwipeIntent()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { horizontalOffset = 0 }
    }
}

extension View {
    func horizontalCardSwipe(enabled: Bool = true, onSwipe: @escaping (Bool) -> Void) -> some View {
        modifier(HorizontalCardSwipe(enabled: enabled, onSwipe: onSwipe))
    }
}
