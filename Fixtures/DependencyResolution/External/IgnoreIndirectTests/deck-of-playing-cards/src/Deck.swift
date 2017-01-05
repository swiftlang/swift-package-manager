/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import FisherYates
import PlayingCard

public struct Deck {
    fileprivate var cards: [PlayingCard]

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

// MARK: - ExpressibleByArrayLiteral

extension Deck : ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: PlayingCard...) {
        self.init(elements)
    }
}

// MARK: - Equatable

extension Deck : Equatable {}

public func ==(lhs: Deck, rhs: Deck) -> Bool {
    return lhs.cards == rhs.cards
}
