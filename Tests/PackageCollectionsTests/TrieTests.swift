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

import Testing

@testable import PackageCollections

@Suite struct TrieTests {
    @Test func testContains() {
        let trie = Trie<Int>()

        let doc1 = "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"
        self.indexDocument(id: 1, contents: doc1, trie: trie)

        // Whole word match
        #expect(trie.contains(word: "brown", prefixMatch: false))
        #expect(trie.contains(word: "Fox", prefixMatch: false))
        #expect(!trie.contains(word: "foobar", prefixMatch: false))

        // Prefix match
        #expect(trie.contains(word: "d", prefixMatch: true))
        #expect(trie.contains(word: "Do", prefixMatch: true))
        #expect(!trie.contains(word: "doo", prefixMatch: true))
    }

    @Test func testFind() throws {
        let trie = Trie<Int>()

        let doc1 = "the quick brown fox jumps over the lazy dog and the dog does not notice the fox jumps over it"
        let doc2 = "the quick brown fox jumps over the lazy dog for the lazy dog has blocked its way for far too long"
        self.indexDocument(id: 1, contents: doc1, trie: trie)
        self.indexDocument(id: 2, contents: doc2, trie: trie)

        #expect(try trie.find(word: "brown") == [1, 2])
        #expect(try trie.find(word: "blocked") == [2])
        #expect(throws:NotFoundError.self) {
            try trie.find(word: "fo")
        }
    }

    func testFindWithPrefix() throws {
        let trie = Trie<Int>()

        let doc1 = "the quick brown fox jumps over the lazy dog and the dog does not notice the fox jumps over it"
        let doc2 = "the quick brown fox jumps over the lazy dog for the lazy dog has blocked its way for far too long"
        self.indexDocument(id: 1, contents: doc1, trie: trie)
        self.indexDocument(id: 2, contents: doc2, trie: trie)

        #expect(try trie.findWithPrefix("f") == ["fox": [1, 2], "for": [2], "far": [2]])
        #expect(try trie.findWithPrefix("fo") == ["fox": [1, 2], "for": [2]])
        #expect(try trie.findWithPrefix("far") == ["far": [2]])
        #expect(throws: NotFoundError.self) {
            try trie.findWithPrefix("foo")
        }
    }

    @Test func testRemoveDocument() throws {
        let trie = Trie<Int>()

        let doc1 = "the quick brown fox jumps over the lazy dog"
        let doc2 = "the dog does not notice the fox jumps over it"
        let doc3 = "it has blocked the fox for far too long"
        self.indexDocument(id: 1, contents: doc1, trie: trie)
        self.indexDocument(id: 2, contents: doc2, trie: trie)
        self.indexDocument(id: 3, contents: doc3, trie: trie)

        #expect(try trie.find(word: "fox") == [1, 2, 3])
        #expect(try trie.find(word: "dog") == [1, 2])
        #expect(try trie.find(word: "it") == [2, 3])
        #expect(try trie.find(word: "lazy") == [1])
        #expect(try trie.find(word: "notice") == [2])
        #expect(try trie.find(word: "blocked") == [3])

        trie.remove(document: 3)

        #expect(try trie.find(word: "fox") == [1, 2])
        #expect(try trie.find(word: "dog") == [1, 2])
        #expect(try trie.find(word: "it") == [2])
        #expect(try trie.find(word: "lazy") == [1])
        #expect(try trie.find(word: "notice") == [2])
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "blocked")
        }

        trie.remove(document: 1)

        #expect(try trie.find(word: "fox") == [2])
        #expect(try trie.find(word: "dog") == [2])
        #expect(try trie.find(word: "it") == [2])
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "lazy")
        }
        #expect(try trie.find(word: "notice") == [2])
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "blocked")
        }

        trie.remove(document: 2)

        #expect(throws: NotFoundError.self) {
            try trie.find(word: "fox")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "dog")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "it")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "lazy")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "notice")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "blocked")
        }
    }

    func testRemoveDocumentsWithPredicate() throws {
        let trie = Trie<Int>()

        let doc1 = "the quick brown fox jumps over the lazy dog"
        let doc2 = "the dog does not notice the fox jumps over it"
        let doc3 = "it has blocked the fox for far too long"
        self.indexDocument(id: 1, contents: doc1, trie: trie)
        self.indexDocument(id: 2, contents: doc2, trie: trie)
        self.indexDocument(id: 3, contents: doc3, trie: trie)

        #expect(try trie.find(word: "fox") == [1, 2, 3])
        #expect(try trie.find(word: "dog") == [1, 2])
        #expect(try trie.find(word: "it") == [2, 3])
        #expect(try trie.find(word: "lazy") == [1])
        #expect(try trie.find(word: "notice") == [2])
        #expect(try trie.find(word: "blocked") == [3])

        trie.remove { $0 == 3 }

        #expect(try trie.find(word: "fox") == [1, 2])
        #expect(try trie.find(word: "dog") == [1, 2])
        #expect(try trie.find(word: "it") == [2])
        #expect(try trie.find(word: "lazy") == [1])
        #expect(try trie.find(word: "notice") == [2])
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "blocked")
        }

        trie.remove { $0 == 1 }

        #expect(try trie.find(word: "fox") == [2])
        #expect(try trie.find(word: "dog") == [2])
        #expect(try trie.find(word: "it") == [2])
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "lazy")
        }
        #expect(try trie.find(word: "notice") == [2])
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "blocked")
        }

        trie.remove { $0 == 2 }

        #expect(throws: NotFoundError.self) {
            try trie.find(word: "fox")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "dog")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "it")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "lazy")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "notice")
        }
        #expect(throws: NotFoundError.self) {
            try trie.find(word: "blocked")
        }
    }

    private func indexDocument(id: Int, contents: String, trie: Trie<Int>) {
        let words = contents.components(separatedBy: " ")
        words.forEach { word in
            trie.insert(word: word, foundIn: id)
        }
    }

    @Test func testThreadSafe() async throws {
        let trie = Trie<Int>()

        let docCount = 100
        await withTaskGroup { group in
            for i in 0 ..< docCount {
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(Double.random(in: 100...300)))

                    trie.remove { $0 == i }
                    trie.insert(word: "word-\(i)", foundIn: i)
                    trie.insert(word: "test", foundIn: i)
                }
            }
            await group.waitForAll()
        }
        for doc in 0 ..< docCount {
            #expect(try trie.find(word: "word-\(doc)") == [doc])
            #expect(try trie.find(word: "test").count == docCount)
        }
    }
}
