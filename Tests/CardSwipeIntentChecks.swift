import Foundation

@main struct CardSwipeIntentChecks {
    static func main() {
        var vertical = CardSwipeIntent()
        vertical.update(x: 4, y: 24)
        precondition(vertical.axis == .vertical)
        vertical.update(x: 180, y: 26)
        precondition(vertical.decision(x: 180, y: 26) == nil, "A scroll must never become a match")
        var right = CardSwipeIntent()
        right.update(x: 22, y: 3)
        precondition(right.decision(x: 120, y: 12) == .like)
        precondition(right.decision(x: 70, y: 2) == nil, "Short drags should snap back")
        precondition(right.decision(x: 120, y: 160) == nil, "Mostly vertical release must not like")
        var left = CardSwipeIntent()
        left.update(x: -24, y: 4)
        precondition(left.decision(x: -140, y: 20) == .pass)
        var diagonal = CardSwipeIntent()
        diagonal.update(x: 30, y: 30)
        precondition(diagonal.axis == .undecided && diagonal.decision(x: 110, y: 100) == nil)
        var tap = CardSwipeIntent()
        tap.update(x: 3, y: 2)
        precondition(tap.axis == .undecided && tap.decision(x: 3, y: 2) == nil)
        print("Card swipe checks passed: vertical intent lock, horizontal likes/passes, short drags, diagonal gestures, taps.")
    }
}
