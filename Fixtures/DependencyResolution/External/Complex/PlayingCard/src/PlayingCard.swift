public struct PlayingCard: Equatable {
    let rank: Rank
    let suit: Suit

    public init(rank: Rank, suit: Suit) {
        self.rank = rank
        self.suit = suit
    }
}

// MARK: - Comparable

extension PlayingCard: Comparable {}

public func <(lhs: PlayingCard, rhs: PlayingCard) -> Bool {
    return lhs.suit < rhs.suit || (lhs.suit == rhs.suit && lhs.rank < rhs.rank)
}

// MARK: - CustomStringConvertible

extension PlayingCard : CustomStringConvertible {
    public var description: String {
        return "\(suit)\(rank)"
    }
}
