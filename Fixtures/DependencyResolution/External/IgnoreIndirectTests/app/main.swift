/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import FisherYates
import PlayingCard
import DeckOfPlayingCards

let numberOfCards = 10

var deck = Deck.standard52CardDeck()

if FisherYates.shuffle {
    deck.shuffle()
}

for _ in 0..<numberOfCards {
    guard let card = deck.deal() else {
        print("No More Cards!")
        break
    }

    print(card)
}
