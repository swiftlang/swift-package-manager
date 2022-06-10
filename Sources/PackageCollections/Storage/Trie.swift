//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class Foundation.NSLock
import PackageModel

struct Trie<Document: Hashable> {
    private typealias Node = TrieNode<Character, Document>

    private let root: Node
    private let lock = NSLock()

    init() {
        self.root = Node()
    }

    /// Inserts a word and its document to the trie.
    func insert(word: String, foundIn document: Document) {
        guard !word.isEmpty else { return }

        self.lock.withLock {
            var currentNode = self.root
            // Check if word already exists otherwise creates the node path
            for character in word.lowercased() {
                if let child = currentNode.children[character] {
                    currentNode = child
                } else {
                    currentNode = currentNode.add(value: character)
                }
            }

            currentNode.add(document: document)
        }
    }

    /// Removes word occurrences found in the given document.
    func remove(document: Document) {
        func removeInSubTrie(root: Node, document: Document) {
            if root.isTerminating {
                root.remove(document: document)
            }

            // Clean up sub-tries
            root.children.values.forEach {
                removeInSubTrie(root: $0, document: document)
            }

            root.children.forEach { value, node in
                // If a child node doesn't have children (i.e., there are no words under it),
                // and itself is not a word, delete it since its path has become a deadend.
                if node.isLeaf, !node.isTerminating {
                    root.remove(value: value)
                }
            }
        }

        self.lock.withLock {
            removeInSubTrie(root: self.root, document: document)
        }
    }

    /// Removes word occurrences found in matching document(s).
    func remove(where predicate: @escaping (Document) -> Bool) {
        func removeInSubTrie(root: Node, where predicate: @escaping (Document) -> Bool) {
            if root.isTerminating {
                root.remove(where: predicate)
            }

            // Clean up sub-tries
            root.children.values.forEach {
                removeInSubTrie(root: $0, where: predicate)
            }

            root.children.forEach { value, node in
                // If a child node doesn't have children (i.e., there are no words under it),
                // and itself is not a word, delete it since its path has become a deadend.
                if node.isLeaf, !node.isTerminating {
                    root.remove(value: value)
                }
            }
        }

        self.lock.withLock {
            removeInSubTrie(root: self.root, where: predicate)
        }
    }

    /// Checks if the trie contains the exact word or words with matching prefix.
    func contains(word: String, prefixMatch: Bool = false) -> Bool {
        guard let node = self.findLastNodeOf(word: word) else {
            return false
        }
        return prefixMatch || node.isTerminating
    }

    /// Finds the word in this trie and returns its documents.
    func find(word: String) throws -> Set<Document> {
        guard let node = self.findLastNodeOf(word: word), node.isTerminating else {
            throw NotFoundError(word)
        }
        return node.documents
    }

    /// Finds words with matching prefix in this trie and returns their documents.
    func findWithPrefix(_ prefix: String) throws -> [String: Set<Document>] {
        guard let node = self.findLastNodeOf(word: prefix) else {
            throw NotFoundError(prefix)
        }

        func wordsInSubTrie(root: Node, prefix: String) -> [String: Set<Document>] {
            precondition(root.value != nil, "Sub-trie root's value should not be nil")

            var subTrieWords = [String: Set<Document>]()

            // Construct the new prefix by adding the sub-trie root's character
            var previousCharacters = prefix
            previousCharacters.append(root.value!.lowercased()) // !-safe; see precondition

            // The root actually forms a word
            if root.isTerminating {
                subTrieWords[previousCharacters] = root.documents
            }

            // Collect all words under this sub-trie
            root.children.values.forEach {
                let childWords = wordsInSubTrie(root: $0, prefix: previousCharacters)
                subTrieWords.merge(childWords, uniquingKeysWith: { _, child in child })
            }

            return subTrieWords
        }

        var words = [String: Set<Document>]()

        let prefix = prefix.lowercased()
        // The prefix is actually a word
        if node.isTerminating {
            words[prefix] = node.documents
        }

        node.children.values.forEach {
            let childWords = wordsInSubTrie(root: $0, prefix: prefix)
            words.merge(childWords, uniquingKeysWith: { _, child in child })
        }

        return words
    }

    /// Finds the last node in the path of the given word if it exists in this trie.
    private func findLastNodeOf(word: String) -> Node? {
        guard !word.isEmpty else { return nil }

        return self.lock.withLock {
            var currentNode = self.root
            // Traverse down the trie as far as we can
            for character in word.lowercased() {
                guard let child = currentNode.children[character] else {
                    return nil
                }
                currentNode = child
            }
            return currentNode
        }
    }
}

private final class TrieNode<T: Hashable, Document: Hashable> {
    /// The value (i.e., character) that this node stores. `nil` if root.
    let value: T?

    /// The parent of this node. `nil` if root.
    private weak var parent: TrieNode<T, Document>?

    /// The children of this node identified by their corresponding value.
    private var _children = [T: TrieNode<T, Document>]()
    private let childrenLock = NSLock()

    /// If the path to this node forms a valid word, these are the documents where the word can be found.
    private var _documents = Set<Document>()
    private let documentsLock = NSLock()

    var isLeaf: Bool {
        self.childrenLock.withLock {
            self._children.isEmpty
        }
    }

    /// `true` indicates the path to this node forms a valid word.
    var isTerminating: Bool {
        self.documentsLock.withLock {
            !self._documents.isEmpty
        }
    }

    var children: [T: TrieNode<T, Document>] {
        self.childrenLock.withLock {
            self._children
        }
    }

    var documents: Set<Document> {
        self.documentsLock.withLock {
            self._documents
        }
    }

    init(value: T? = nil, parent: TrieNode<T, Document>? = nil) {
        self.value = value
        self.parent = parent
    }

    /// Adds a subpath under this node.
    func add(value: T) -> TrieNode<T, Document> {
        self.childrenLock.withLock {
            if let existing = self._children[value] {
                return existing
            }

            let child = TrieNode<T, Document>(value: value, parent: self)
            self._children[value] = child
            return child
        }
    }

    /// Removes a subpath from this node.
    func remove(value: T) {
        _ = self.childrenLock.withLock {
            self._children.removeValue(forKey: value)
        }
    }

    /// Adds a document in which the word formed by path leading to this node can be found.
    func add(document: Document) {
        _ = self.documentsLock.withLock {
            self._documents.insert(document)
        }
    }

    /// Removes a referenced document.
    func remove(document: Document) {
        _ = self.documentsLock.withLock {
            self._documents.remove(document)
        }
    }

    /// Removes documents that satisfy the given predicate.
    func remove(where predicate: @escaping (Document) -> Bool) {
        self.documentsLock.withLock {
            for document in self._documents {
                if predicate(document) {
                    self._documents.remove(document)
                }
            }
        }
    }
}
