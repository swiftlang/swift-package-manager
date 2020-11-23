/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch
import TSCBasic

import PackageModel

final class InMemoryPackageCollectionsSearch: PackageCollectionsSearch {
    let configuration: Configuration

    private let packageTrie: Trie<CollectionPackage>
    private let targetTrie: Trie<CollectionPackage>
    
    private var cache = [Model.CollectionIdentifier: Model.Collection]()
    private let cacheLock = Lock()
    
    private let tokenizer: Tokenizer = WordBoundaryTokenizer()
    
    // For indexing and executing queries
    private let queue = DispatchQueue(label: "org.swift.swiftpm.InMemoryPackageCollectionsSearch", attributes: .concurrent)
    
    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        self.packageTrie = Trie<CollectionPackage>()
        self.targetTrie = Trie<CollectionPackage>()
    }
    
    func index(collection: Model.Collection,
               callback: @escaping (Result<Void, Error>) -> Void) {
        self.queue.async {
            let group = DispatchGroup()
            
            collection.packages.forEach { package in
                group.enter()
                
                self.queue.async {
                    defer { group.leave() }
                    
                    let document = CollectionPackage(collection: collection.identifier, package: package.reference.identity)
        
                    // This breaks up the URL into tokens because it contains punctuations, so when the
                    // search query is a repository URL it will need to be tokenized the same way.
                    // `searchPackages` does this, but not sure this is a good thing? We don't provide
                    // options to NOT tokenize query string.
                    self.index(text: package.repository.url, foundIn: document, to: self.packageTrie)
                    // Index package identity without any transformation for `findPackage`
                    self.index(text: package.reference.identity.description, foundIn: document, to: self.packageTrie, analyze: false)

                    if let summary = package.summary {
                        self.index(text: summary, foundIn: document, to: self.packageTrie)
                    }
                    if let keywords = package.keywords {
                        keywords.forEach {
                            self.index(text: $0, foundIn: document, to: self.packageTrie)
                        }
                    }
                    package.versions.forEach { version in
                        self.index(text: version.packageName, foundIn: document, to: self.packageTrie)
                        version.products.forEach {
                            self.index(text: $0.name, foundIn: document, to: self.packageTrie)
                        }
                        version.targets.forEach {
                            self.index(text: $0.name, foundIn: document, to: self.packageTrie)
                            // Target search is not tokenized - it's either exact match or prefix match
                            self.index(text: $0.name, foundIn: document, to: self.targetTrie, analyze: false)
                        }
                    }
                }
            }
            
            group.notify(queue: self.queue) {
                self.cacheLock.withLock {
                    self.cache[collection.identifier] = collection
                }
                callback(.success(()))
            }
        }
    }
    
    private func index(text: String, foundIn document: CollectionPackage, to trie: Trie<CollectionPackage>, analyze: Bool = true) {
        if analyze {
            let tokens = self.analyze(text: text)
            tokens.forEach { trie.insert(word: $0, foundIn: document) }
        } else {
            trie.insert(word: text.lowercased(), foundIn: document)
        }
    }
    
    func remove(identifier: Model.CollectionIdentifier,
                callback: @escaping (Result<Void, Error>) -> Void) {
        self.queue.async {
            guard let collection = self.cacheLock.withLock({ self.cache.removeValue(forKey: identifier) }) else {
                return callback(.success(()))
            }
            
            let group = DispatchGroup()

            collection.packages.forEach { package in
                group.enter()
                
                self.queue.async {
                    defer { group.leave() }
                    
                    let document = CollectionPackage(collection: identifier, package: package.reference.identity)
                    self.packageTrie.remove(document: document)
                    self.targetTrie.remove(document: document)
                }
            }
            
            group.notify(queue: self.queue) {
                callback(.success(()))
            }
        }
    }
    
    func findPackage(identifier: PackageIdentity,
                     collectionIdentifiers: [Model.CollectionIdentifier]? = nil,
                     callback: @escaping (Result<Model.PackageSearchResult.Item, Error>) -> Void) {
        self.queue.async {
            let documents: Set<CollectionPackage>
            do {
                documents = try self.packageTrie.find(word: identifier.description)
            } catch { // This includes `NotFoundError`
                return callback(.failure(error))
            }

            let collectionIdentifiers: Set<Model.CollectionIdentifier>? = collectionIdentifiers.flatMap { Set($0) }
            let collections = documents.filter { collectionIdentifiers?.contains($0.collection) ?? true }
                .compactMap { collectionPackage in self.cacheLock.withLock { self.cache[collectionPackage.collection] } }
                // Sort collections by processing date so the latest metadata is first
                .sorted(by: { lhs, rhs in lhs.lastProcessedAt > rhs.lastProcessedAt })
            
            guard let package = collections.compactMap({ $0.packages.first { $0.reference.identity == identifier } }).first else {
                return callback(.failure(NotFoundError("\(identifier)")))
            }

            callback(.success(.init(package: package, collections: collections.map { $0.identifier })))
        }
    }
    
    func searchPackages(identifiers: [Model.CollectionIdentifier]? = nil,
                        query: String,
                        callback: @escaping (Result<Model.PackageSearchResult, Error>) -> Void) {
        self.queue.async {
            // Clean and break up query string into tokens
            let queryTokens = self.analyze(text: query)
    
            var queryResults = [String: Result<Set<CollectionPackage>, Error>]()
            let queryResultsLock = Lock()

            let group = DispatchGroup()

            queryTokens.forEach { token in
                group.enter()
                
                self.queue.async {
                    defer { group.leave() }

                    do {
                        let matches = try self.packageTrie.find(word: token)
                        queryResultsLock.withLock { queryResults[token] = .success(matches) }
                    } catch {
                        queryResultsLock.withLock { queryResults[token] = .failure(error) }
                    }
                }
            }

            group.notify(queue: self.queue) {
                let errors = queryResults.values.compactMap { $0.failure }.filter { !($0 is NotFoundError) }
                guard errors.isEmpty else {
                    return callback(.failure(MultipleErrors(errors)))
                }
                
                // We only want `CollectionPackage`s that match *all* tokens
                let collectionIdentifiers: Set<Model.CollectionIdentifier>? = identifiers.flatMap { Set($0) }
                let matchingCollectionPackages = queryResults.values
                    .compactMap { $0.success }
                    .reduce(into: [CollectionPackage: Int]()) { result, documents in
                        // Count matches for each `CollectionPackage`
                        documents.forEach {
                            result[$0] = (result[$0] ?? 0) + 1
                        }
                    }
                    .filter { collectionPackage, score in
                        // Qualified results must contain all query tokens
                        score == queryTokens.count && collectionIdentifiers?.contains(collectionPackage.collection) ?? true
                    }
                    .keys

                // Construct the result
                let packageCollections = matchingCollectionPackages
                    .reduce(into: [PackageIdentity: (package: Model.Package, collections: Set<Model.CollectionIdentifier>)]()) { result, collectionPackage in
                        var entry = result.removeValue(forKey: collectionPackage.package)
                        if entry == nil {
                            guard let package = self.cacheLock.withLock({
                                self.cache[collectionPackage.collection].flatMap { collection in
                                    collection.packages.first { $0.reference.identity == collectionPackage.package }
                                }
                            }) else {
                                return
                            }
                            entry = (package, .init())
                        }
                        
                        if var entry = entry {
                            entry.collections.insert(collectionPackage.collection)
                            result[collectionPackage.package] = entry
                        }
                    }
                
                let result = Model.PackageSearchResult(items: packageCollections.map { entry in
                    .init(package: entry.value.package, collections: Array(entry.value.collections))
                })
                callback(.success(result))
            }
        }
    }
    
    func searchTargets(identifiers: [Model.CollectionIdentifier]? = nil,
                       query: String,
                       type: Model.TargetSearchType,
                       callback: @escaping (Result<Model.TargetSearchResult, Error>) -> Void) {
        self.queue.async {
            let matches: [String: Set<CollectionPackage>]
            do {
                switch type {
                case .exactMatch:
                    matches = [query.lowercased(): try self.targetTrie.find(word: query)]
                case .prefix:
                    matches = try self.targetTrie.findWithPrefix(query)
                }
            } catch is NotFoundError {
                matches = [:]
            } catch {
                return callback(.failure(error))
            }

            let collectionIdentifiers: Set<Model.CollectionIdentifier>? = identifiers.flatMap { Set($0) }
            
            var packageCollections = [PackageIdentity: (package: Model.Package, collections: Set<Model.CollectionIdentifier>)]()
            var targetPackageVersions = [Model.Target: [PackageIdentity: Set<Model.TargetListResult.PackageVersion>]]()
            
            // Group `CollectionPackage`s by packages
            // For each matching target name, find the containing package version(s)
            matches.forEach { targetName, collectionPackages in
                collectionPackages.filter { collectionIdentifiers?.contains($0.collection) ?? true }.forEach { collectionPackage in
                    var packageEntry = packageCollections.removeValue(forKey: collectionPackage.package)
                    if packageEntry == nil {
                        guard let package = self.cacheLock.withLock({
                            self.cache[collectionPackage.collection].flatMap { collection in
                                collection.packages.first { $0.reference.identity == collectionPackage.package }
                            }
                        }) else {
                            return
                        }
                        packageEntry = (package, .init())
                    }

                    if var packageEntry = packageEntry {
                        packageEntry.collections.insert(collectionPackage.collection)
                        packageCollections[collectionPackage.package] = packageEntry

                        packageEntry.package.versions.forEach { version in
                            let targets = version.targets.filter { $0.name.lowercased() == targetName }
                            targets.forEach { target in
                                var targetEntry = targetPackageVersions.removeValue(forKey: target) ?? [:]
                                var targetPackageEntry = targetEntry.removeValue(forKey: packageEntry.package.reference.identity) ?? .init()
                                targetPackageEntry.insert(.init(version: version.version, packageName: version.packageName))
                                targetEntry[packageEntry.package.reference.identity] = targetPackageEntry
                                targetPackageVersions[target] = targetEntry
                            }
                        }
                    }
                }
            }

            let result = Model.TargetSearchResult(items: targetPackageVersions.map { target, packageVersions in
                let targetPackages: [Model.TargetListItem.Package] = packageVersions.compactMap { reference, versions in
                    guard let packageEntry = packageCollections[reference] else {
                        return nil
                    }
                    return Model.TargetListItem.Package(
                        repository: packageEntry.package.repository,
                        summary: packageEntry.package.summary,
                        versions: Array(versions).sorted(by: >),
                        collections: Array(packageEntry.collections)
                    )
                }
                return Model.TargetListItem(target: target, packages: targetPackages)
            })
            callback(.success(result))
        }
    }
    
    func analyze(text: String) -> [String] {
        var tokens = self.tokenizer.tokenize(text: text)
        tokens = TokenFilters.lowercase(tokens: tokens)
        tokens = TokenFilters.stopwords(tokens: tokens, stopwords: self.configuration.stopwords)
        return tokens
    }

    private struct CollectionPackage: Hashable, CustomStringConvertible {
        let collection: Model.CollectionIdentifier
        let package: PackageIdentity
        
        var description: String {
            "\(collection): \(package)"
        }
    }
    
    struct Configuration {
        // https://www.link-assistant.com/seo-stop-words.html
        static let stopwords: Set<String> = [
            "a", "am", "an", "and", "also", "are", "b", "be", "been", "being", "but",
            "c", "can", "cannot", "could", "d", "did", "do", "does", "doing", "done", "e",
            "f", "for", "from", "g", "h", "had", "has", "have", "he", "her", "hers", "him", "his", "how", "however",
            "i", "if", "in", "is", "it", "its", "j", "just", "k", "l", "let",
            "m", "may", "me", "might", "mine", "must", "my", "n", "not", "o", "of", "on", "or", "our", "ours",
            "p", "q", "r", "re", "s", "shall", "she", "should", "so",
            "t", "that", "the", "their", "theirs", "them", "then", "there", "these", "they", "this", "those", "to", "too",
            "u", "un", "us", "v",
            "w", "was", "we", "were", "what", "when", "where", "which", "while", "who", "whom", "whose", "why", "will", "with", "would",
            "x", "y", "yes", "yet", "you", "your", "yours", "z"
        ]
        
        var stopwords: Set<String>
        
        init(stopwords: Set<String>? = nil) {
            self.stopwords = stopwords ?? Self.stopwords
        }
    }
}

protocol Tokenizer {
    func tokenize(text: String) -> [String]
}

struct WordBoundaryTokenizer: Tokenizer {
    func tokenize(text: String) -> [String] {
        // Split on any character that is not a letter or a number
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

enum TokenFilters {
    static func lowercase(tokens: [String]) -> [String] {
        tokens.map { $0.lowercased() }
    }
    
    static func stopwords(tokens: [String], stopwords: Set<String> = []) -> [String] {
        tokens.filter { !stopwords.contains($0) }
    }
}
