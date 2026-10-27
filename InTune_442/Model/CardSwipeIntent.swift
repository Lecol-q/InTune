import Foundation

/// Lock the gesture's initial intent so a vertical scroll can never become a like.
struct CardSwipeIntent {
    enum Axis { case undecided, horizontal, vertical }
    enum Decision: Equatable { case pass, like }
    private(set) var axis: Axis = .undecided

    mutating func update(x: Double, y: Double) {
        guard axis == .undecided, max(abs(x), abs(y)) >= 12 else { return }
        if abs(x) > abs(y) * 1.3 { axis = .horizontal }
        else if abs(y) > abs(x) * 1.3 { axis = .vertical }
    }
    func decision(x: Double, y: Double) -> Decision? {
        guard axis == .horizontal, abs(x) > 90, abs(x) > abs(y) * 1.3 else { return nil }
        return x > 0 ? .like : .pass
    }
}
