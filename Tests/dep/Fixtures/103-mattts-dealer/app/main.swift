import FisherYates
import PlayingCard
import DeckOfPlayingCards

#if os(Linux)
import Glibc
#endif

let numberOfCards = 10

var deck = Deck.standard52CardDeck()

//deck.shuffle()  // no shuffle!

for _ in 0..<numberOfCards {
    guard let card = deck.deal() else {
        print("No More Cards!")
        break
    }

    print(card)
}
