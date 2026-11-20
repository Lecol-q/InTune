import SwiftUI
import Combine

@MainActor
final class CardSwipeFeedback: ObservableObject {
    static let shared = CardSwipeFeedback()
    @Published private(set) var horizontalOffset: CGFloat = 0
    var intensity: Double {
        let progress = min(Double(abs(horizontalOffset)) / 220, 1)
        return 0.8 * progress * sqrt(progress)
    }
    func update(offset: CGFloat) { horizontalOffset = offset }
    func clear() { horizontalOffset = 0 }
}

private struct HorizontalCardSwipe: ViewModifier {
    let enabled: Bool
    let onSwipe: (Bool) -> Void
    @ObservedObject private var feedback = CardSwipeFeedback.shared
    @State private var intent = CardSwipeIntent()
    @State private var horizontalOffset: CGFloat = 0
    @State private var isExiting = false

    func body(content: Content) -> some View {
        content
            .offset(x: horizontalOffset)
            .rotationEffect(.degrees(Double(horizontalOffset / 24)))
            // Simultaneous recognition lets the surrounding vertical ScrollView work
            // even when the finger starts on the face or edge of a card.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard enabled, !isExiting else { return }
                        intent.update(x: value.translation.width, y: value.translation.height)
                        if intent.axis == .horizontal {
                            horizontalOffset = value.translation.width
                            feedback.update(offset: horizontalOffset)
                        }
                    }
                    .onEnded { value in
                        guard !isExiting else { return }
                        let decision = enabled ? intent.decision(x: value.translation.width, y: value.translation.height) : nil
                        guard let decision else {
                            intent = CardSwipeIntent()
                            feedback.clear()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                horizontalOffset = 0
                            }
                            return
                        }

                        // Keep this card's content in place until its exit animation
                        // completes. The parent can then advance to the next profile.
                        isExiting = true
                        let direction: CGFloat = decision == .like ? 1 : -1
                        let exitDistance = max(abs(value.translation.width) + 500, 1_000)
                        withAnimation(.easeIn(duration: 0.22)) {
                            horizontalOffset = direction * exitDistance
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                            horizontalOffset = 0
                            isExiting = false
                            intent = CardSwipeIntent()
                            feedback.clear()
                            onSwipe(decision == .like)
                        }
                    }
            )
            .onChange(of: enabled) { _, active in if !active { reset() } }
    }

    private func reset() {
        intent = CardSwipeIntent()
        isExiting = false
        feedback.clear()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { horizontalOffset = 0 }
    }
}

extension View {
    func horizontalCardSwipe(enabled: Bool = true, onSwipe: @escaping (Bool) -> Void) -> some View {
        modifier(HorizontalCardSwipe(enabled: enabled, onSwipe: onSwipe))
    }
}
