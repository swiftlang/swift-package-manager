/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch
import Foundation
import TSCBasic
import TSCUtility
import XCTest

@testable import PackageCollections
import SourceControl

class InMemoryPackageCollectionsSearchTests: XCTestCase {
    func testAnalyze() {
        let search = InMemoryPackageCollectionsSearch()
        let text = "The quick brown fox jumps over the lazy dog, for the lazy dog has blocked its way for far too long."
        let tokens = search.analyze(text: text)
        XCTAssertEqual(["quick", "brown", "fox", "jumps", "over", "lazy", "dog", "lazy", "dog", "blocked", "way", "far", "long"], tokens)
    }
    
    func testRemove() throws {
        let search = InMemoryPackageCollectionsSearch()

        let mockTargets = [UUID().uuidString, UUID().uuidString].map {
            PackageCollectionsModel.Target(name: $0, moduleName: $0)
        }

        let mockProducts = [PackageCollectionsModel.Product(name: UUID().uuidString, type: .executable, targets: [mockTargets.first!]),
                            PackageCollectionsModel.Product(name: UUID().uuidString, type: .executable, targets: mockTargets)]

        let mockVersion = PackageCollectionsModel.Package.Version(version: TSCUtility.Version(1, 0, 0),
                                                                  packageName: UUID().uuidString,
                                                                  targets: mockTargets,
                                                                  products: mockProducts,
                                                                  toolsVersion: .currentToolsVersion,
                                                                  minimumPlatformVersions: nil,
                                                                  verifiedPlatforms: nil,
                                                                  verifiedSwiftVersions: nil,
                                                                  license: nil)

        let mockPackage = PackageCollectionsModel.Package(repository: .init(url: "https://packages.mock/\(UUID().uuidString)"),
                                                          summary: UUID().uuidString,
                                                          keywords: [UUID().uuidString, UUID().uuidString],
                                                          versions: [mockVersion],
                                                          latestVersion: mockVersion,
                                                          watchersCount: nil,
                                                          readmeURL: nil,
                                                          authors: nil)

        let mockCollection = PackageCollectionsModel.Collection(source: .init(type: .json, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                name: UUID().uuidString,
                                                                overview: UUID().uuidString,
                                                                keywords: [UUID().uuidString, UUID().uuidString],
                                                                packages: [mockPackage],
                                                                createdAt: Date(),
                                                                createdBy: nil)

        let mockCollection2 = PackageCollectionsModel.Collection(source: .init(type: .json, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                 name: UUID().uuidString,
                                                                 overview: UUID().uuidString,
                                                                 keywords: [UUID().uuidString, UUID().uuidString],
                                                                 packages: [mockPackage],
                                                                 createdAt: Date(),
                                                                 createdBy: nil)

        let mockCollections = [mockCollection, mockCollection2]
        
        try mockCollections.forEach { collection in
            try tsc_await { callback in search.index(collection: collection, callback: callback) }
        }
        
        do {
            // search by package name
            let searchResult = try tsc_await { callback in search.searchPackages(query: mockVersion.packageName, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), mockCollections.map { $0.identifier }.sorted(), "list count should match")
        }
        
        // Remove a collection
        try tsc_await { callback in search.remove(identifier: mockCollection.identifier, callback: callback) }
        
        // It should no longer show up in results
        do {
            // search by package name
            let searchResult = try tsc_await { callback in search.searchPackages(query: mockVersion.packageName, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections, [mockCollection2.identifier], "list count should match")
        }
    }
    
    func testFindPackage() throws {
        let search = InMemoryPackageCollectionsSearch()
        
        let mockCollections = makeMockCollections()
        let expectedPackage = mockCollections.last!.packages.last!

        let group = DispatchGroup()
        mockCollections.forEach { collection in
            group.enter()
            search.index(collection: collection) { _ in group.leave() }
        }
        group.wait()

        let metadata = try tsc_await { callback in search.findPackage(identifier: expectedPackage.reference.identity, callback: callback) }

        let expectedCollections = Set(mockCollections.filter { $0.packages.map { $0.reference }.contains(expectedPackage.reference) }.map { $0.identifier })
        XCTAssertEqual(Set(metadata.collections), expectedCollections, "collections should match")

        XCTAssertEqual(metadata.package, expectedPackage, "package should match")
    }
    
    func testFindPackage_notFound() throws {
        let search = InMemoryPackageCollectionsSearch()
        let expectedPackage = makeMockCollections().first!.packages.first!

        XCTAssertThrowsError(try tsc_await { callback in search.findPackage(identifier: expectedPackage.reference.identity, callback: callback) }, "expected error") { error in
            XCTAssert(error is NotFoundError)
        }
    }
    
    func testFindPackage_mostRecentFirst() throws {
        let search = InMemoryPackageCollectionsSearch()

        var date = Date()
        let mockCollections: [Model.Collection] = makeMockCollections(count: 2).map {
            date.addTimeInterval(-1)
            return Model.Collection(
                source: $0.source,
                name: $0.name,
                overview: $0.overview,
                keywords: $0.keywords,
                packages: $0.packages,
                createdAt: $0.createdAt,
                createdBy: $0.createdBy,
                lastProcessedAt: date
            )
        }
        // Most recent lastProcessedAt
        let expectedPackage = mockCollections.first!.packages.first!

        try mockCollections.forEach { collection in
            try tsc_await { callback in search.index(collection: collection, callback: callback) }
        }

        let metadata = try tsc_await { callback in search.findPackage(identifier: expectedPackage.reference.identity, callback: callback) }

        let expectedCollections = Set(mockCollections.filter { $0.packages.map { $0.reference }.contains(expectedPackage.reference) }.map { $0.identifier })
        XCTAssertEqual(Set(metadata.collections), expectedCollections, "collections should match")

        XCTAssertEqual(metadata.package, expectedPackage, "package should match")
    }
    
    func testFindPackagePerformance() throws {
        #if ENABLE_COLLECTION_PERF_TESTS
        #else
        try XCTSkipIf(true)
        #endif
        
        let search = InMemoryPackageCollectionsSearch()

        let mockCollections = makeMockCollections(count: 1000)
        let expectedPackage = mockCollections.last!.packages.last!

        let group = DispatchGroup()
        mockCollections.forEach { collection in
            group.enter()
            search.index(collection: collection) { _ in group.leave() }
        }
        group.wait()

        let start = Date()
        let metadata = try tsc_await { callback in search.findPackage(identifier: expectedPackage.reference.identity, callback: callback) }
        XCTAssertNotNil(metadata)
        let delta = Date().timeIntervalSince(start)
        XCTAssert(delta < 1.0, "should fetch quickly, took \(delta)")
    }

    // This is an equivalent of PackageCollectionsTests.testPackageSearch
    func testSearchPackages() throws {
        let search = InMemoryPackageCollectionsSearch()

        var mockCollections = makeMockCollections()

        let mockTargets = [UUID().uuidString, UUID().uuidString].map {
            PackageCollectionsModel.Target(name: $0, moduleName: $0)
        }

        let mockProducts = [PackageCollectionsModel.Product(name: UUID().uuidString, type: .executable, targets: [mockTargets.first!]),
                            PackageCollectionsModel.Product(name: UUID().uuidString, type: .executable, targets: mockTargets)]

        let mockVersion = PackageCollectionsModel.Package.Version(version: TSCUtility.Version(1, 0, 0),
                                                                  packageName: UUID().uuidString,
                                                                  targets: mockTargets,
                                                                  products: mockProducts,
                                                                  toolsVersion: .currentToolsVersion,
                                                                  minimumPlatformVersions: nil,
                                                                  verifiedPlatforms: nil,
                                                                  verifiedSwiftVersions: nil,
                                                                  license: nil)

        let mockPackage = PackageCollectionsModel.Package(repository: .init(url: "https://packages.mock/\(UUID().uuidString)"),
                                                          summary: UUID().uuidString,
                                                          keywords: [UUID().uuidString, UUID().uuidString],
                                                          versions: [mockVersion],
                                                          latestVersion: mockVersion,
                                                          watchersCount: nil,
                                                          readmeURL: nil,
                                                          authors: nil)

        let mockCollection = PackageCollectionsModel.Collection(source: .init(type: .json, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                name: UUID().uuidString,
                                                                overview: UUID().uuidString,
                                                                keywords: [UUID().uuidString, UUID().uuidString],
                                                                packages: [mockPackage],
                                                                createdAt: Date(),
                                                                createdBy: nil)

        let mockCollection2 = PackageCollectionsModel.Collection(source: .init(type: .json, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                 name: UUID().uuidString,
                                                                 overview: UUID().uuidString,
                                                                 keywords: [UUID().uuidString, UUID().uuidString],
                                                                 packages: [mockPackage],
                                                                 createdAt: Date(),
                                                                 createdBy: nil)

        let expectedCollections = [mockCollection, mockCollection2]
        let expectedCollectionsIdentifiers = expectedCollections.map { $0.identifier }.sorted()

        mockCollections.append(contentsOf: expectedCollections)
        
        let group = DispatchGroup()
        mockCollections.forEach { collection in
            group.enter()
            search.index(collection: collection) { _ in group.leave() }
        }
        group.wait()
        
        do {
            // search by package name
            let searchResult = try tsc_await { callback in search.searchPackages(query: mockVersion.packageName, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifiers, "list count should match")
        }
        
        do {
            // search by package description/summary
            let searchResult = try tsc_await { callback in search.searchPackages(query: mockPackage.summary!, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifiers, "list count should match")
        }
        
        do {
            // search by package keywords
            let searchResult = try tsc_await { callback in search.searchPackages(query: mockPackage.keywords!.first!, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifiers, "list count should match")
        }
        
        // FIXME: the code tokenizes the query (i.e., URL) which might not be desired?
        do {
            // search by package repository url
            let searchResult = try tsc_await { callback in search.searchPackages(query: mockPackage.repository.url, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifiers, "collections should match")
        }
        
        do {
            // search by package repository url base name
            let searchResult = try tsc_await { callback in search.searchPackages(query: mockPackage.repository.basename, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifiers, "collections should match")
        }
        
        do {
            // search by product name
            let searchResult = try tsc_await { callback in search.searchPackages(query: mockProducts.first!.name, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifiers, "list count should match")
        }
        
        do {
            // search by target name
            let searchResult = try tsc_await { callback in search.searchPackages(query: mockTargets.first!.name, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifiers, "collections should match")
        }
        
        do {
            // empty search
            let searchResult = try tsc_await { callback in search.searchPackages(query: UUID().uuidString, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 0, "list count should match")
        }
    }
    
    // This is an equivalent of PackageCollectionsTests.testPackageSearchPerformance
    func testSearchPackagesPerformance() throws {
        #if ENABLE_COLLECTION_PERF_TESTS
        #else
        try XCTSkipIf(true)
        #endif

        let search = InMemoryPackageCollectionsSearch()

        let mockCollections = makeMockCollections(count: 1000, maxPackages: 20)

        let group = DispatchGroup()
        mockCollections.forEach { collection in
            group.enter()
            search.index(collection: collection) { _ in group.leave() }
        }
        group.wait()
        
        // search by package name
        let start = Date()
        let repoName = mockCollections.last!.packages.last!.repository.basename
        let searchResult = try tsc_await { callback in search.searchPackages(query: repoName, callback: callback) }
        XCTAssert(searchResult.items.count > 0, "should get results")
        let delta = Date().timeIntervalSince(start)
        XCTAssert(delta < 1.0, "should search quickly, took \(delta)")
    }
    
    // This is an equivalent of PackageCollectionsTests.testTargetsSearch
    func testSearchTargets() throws {
        let search = InMemoryPackageCollectionsSearch()
        
        var mockCollections = makeMockCollections()

        let mockTargets = [UUID().uuidString, UUID().uuidString].map {
            PackageCollectionsModel.Target(name: $0, moduleName: $0)
        }

        let mockProducts = [PackageCollectionsModel.Product(name: UUID().uuidString, type: .executable, targets: [mockTargets.first!]),
                            PackageCollectionsModel.Product(name: UUID().uuidString, type: .executable, targets: mockTargets)]

        let mockVersion = PackageCollectionsModel.Package.Version(version: TSCUtility.Version(1, 0, 0),
                                                                  packageName: UUID().uuidString,
                                                                  targets: mockTargets,
                                                                  products: mockProducts,
                                                                  toolsVersion: .currentToolsVersion,
                                                                  minimumPlatformVersions: nil,
                                                                  verifiedPlatforms: nil,
                                                                  verifiedSwiftVersions: nil,
                                                                  license: nil)

        let mockPackage = PackageCollectionsModel.Package(repository: RepositorySpecifier(url: "https://packages.mock/\(UUID().uuidString)"),
                                                          summary: UUID().uuidString,
                                                          keywords: [UUID().uuidString, UUID().uuidString],
                                                          versions: [mockVersion],
                                                          latestVersion: mockVersion,
                                                          watchersCount: nil,
                                                          readmeURL: nil,
                                                          authors: nil)

        let mockCollection = PackageCollectionsModel.Collection(source: .init(type: .json, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                name: UUID().uuidString,
                                                                overview: UUID().uuidString,
                                                                keywords: [UUID().uuidString, UUID().uuidString],
                                                                packages: [mockPackage],
                                                                createdAt: Date(),
                                                                createdBy: nil)

        let mockCollection2 = PackageCollectionsModel.Collection(source: .init(type: .json, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                 name: UUID().uuidString,
                                                                 overview: UUID().uuidString,
                                                                 keywords: [UUID().uuidString, UUID().uuidString],
                                                                 packages: [mockPackage],
                                                                 createdAt: Date(),
                                                                 createdBy: nil)

        let expectedCollections = [mockCollection, mockCollection2]
        let expectedCollectionsIdentifiers = expectedCollections.map { $0.identifier }.sorted()

        mockCollections.append(contentsOf: expectedCollections)

        let group = DispatchGroup()
        mockCollections.forEach { collection in
            group.enter()
            search.index(collection: collection) { _ in group.leave() }
        }
        group.wait()

        do {
            // search by exact target name
            let searchResult = try tsc_await { callback in search.searchTargets(query: mockTargets.first!.name, type: .exactMatch, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.packages.map { $0.repository }, [mockPackage.repository], "packages should match")
            XCTAssertEqual(searchResult.items.first?.packages.flatMap { $0.collections }.sorted(), expectedCollectionsIdentifiers, "collections should match")
        }

        do {
            // search by prefix target name
            let searchResult = try tsc_await { callback in search.searchTargets(query: String(mockTargets.first!.name.prefix(mockTargets.first!.name.count - 1)), type: .prefix, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.packages.map { $0.repository }, [mockPackage.repository], "packages should match")
            XCTAssertEqual(searchResult.items.first?.packages.flatMap { $0.collections }.sorted(), expectedCollectionsIdentifiers, "collections should match")
        }

        do {
            // empty search
            let searchResult = try tsc_await { callback in search.searchTargets(query: UUID().uuidString, type: .exactMatch, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 0, "list count should match")
        }
    }
    
    // This is an equivalent of PackageCollectionsTests.testTargetsSearchPerformance
    func testSearchTargetsPerformance() throws {
        #if ENABLE_COLLECTION_PERF_TESTS
        #else
        try XCTSkipIf(true)
        #endif

        let search = InMemoryPackageCollectionsSearch()

        let mockCollections = makeMockCollections(count: 1000)

        let group = DispatchGroup()
        mockCollections.forEach { collection in
            group.enter()
            search.index(collection: collection) { _ in group.leave() }
        }
        group.wait()

        // search by target name
        let start = Date()
        let targetName = mockCollections.last!.packages.last!.versions.last!.targets.last!.name
        let searchResult = try tsc_await { callback in search.searchTargets(query: targetName, type: .exactMatch, callback: callback) }
        XCTAssert(searchResult.items.count > 0, "should get results")
        let delta = Date().timeIntervalSince(start)
        XCTAssert(delta < 1.0, "should search quickly, took \(delta)")
    }
}
