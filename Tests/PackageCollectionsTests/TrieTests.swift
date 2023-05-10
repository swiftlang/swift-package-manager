//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest

@testable import PackageCollections

class TrieTests: XCTestCase {
    func testContains() {
        let trie = Trie<Int>()

        let doc1 = "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"
        self.indexDocument(id: 1, contents: doc1, trie: trie)

        // Whole word match
        XCTAssertTrue(trie.contains(word: "brown", prefixMatch: false))
        XCTAssertTrue(trie.contains(word: "Fox", prefixMatch: false))
        XCTAssertFalse(trie.contains(word: "foobar", prefixMatch: false))

        // Prefix match
        XCTAssertTrue(trie.contains(word: "d", prefixMatch: true))
        XCTAssertTrue(trie.contains(word: "Do", prefixMatch: true))
        XCTAssertFalse(trie.contains(word: "doo", prefixMatch: true))
    }

    func testFind() {
        let trie = Trie<Int>()

        let doc1 = "the quick brown fox jumps over the lazy dog and the dog does not notice the fox jumps over it"
        let doc2 = "the quick brown fox jumps over the lazy dog for the lazy dog has blocked its way for far too long"
        self.indexDocument(id: 1, contents: doc1, trie: trie)
        self.indexDocument(id: 2, contents: doc2, trie: trie)

        XCTAssertEqual(try trie.find(word: "brown"), [1, 2])
        XCTAssertEqual(try trie.find(word: "blocked"), [2])
        XCTAssertThrowsError(try trie.find(word: "fo"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
    }

    func testFindWithPrefix() {
        let trie = Trie<Int>()

        let doc1 = "the quick brown fox jumps over the lazy dog and the dog does not notice the fox jumps over it"
        let doc2 = "the quick brown fox jumps over the lazy dog for the lazy dog has blocked its way for far too long"
        self.indexDocument(id: 1, contents: doc1, trie: trie)
        self.indexDocument(id: 2, contents: doc2, trie: trie)

        XCTAssertEqual(try trie.findWithPrefix("f"), ["fox": [1, 2], "for": [2], "far": [2]])
        XCTAssertEqual(try trie.findWithPrefix("fo"), ["fox": [1, 2], "for": [2]])
        XCTAssertEqual(try trie.findWithPrefix("far"), ["far": [2]])
        XCTAssertThrowsError(try trie.findWithPrefix("foo"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
    }

    func testRemoveDocument() {
        let trie = Trie<Int>()

        let doc1 = "the quick brown fox jumps over the lazy dog"
        let doc2 = "the dog does not notice the fox jumps over it"
        let doc3 = "it has blocked the fox for far too long"
        self.indexDocument(id: 1, contents: doc1, trie: trie)
        self.indexDocument(id: 2, contents: doc2, trie: trie)
        self.indexDocument(id: 3, contents: doc3, trie: trie)

        XCTAssertEqual(try trie.find(word: "fox"), [1, 2, 3])
        XCTAssertEqual(try trie.find(word: "dog"), [1, 2])
        XCTAssertEqual(try trie.find(word: "it"), [2, 3])
        XCTAssertEqual(try trie.find(word: "lazy"), [1])
        XCTAssertEqual(try trie.find(word: "notice"), [2])
        XCTAssertEqual(try trie.find(word: "blocked"), [3])

        trie.remove(document: 3)

        XCTAssertEqual(try trie.find(word: "fox"), [1, 2])
        XCTAssertEqual(try trie.find(word: "dog"), [1, 2])
        XCTAssertEqual(try trie.find(word: "it"), [2])
        XCTAssertEqual(try trie.find(word: "lazy"), [1])
        XCTAssertEqual(try trie.find(word: "notice"), [2])
        XCTAssertThrowsError(try trie.find(word: "blocked"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }

        trie.remove(document: 1)

        XCTAssertEqual(try trie.find(word: "fox"), [2])
        XCTAssertEqual(try trie.find(word: "dog"), [2])
        XCTAssertEqual(try trie.find(word: "it"), [2])
        XCTAssertThrowsError(try trie.find(word: "lazy"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertEqual(try trie.find(word: "notice"), [2])
        XCTAssertThrowsError(try trie.find(word: "blocked"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }

        trie.remove(document: 2)

        XCTAssertThrowsError(try trie.find(word: "fox"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "dog"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "it"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "lazy"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "notice"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "blocked"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
    }

    func testRemoveDocumentsWithPredicate() {
        let trie = Trie<Int>()

        let doc1 = "the quick brown fox jumps over the lazy dog"
        let doc2 = "the dog does not notice the fox jumps over it"
        let doc3 = "it has blocked the fox for far too long"
        self.indexDocument(id: 1, contents: doc1, trie: trie)
        self.indexDocument(id: 2, contents: doc2, trie: trie)
        self.indexDocument(id: 3, contents: doc3, trie: trie)

        XCTAssertEqual(try trie.find(word: "fox"), [1, 2, 3])
        XCTAssertEqual(try trie.find(word: "dog"), [1, 2])
        XCTAssertEqual(try trie.find(word: "it"), [2, 3])
        XCTAssertEqual(try trie.find(word: "lazy"), [1])
        XCTAssertEqual(try trie.find(word: "notice"), [2])
        XCTAssertEqual(try trie.find(word: "blocked"), [3])

        trie.remove { $0 == 3 }

        XCTAssertEqual(try trie.find(word: "fox"), [1, 2])
        XCTAssertEqual(try trie.find(word: "dog"), [1, 2])
        XCTAssertEqual(try trie.find(word: "it"), [2])
        XCTAssertEqual(try trie.find(word: "lazy"), [1])
        XCTAssertEqual(try trie.find(word: "notice"), [2])
        XCTAssertThrowsError(try trie.find(word: "blocked"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }

        trie.remove { $0 == 1 }

        XCTAssertEqual(try trie.find(word: "fox"), [2])
        XCTAssertEqual(try trie.find(word: "dog"), [2])
        XCTAssertEqual(try trie.find(word: "it"), [2])
        XCTAssertThrowsError(try trie.find(word: "lazy"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertEqual(try trie.find(word: "notice"), [2])
        XCTAssertThrowsError(try trie.find(word: "blocked"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }

        trie.remove { $0 == 2 }

        XCTAssertThrowsError(try trie.find(word: "fox"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "dog"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "it"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "lazy"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "notice"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
        XCTAssertThrowsError(try trie.find(word: "blocked"), "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
    }

    private func indexDocument(id: Int, contents: String, trie: Trie<Int>) {
        let words = contents.components(separatedBy: " ")
        words.forEach { word in
            trie.insert(word: word, foundIn: id)
        }
    }

    func testThreadSafe() {
        let queue = DispatchQueue(label: "TrieTests", attributes: .concurrent)
        let trie = Trie<Int>()
        let docCount = 100

        for _ in 0 ..< 100 {
            let sync = DispatchGroup()

            for i in 0 ..< docCount {
                queue.async(group: sync) {
                    Thread.sleep(forTimeInterval: Double.random(in: 100 ... 300) * 1.0e-6)

                    trie.remove { $0 == i }
                    trie.insert(word: "word-\(i)", foundIn: i)
                    trie.insert(word: "test", foundIn: i)
                }
            }

            switch sync.wait(timeout: .now() + 1) {
            case .timedOut:
                XCTFail("timeout")
            case .success:
                for doc in 0 ..< docCount {
                    XCTAssertEqual(try trie.find(word: "word-\(doc)"), [doc])
                    XCTAssertEqual(try trie.find(word: "test").count, docCount)
                }
            }
        }
    }
}
