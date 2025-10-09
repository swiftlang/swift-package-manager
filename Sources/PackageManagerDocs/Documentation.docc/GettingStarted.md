# Getting Started

Learn to create and use Swift packages.

## Overview

To provide a more complete look at what the Swift Package Manager can do, the following example consists of three interdependent packages, which you can explore:

- [PlayingCard](https://github.com/apple/example-package-playingcard) - Defines PlayingCard, Suit, and Rank types.
- [DeckOfPlayingCards](https://github.com/apple/example-package-deckofplayingcards) - Defines a Deck type that shuffles and deals an array of PlayingCard values.
- [Dealer](https://github.com/apple/example-package-dealer) - Defines an executable that creates a DeckOfPlayingCards, shuffles it, and deals the first 10 cards.

This guide shows you how to create a library that uses another library as a dependency, use the Package Manager to build and test your code, and show you how you might release your own package.

### Creating a library package

This example starts with using an existing package that represents a playing card in a standard 52-card deck.
The package, [PlayingCard](https://github.com/apple/example-package-playingcard), is available through git and provides a library (`PlayingCard`) that this guide uses and expands upon.

This example creates the library `DeckOfPlayingCards` that provides a type that represents a deck of cards and common interactions with the deck, including shuffling, counting, and dealing. 
To start a new library, first make an empty directory, and within it run the `swift package init` command to initialize a new package:

```bash
mkdir DeckOfPlayingCards
cd DeckOfPlayingCards
swift package init
```

The default template that Package Manager creates is a library, which you can control with the `--type` parameter.
The name of the package defaults to the name of the directory you created, and can be overridden with the `--name` parameter to the `swift package init` command.
For the complete details on options for this command, see the [swift package init documentation](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/packageinit).

The template generates a structure of files in the directory that follow the defaults for a Swift package:

```bash
DeckOfPlayingCards
├── .gitignore
├── Package.swift
├── Sources
│   └── DeckOfPlayingCards
│       └── DeckOfPlayingCards.swift
└── Tests
    └── DeckOfPlayingCardsTests
        └── DeckOfPlayingCardsTests.swift
```

The template provides a directory to host a single module that is exposed as a library at `Sources/DeckOfPlayingcards`, and a matching directory to host the tests.
The default package structure provides a library that consists of a single target, both of which are named the same as the package: `DeckOfPlayingCards`, and a test target where you can add tests as you develop your code.

```swift
let package = Package(
    name: "DeckOfPlayingCards",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DeckOfPlayingCards",
            targets: ["DeckOfPlayingCards"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DeckOfPlayingCards"
        ),
        .testTarget(
            name: "DeckOfPlayingCardsTests",
            dependencies: ["DeckOfPlayingCards"]
        ),
    ]
)
```

### Adding a dependency

To add the dependency on the library that provides a PlayingCard so that this example can use it, use the `add-dependency` command, providing the location where the package is hosted. 

```bash
swift package add-dependency https://github.com/apple/example-package-playingcard --from 3.0.0
```

Each dependency within a package specifies a source URL and version requirements.
The source URL is a URL accessible to the current user that resolves to a Git repository.
The package manager uses the version requirements, which follow Semantic Versioning (SemVer) conventions, to determine which Git tag to check out and use to build the dependency.

The above example uses the parameter `--from 3.0.0`, to indicate the version requirements for the dependency.
The `from` constrains the dependency chosen to a minimum of `3.0.0` and extending up to the highest minor and patch release available from the git repository.
Package Manager uses tags, interpreting them as semantic versions, to determine the versions available.
The command updated the `Package.swift` manifest file, adding the `dependencies` section:

```swift
let package = Package(
    name: "DeckOfPlayingCards",
    products: [
        ...
    ],
    dependencies: [
        .package(url: "https://github.com/apple/example-package-playingcard", from: "3.0.0"),
    ],
    targets: [
        ...
    ]
)
```

Adding the dependency makes it available to the package, but doesn't include it by default into the targets within the package.
For example, if you are attempting to build the package using `swift build`, the build would succeed, but provide the warning:

```bash
warning: 'deckofplayingcards': dependency 'example-package-playingcard' is not used by any target
```

If you attempted to use the library in the source, for example `import PlayingCard`, the compiler reports `No such module 'PlayingCard'`.

When you run the swift build command, the Package Manager downloads all of the dependencies, compiles them, and links them to the package module based on the Package.swift manifest.
You can see the downloaded sources in the `.build/checkouts` directory at the root of your project, and intermediate build products in the `.build` directory at the root of your project.

You also need to include the dependency on the target where you want to use the library.
Use the command `add-target-dependency` to add the dependency to the target in this package.

```bash
swift package add-target-dependency PlayingCard DeckOfPlayingCards --package example-package-playingcard
```

This allows DeckOfPlayingCards to access the public members of its dependent modules with import statements.
The above command updates the `Package.swift` manifest so that the DeckOfPlayingCards target now references the dependency:

```swift
.target(
    name: "DeckOfPlayingCards",
    dependencies: [
        .target(name: "PlayingCard"),
    ]
),
```
 
With this update in place, when you run `swift build` the package compiles without warnings.

### Implement the library

The template provides an empty file for the source for your package. Remove the content, add `import PlayingCard`, and your implementation.
The following code provides an example implementation:

```swift
import PlayingCard

/// A model for shuffling and dealing a deck of playing cards.
///
/// The playing card deck consists of 52 individual cards in four suites: spades, hearts, diamonds, and clubs.
/// There are 13 ranks from two to ten, then jack, queen, king, and ace.
public struct Deck: Equatable {
  fileprivate var cards: [PlayingCard]

  /// Returns a deck of playing cards.
  public static func standard52CardDeck() -> Deck {
    var cards: [PlayingCard] = []
    for rank in Rank.allCases {
      for suit in Suit.allCases {
        cards.append(PlayingCard(rank: rank, suit: suit))
      }
    }

    return Deck(cards)
  }

  /// Creates a deck of playing cards.
  public init(_ cards: [PlayingCard]) {
    self.cards = cards
  }

  /// Randomly shuffles a deck of playing cards.
  public mutating func shuffle() {
    cards.shuffle()
  }

  /// Deals a card from the deck.
  ///
  /// The function returns the last card in the deck.
  public mutating func deal() -> PlayingCard? {
    guard !cards.isEmpty else { return nil }

    return cards.removeLast()
  }

  /// The number of remaining cards in the deck.
  public var count: Int {
    cards.count
  }
}

// MARK: - ExpressibleByArrayLiteral

extension Deck: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: PlayingCard...) {
    self.init(elements)
  }
}
```

Use `swift build` to build the package, and `swift test` to run all the tests associated with the package.
The default template also includes the structure that uses [swift-testing](https://swiftpackageindex.com/swiftlang/swift-testing/documentation/testing) by default, including an empty but functional single test:

```bash
[1/1] Planning build
Building for debugging...
[10/10] Linking DeckOfPlayingCardsPackageTests
Build complete! (2.68s)
Test Suite 'All tests' started at 2025-10-09 13:12:08.094.
Test Suite 'All tests' passed at 2025-10-09 13:12:08.095.
     Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
◇ Test run started.
↳ Testing Library Version: 1400
↳ Target Platform: arm64e-apple-macos14.0
◇ Test example() started.
✔ Test example() passed after 0.001 seconds.
✔ Test run with 1 test in 0 suites passed after 0.001 seconds.
```

### Add tests for your package

Extend the tests to work with the code in your library. Update the contents of `Tests/DeckOfPlayingCardsTests/DeckOfPlayingCardsTests.swift`:

```swift
import DeckOfPlayingCards
import PlayingCard
import Testing

struct DeckTests {
  @Test
  func standard52CardDeck() {
    var countByPlayingCard: [PlayingCard: Int] = [:]

    var deck = Deck.standard52CardDeck()
    while let playingCard = deck.deal() {
      countByPlayingCard[playingCard, default: 0] += 1
    }

    #expect(countByPlayingCard.count == 52)
    #expect(countByPlayingCard.values.allSatisfy({ $0 == 1 }))

    for rank in Rank.allCases {
      for suit in Suit.allCases {
        let playingCard = PlayingCard(rank: rank, suit: suit)
        #expect(countByPlayingCard[playingCard] == 1)
      }
    }
  }

  @Test
  func deal() {
    let playingCard = PlayingCard(rank: .ace, suit: .clubs)
    var deck: Deck = [playingCard]

    #expect(deck.deal() == playingCard)
    #expect(deck.deal() == nil)
  }

  @Test
  func countEmptyDeckHasZeroCards() {
    let deck = Deck()
    //XCTAssertEqual(deck.count, 0)
    #expect(deck.count == 0)
  }

  @Test
  func countStandard52CardDeckHas52Cards() {
    let deck = Deck.standard52CardDeck()

    #expect(deck.count == 52)
  }

  @Test
  func countDealingDecreasesCountByOne() throws {
    var deck = Deck([
      PlayingCard(rank: .ace, suit: .spades), PlayingCard(rank: .queen, suit: .hearts),
    ])

    #expect(deck.count == 2)
    try #require(deck.deal() != nil)
    #expect(deck.count == 1)
  }
}
```

Then when you run the tests again, you see each of the tests and their results:

```bash
Building for debugging...
[6/6] Linking DeckOfPlayingCardsPackageTests
Build complete! (0.44s)
Test Suite 'All tests' started at 2025-10-09 13:16:44.052.
Test Suite 'All tests' passed at 2025-10-09 13:16:44.052.
     Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
◇ Test run started.
↳ Testing Library Version: 1400
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite DeckTests started.
◇ Test deal() started.
◇ Test countStandard52CardDeckHas52Cards() started.
◇ Test countEmptyDeckHasZeroCards() started.
◇ Test standard52CardDeck() started.
◇ Test countDealingDecreasesCountByOne() started.
✔ Test countDealingDecreasesCountByOne() passed after 0.001 seconds.
✔ Test deal() passed after 0.001 seconds.
✔ Test countStandard52CardDeckHas52Cards() passed after 0.001 seconds.
✔ Test countEmptyDeckHasZeroCards() passed after 0.001 seconds.
✔ Test standard52CardDeck() passed after 0.001 seconds.
✔ Suite DeckTests passed after 0.001 seconds.
✔ Test run with 5 tests in 1 suite passed after 0.001 seconds.
```

> The complete code for the DeckOfPlayingCards example package can be found at [https://github.com/apple/example-package-deckofplayingcards](https://github.com/apple/example-package-deckofplayingcards).

### Share your package

You can use this package from other Swift packages locally, or share the package through a git hosting provider.
When you want to release your own package, create a git tag that matches the major, minor, and patch versions of a semantic version and push the tag to your git hosting provider.
For example, to tag the package with the semantic version `0.1`, which indicates that it's an initial minor release, use the tag `0.1.0`.

For more information about sharing packages, see [Releasing and publishing a Swift package](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/releasingpublishingapackage).

### Resolving transitive dependencies

The Package Manager resolves dependencies for the package you're using and all of its transitive dependencies.
Another example package, `Dealer`, illustrates how this works by using the example of the package this guide created.
You can explore the example package online at [https://github.com/swiftlang/example-package-dealer/](https://github.com/swiftlang/example-package-dealer/), or download it locally to explore:

```bash
git clone https://github.com/swiftlang/example-package-dealer.git
cd example-package-dealer
```

The dealer package includes an additional dependency to [Swift Argument Parser](https://github.com/apple/swift-argument-parser), a package that helps parse arguments for command-line applications.


To see the package resolution and choices, run the command `swift package resolve`.

```bash
Fetching https://github.com/swiftlang/example-package-deckofplayingcards.git
Fetching https://github.com/apple/swift-argument-parser.git from cache
Fetched https://github.com/swiftlang/example-package-deckofplayingcards.git from cache (0.41s)
Fetched https://github.com/apple/swift-argument-parser.git from cache (0.58s)
Computing version for https://github.com/swiftlang/example-package-deckofplayingcards.git
Computed https://github.com/swiftlang/example-package-deckofplayingcards.git at 4.0.0 (0.94s)
Fetching https://github.com/apple/example-package-playingcard.git from cache
Fetched https://github.com/apple/example-package-playingcard.git from cache (0.30s)
Computing version for https://github.com/apple/example-package-playingcard.git
Computed https://github.com/apple/example-package-playingcard.git at 4.0.0 (0.66s)
Computing version for https://github.com/apple/swift-argument-parser.git
Computed https://github.com/apple/swift-argument-parser.git at 1.6.1 (0.39s)
Creating working copy for https://github.com/apple/swift-argument-parser.git
Working copy of https://github.com/apple/swift-argument-parser.git resolved at 1.6.1
Creating working copy for https://github.com/apple/example-package-playingcard.git
Working copy of https://github.com/apple/example-package-playingcard.git resolved at 4.0.0
Creating working copy for https://github.com/swiftlang/example-package-deckofplayingcards.git
Working copy of https://github.com/swiftlang/example-package-deckofplayingcards.git resolved at 4.0.0
```

This process happens automatically when you run `swift build` or `swift test`, making the dependencies available for your project.
As with the previous package, you can build this package with `swift build`, and run and see the tests for the package using the command `swift test`.

As the dealer package provides a command-line executable, you can also run the executable built by the package using `swift run`:

```bash
[1/1] Planning build
Building for debugging...
[1/1] Write swift-version-2C315BDEC41BFF30.txt
Build of product 'dealer' complete! (0.13s)
Error: Missing expected argument '<count> ...'

OVERVIEW: Shuffles a deck of playing cards and deals a number of cards.

For each count argument, prints a line of tab-delimited cards to stdout,
or if there aren't enough cards remaining,
prints "Not enough cards" to stderr and exits with a nonzero status.

USAGE: dealer <count> ...

ARGUMENTS:
  <count>                 The number of cards to deal at a time.

OPTIONS:
  -h, --help              Show help information.
```

Specify the name of the executable along with any required arguments to try it out, for example `swift run dealer 5`:

```bash
Building for debugging...
[1/1] Write swift-version-2C315BDEC41BFF30.txt
Build of product 'dealer' complete! (0.07s)
♢ J    ♢ 3    ♢ 7    ♣︎ 5    ♡ 7
```

The build product from the package is also available in the `.build` directory by default, where you can also execute the tool directly.
For example, the debug build (the default) for the dealer package is available at `.build/debug/dealer`.
You can invoke that from the terminal: `.build/debug/dealer 5`

```bash
♠︎ 6    ♡ 4    ♣︎ 4    ♡ A    ♡ K
```
