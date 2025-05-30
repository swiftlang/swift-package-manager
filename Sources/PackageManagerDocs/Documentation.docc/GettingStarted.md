# Getting Started

Learn to create and use Swift packages.

## Overview

To provide a more complete look at what the Swift Package Manager can do, the following example consists of three interdependent packages:

- [PlayingCard](https://github.com/apple/example-package-playingcard) - Defines PlayingCard, Suit, and Rank types.
- [DeckOfPlayingCards](https://github.com/apple/example-package-deckofplayingcards) - Defines a Deck type that shuffles and deals an array of PlayingCard values.
- [Dealer](https://github.com/apple/example-package-dealer) - Defines an executable that creates a DeckOfPlayingCards, shuffles it, and deals the first 10 cards.

### Creating a Library Package

We'll start by creating a target representing a playing card in a standard 52-card deck. 
The [PlayingCard](https://github.com/apple/example-package-playingcard) target defines the PlayingCard type, which consists of a Suit enumeration value (Clubs, Diamonds, Hearts, Spades) and a Rank enumeration value (Ace, Two, Three, …, Jack, Queen, King).

```swift
public enum Rank: Int {
    case two = 2
    case three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace
}

public enum Suit: String {
    case spades, hearts, diamonds, clubs
}

public struct PlayingCard {
    let rank: Rank
    let suit: Suit
}
```

By convention, a target includes any source files located in the `Sources/<target-name>` directory.

```
example-package-playingcard
├── Sources
│   └── PlayingCard
│       ├── PlayingCard.swift
│       ├── Rank.swift
│       └── Suit.swift
└── Package.swift
```

Because the PlayingCard target does not produce an executable, it can be described as a library.
A library is a target that builds a module which can be imported by other packages.
By default, a library module exposes all of the public types and methods declared in source code located in the `Sources/<target-name>` directory.

When creating a library package intended for use as a dependency in other projects, the `Package.swift` manifest resides at the top level/root of the package directory structure.

Run swift build to start the Swift build process. 
If everything worked correctly, it compiles the Swift module for PlayingCard.

> The complete code for the PlayingCard package can be found at [https://github.com/apple/example-package-playingcard](https://github.com/apple/example-package-playingcard).

### Importing Dependencies

The [DeckOfPlayingCards package](https://github.com/apple/example-package-playingcard.git) depends in the previous package: It defines a Deck type.

To use the PlayingCards module, the DeckOfPlayingCards package declares the package as a dependency in its `Package.swift` manifest file.

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DeckOfPlayingCards",
    products: [
        .library(name: "DeckOfPlayingCards",
                 targets: ["DeckOfPlayingCards"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/example-package-playingcard.git",
            from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "DeckOfPlayingCards",
            dependencies: [
                .product(name: "PlayingCard",
                         package: "example-package-playingcard")
            ]),
        .testTarget(
            name: "DeckOfPlayingCardsTests",
            dependencies: [
                .target(name: "DeckOfPlayingCards")
            ]),
    ]
)
```

Each dependency specifies a source URL and version requirements.
The source URL is a URL accessible to the current user that resolves to a Git repository.
The package manager uses the version requirements, which follow Semantic Versioning (SemVer) conventions, to determine which Git tag to check out and use to build the dependency.
The requirement for the PlayingCard dependency uses the most recent version with a major version equal to 3.

When you run the swift build command, the Package Manager downloads all of the dependencies, compiles them, and links them to the package module.
This allows DeckOfPlayingCards to access the public members of its dependent modules with import statements.

You can see the downloaded sources in the `.build/checkouts` directory at the root of your project, and intermediate build products in the `.build` directory at the root of your project.

> The complete code for the DeckOfPlayingCards package can be found at [https://github.com/apple/example-package-deckofplayingcards](https://github.com/apple/example-package-deckofplayingcards).

### Resolving transitive dependencies

With everything else in place, now you can build the Dealer executable. 
The Dealer executable depends on the `DeckOfPlayingCards` package, which in turn depends on the `PlayingCard` package.
However, because the package manager automatically resolves transitive dependencies, you only need to declare the `DeckOfPlayingCards` package as a dependency.

```swift
// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "dealer",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "dealer",
                    targets: ["dealer"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/example-package-deckofplayingcards.git",
            from: "3.0.0"),
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "0.4.4"),
    ],
    targets: [
        .executableTarget(
            name: "dealer",
            dependencies: [
                .product(name: "DeckOfPlayingCards",
                         package: "example-package-deckofplayingcards"),
                .product(name: "ArgumentParser",
                         package: "swift-argument-parser")
            ]),
        .testTarget(
            name: "DealerTests",
            dependencies: [
                .byName(name: "dealer")
            ]),
    ]
)

```

Swift requires that a source file imports the modules for any types that are referenced in code.
In the Dealer module's `Deal.swift` file, the code imports `DeckOfPlayingCards` and `PlayingCard` to use types from each.

```swift
import DeckOfPlayingCards

var deck = Deck.standard52CardDeck()
deck.shuffle()

for count in counts {
    var cards: [PlayingCard] = []

    for _ in 0..<count {
        guard let card = deck.deal() else {
            Self.exit(withError: Error.notEnoughCards)
        }

        cards.append(card)
    }

    print(cards.map(\.description).joined(separator: "\t"))
}
```

Running the `swift build` command compiles and produces the `Dealer` executable, which you run from the `.build/debug` directory.

```bash
$ swift build
$ .build/debug/Dealer 5
♠︎ 6    ♡ 4    ♣︎ 4    ♡ A    ♡ K
```

You can build and run the complete example by downloading the source code of the Dealer project from GitHub and running the following commands:

```bash
$ git clone https://github.com/apple/example-package-dealer.git
$ cd example-package-dealer
$ swift run dealer <count>
```

