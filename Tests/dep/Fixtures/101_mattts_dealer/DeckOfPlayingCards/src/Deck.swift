import FisherYates
import PlayingCard

public struct Deck {
    private var cards: [PlayingCard]

    public static func standard52CardDeck() -> Deck {
        let suits: [Suit] = [.Spades, .Hearts, .Diamonds, .Clubs]
        let ranks: [Rank] = [.Ace, .Two, .Three, .Four, .Five, .Six, .Seven, .Eight, .Nine, .Ten, .Jack, .Queen, .King]

        var cards: [PlayingCard] = []
        for suit in suits {
            for rank in ranks {
                cards.append(PlayingCard(rank: rank, suit: suit))
            }
        }

        return Deck(cards)
    }

    public init(_ cards: [PlayingCard]) {
        self.cards = cards
    }

    public mutating func shuffle() {
        cards.shuffleInPlace()
    }

    public mutating func deal() -> PlayingCard? {
        guard !cards.isEmpty else { return nil }

        return cards.removeLast()
    }
}

// MARK: - ArrayLiteralConvertible

extension Deck : ArrayLiteralConvertible {
    public init(arrayLiteral elements: PlayingCard...) {
        self.init(elements)
    }
}

// MARK: - Equatable

extension Deck : Equatable {}

public func ==(lhs: Deck, rhs: Deck) -> Bool {
    return lhs.cards == rhs.cards
}
