public enum Suit: String {
    case Spades, Hearts, Diamonds, Clubs
}

// MARK: - Comparable

extension Suit: Comparable {}

public func <(lhs: Suit, rhs: Suit) -> Bool {
    switch (lhs, rhs) {
    case (_, _) where lhs == rhs:
        return false
    case (.Spades, _),
    (.Hearts, .Diamonds), (.Hearts, .Clubs),
    (.Diamonds, .Clubs):
        return false
    default:
        return true
    }
}

// MARK: - CustomStringConvertible

extension Suit : CustomStringConvertible {
    public var description: String {
        switch self {
        case .Spades: return "♠︎"
        case .Hearts: return "♡"
        case .Diamonds: return "♢"
        case .Clubs: return "♣︎"
        }
    }
}
