/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import XCTest

@testable import PackageCollections
import SourceControl
import TSCBasic
import TSCUtility

final class PackageCollectionsTests: XCTestCase {
    func testBasicRegistration() throws {
        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollections = makeMockCollections()
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        do {
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 0, "list should be empty")
        }

        try mockCollections.forEach { collection in
            _ = try await { callback in packageCollections.addCollection(collection.source, order: nil, callback: callback) }
        }

        do {
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list, mockCollections, "list count should match")
        }
    }

    func testDelete() throws {
        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollections = makeMockCollections(count: 10)
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        do {
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 0, "list should be empty")
        }

        do {
            try mockCollections.forEach { collection in
                _ = try await { callback in packageCollections.addCollection(collection.source, order: nil, callback: callback) }
            }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list, mockCollections, "list count should match")
        }

        do {
            _ = try await { callback in packageCollections.removeCollection(mockCollections.first!.source, callback: callback) }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, mockCollections.count - 1, "list count should match")
        }

        do {
            _ = try await { callback in packageCollections.removeCollection(mockCollections.first!.source, callback: callback) }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, mockCollections.count - 1, "list count should match")
        }

        do {
            _ = try await { callback in packageCollections.removeCollection(mockCollections[mockCollections.count - 1].source, callback: callback) }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, mockCollections.count - 2, "list count should match")
        }

        do {
            let unknownSource = makeMockSources(count: 1).first!
            _ = try await { callback in packageCollections.removeCollection(unknownSource, callback: callback) }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, mockCollections.count - 2, "list should be empty")
        }

        do {
            let unknownProfile = PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)")
            XCTAssertThrowsError(try await { callback in packageCollections.removeCollection(mockCollections[mockCollections.count - 2].source, from: unknownProfile, callback: callback) }, "expected error")
        }
    }

    func testDeleteFromStorageWhenLast() throws {
        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollection = makeMockCollections(count: 1).first!
        let mockProfile1 = PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)")
        let mockProfile2 = PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)")

        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider([mockCollection])]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        do {
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 0, "list should be empty")
        }

        _ = try await { callback in packageCollections.addCollection(mockCollection.source, order: nil, to: mockProfile1, callback: callback) }
        _ = try await { callback in packageCollections.addCollection(mockCollection.source, order: nil, to: mockProfile2, callback: callback) }

        do {
            let list1 = try await { callback in packageCollections.listCollections(in: mockProfile1, callback: callback) }
            XCTAssertEqual(list1.count, 1, "list count should match")

            let list2 = try await { callback in packageCollections.listCollections(in: mockProfile2, callback: callback) }
            XCTAssertEqual(list2.count, 1, "list count should match")
        }

        do {
            _ = try await { callback in packageCollections.removeCollection(mockCollection.source, from: mockProfile1, callback: callback) }
            let list1 = try await { callback in packageCollections.listCollections(in: mockProfile1, callback: callback) }
            XCTAssertEqual(list1.count, 0, "list count should match")

            let list2 = try await { callback in packageCollections.listCollections(in: mockProfile2, callback: callback) }
            XCTAssertEqual(list2.count, 1, "list count should match")

            // check if exists in storage
            XCTAssertNoThrow(try await { callback in storage.collections.get(identifier: mockCollection.identifier, callback: callback) })
        }

        do {
            _ = try await { callback in packageCollections.removeCollection(mockCollection.source, from: mockProfile2, callback: callback) }
            let list1 = try await { callback in packageCollections.listCollections(in: mockProfile1, callback: callback) }
            XCTAssertEqual(list1.count, 0, "list count should match")

            let list2 = try await { callback in packageCollections.listCollections(in: mockProfile2, callback: callback) }
            XCTAssertEqual(list2.count, 0, "list count should match")

            // check if exists in storage
            XCTAssertThrowsError(try await { callback in storage.collections.get(identifier: mockCollection.identifier, callback: callback) }, "expected error")
        }
    }

    func testOrdering() throws {
        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollections = makeMockCollections(count: 10)
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        do {
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 0, "list should be empty")
        }

        do {
            _ = try await { callback in packageCollections.addCollection(mockCollections[0].source, order: 0, callback: callback) }
            _ = try await { callback in packageCollections.addCollection(mockCollections[1].source, order: 1, callback: callback) }
            _ = try await { callback in packageCollections.addCollection(mockCollections[2].source, order: 2, callback: callback) }
            _ = try await { callback in packageCollections.addCollection(mockCollections[3].source, order: Int.min, callback: callback) }
            _ = try await { callback in packageCollections.addCollection(mockCollections[4].source, order: Int.max, callback: callback) }

            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 5, "list count should match")

            let expectedOrder = [
                mockCollections[0].identifier: 0,
                mockCollections[1].identifier: 1,
                mockCollections[2].identifier: 2,
                mockCollections[3].identifier: 3,
                mockCollections[4].identifier: 4,
            ]

            list.enumerated().forEach { index, collection in
                let expectedOrder = expectedOrder[collection.identifier]!
                XCTAssertEqual(index, expectedOrder, "order should match")
            }
        }

        // bump the order

        do {
            _ = try await { callback in packageCollections.addCollection(mockCollections[5].source, order: 2, callback: callback) }
            _ = try await { callback in packageCollections.addCollection(mockCollections[6].source, order: 2, callback: callback) }
            _ = try await { callback in packageCollections.addCollection(mockCollections[7].source, order: 0, callback: callback) }
            _ = try await { callback in packageCollections.addCollection(mockCollections[8].source, order: -1, callback: callback) }

            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 9, "list count should match")

            let expectedOrder = [
                mockCollections[0].identifier: 1,
                mockCollections[1].identifier: 2,
                mockCollections[2].identifier: 5,
                mockCollections[3].identifier: 6,
                mockCollections[4].identifier: 7,
                mockCollections[5].identifier: 4,
                mockCollections[6].identifier: 3,
                mockCollections[7].identifier: 0,
                mockCollections[8].identifier: 8,
            ]

            list.enumerated().forEach { index, collection in
                let expectedOrder = expectedOrder[collection.identifier]!
                XCTAssertEqual(index, expectedOrder, "order should match")
            }
        }
    }

    func testReorder() throws {
        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollections = makeMockCollections(count: 3)
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        do {
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 0, "list should be empty")
        }

        do {
            _ = try await { callback in packageCollections.addCollection(mockCollections[0].source, order: 0, callback: callback) }
            _ = try await { callback in packageCollections.addCollection(mockCollections[1].source, order: 1, callback: callback) }
            _ = try await { callback in packageCollections.addCollection(mockCollections[2].source, order: 2, callback: callback) }

            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 3, "list count should match")

            let expectedOrder = [
                mockCollections[0].identifier: 0,
                mockCollections[1].identifier: 1,
                mockCollections[2].identifier: 2,
            ]

            list.enumerated().forEach { index, collection in
                let expectedOrder = expectedOrder[collection.identifier]!
                XCTAssertEqual(index, expectedOrder, "order should match")
            }
        }

        do {
            _ = try await { callback in packageCollections.moveCollection(mockCollections[2].source, to: -1, callback: callback) }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }

            let expectedOrder = [
                mockCollections[0].identifier: 0,
                mockCollections[1].identifier: 1,
                mockCollections[2].identifier: 2,
            ]

            list.enumerated().forEach { index, collection in
                let expectedOrder = expectedOrder[collection.identifier]!
                XCTAssertEqual(index, expectedOrder, "order should match")
            }
        }

        do {
            _ = try await { callback in packageCollections.moveCollection(mockCollections[2].source, to: Int.max, callback: callback) }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }

            let expectedOrder = [
                mockCollections[0].identifier: 0,
                mockCollections[1].identifier: 1,
                mockCollections[2].identifier: 2,
            ]

            list.enumerated().forEach { index, collection in
                let expectedOrder = expectedOrder[collection.identifier]!
                XCTAssertEqual(index, expectedOrder, "order should match")
            }
        }

        do {
            _ = try await { callback in packageCollections.moveCollection(mockCollections[2].source, to: 0, callback: callback) }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }

            let expectedOrder = [
                mockCollections[0].identifier: 1,
                mockCollections[1].identifier: 2,
                mockCollections[2].identifier: 0,
            ]

            list.enumerated().forEach { index, collection in
                let expectedOrder = expectedOrder[collection.identifier]!
                XCTAssertEqual(index, expectedOrder, "order should match")
            }
        }

        do {
            _ = try await { callback in packageCollections.moveCollection(mockCollections[2].source, to: 1, callback: callback) }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }

            let expectedOrder = [
                mockCollections[0].identifier: 0,
                mockCollections[1].identifier: 2,
                mockCollections[2].identifier: 1,
            ]

            list.enumerated().forEach { index, collection in
                let expectedOrder = expectedOrder[collection.identifier]!
                XCTAssertEqual(index, expectedOrder, "order should match")
            }
        }

        do {
            let unknownProfile = PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)")
            XCTAssertThrowsError(try await { callback in packageCollections.moveCollection(mockCollections[2].source, to: 1, in: unknownProfile, callback: callback) }, "expected error")
        }
    }

    func testProfiles() throws {
        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        var profiles = [PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)"): [PackageCollectionsModel.Collection](),
                        PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)"): [PackageCollectionsModel.Collection]()]
        let mockCollections = makeMockCollections()
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        try mockCollections.enumerated().forEach { index, collection in
            let profile = index % 2 == 0 ? Array(profiles.keys)[0] : Array(profiles.keys)[1]
            let collection = try await { callback in packageCollections.addCollection(collection.source, order: nil, to: profile, callback: callback) }
            if profiles[profile] == nil {
                profiles[profile] = .init()
            }
            profiles[profile]!.append(collection)
        }

        let list = try await { callback in packageCollections.listProfiles(callback: callback) }
        XCTAssertEqual(list.count, profiles.count, "list count should match")

        try profiles.forEach { profile, profileCollections in
            let list = try await { callback in packageCollections.listCollections(in: profile, callback: callback) }
            XCTAssertEqual(list.count, profileCollections.count, "list count should match")
        }
    }

    func testPackageSearch() throws {
        // FIXME: restore when search is implemented
        throw XCTSkip()

        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        var mockCollections = makeMockCollections()

        let mockTargets = [UUID().uuidString, UUID().uuidString].map {
            PackageCollectionsModel.PackageTarget(name: $0, moduleName: $0)
        }

        let mockProducts = [PackageCollectionsModel.PackageProduct(name: UUID().uuidString, type: .executable, targets: [mockTargets.first!]),
                            PackageCollectionsModel.PackageProduct(name: UUID().uuidString, type: .executable, targets: mockTargets)]

        let mockVersion = PackageCollectionsModel.Collection.PackageVersion(version: TSCUtility.Version(1, 0, 0),
                                                                            packageName: UUID().uuidString,
                                                                            targets: mockTargets,
                                                                            products: mockProducts,
                                                                            toolsVersion: .currentToolsVersion,
                                                                            verifiedPlatforms: nil,
                                                                            verifiedSwiftVersions: nil,
                                                                            license: nil)

        let mockPackage = PackageCollectionsModel.Collection.Package(repository: .init(url: "https://packages.mock/\(UUID().uuidString)"),
                                                                     summary: UUID().uuidString,
                                                                     versions: [mockVersion],
                                                                     readmeURL: nil)

        let mockCollection = PackageCollectionsModel.Collection(source: .init(type: .feed, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                name: UUID().uuidString,
                                                                description: UUID().uuidString,
                                                                keywords: [UUID().uuidString, UUID().uuidString],
                                                                packages: [mockPackage],
                                                                createdAt: Date())

        let mockCollection2 = PackageCollectionsModel.Collection(source: .init(type: .feed, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                 name: UUID().uuidString,
                                                                 description: UUID().uuidString,
                                                                 keywords: [UUID().uuidString, UUID().uuidString],
                                                                 packages: [mockPackage],
                                                                 createdAt: Date())

        let expectedCollections = [mockCollection, mockCollection2]
        let expectedCollectionsIdentifers = expectedCollections.map { $0.identifier }.sorted()

        mockCollections.append(contentsOf: expectedCollections)

        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        try mockCollections.forEach { collection in
            _ = try await { callback in packageCollections.addCollection(collection.source, callback: callback) }
        }

        do {
            // search by pacakge name
            let searchResult = try await { callback in packageCollections.findPackages(mockVersion.packageName, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifers, "list count should match")
        }

        do {
            // search by pacakge description
            let searchResult = try await { callback in packageCollections.findPackages(mockPackage.summary!, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifers, "list count should match")
        }

        do {
            // search by pacakge repository url
            let searchResult = try await { callback in packageCollections.findPackages(mockPackage.repository.url, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifers, "collections should match")
        }

        do {
            // search by pacakge repository url base name
            let searchResult = try await { callback in packageCollections.findPackages(mockPackage.repository.basename, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifers, "collections should match")
        }

        do {
            // search by product name
            let searchResult = try await { callback in packageCollections.findPackages(mockProducts.first!.name, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifers, "list count should match")
        }

        do {
            // search by target name
            let searchResult = try await { callback in packageCollections.findPackages(mockTargets.first!.name, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.collections.sorted(), expectedCollectionsIdentifers, "collections should match")
        }

        do {
            // empty search
            let searchResult = try await { callback in packageCollections.findPackages(UUID().uuidString, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 0, "list count should match")
        }
    }

    func testPackageSearchPerformance() throws {
        // FIXME: restore when search is implemented
        throw XCTSkip()

        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollections = makeMockCollections(count: 1000)
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        try mockCollections.forEach { collection in
            _ = try await { callback in packageCollections.addCollection(collection.source, callback: callback) }
        }

        // search by pacakge name
        let start = Date()
        let repoName = mockCollections.last!.packages.last!.repository.basename
        let searchResult = try await { callback in packageCollections.findPackages(repoName, callback: callback) }
        XCTAssert(searchResult.items.count > 0, "should get results")
        let delta = start.distance(to: Date())
        // FIXME: we need to get this under 1s
        XCTAssert(delta < 1.5, "should search quickly, took \(delta)")
    }

    func testTargetsSearch() throws {
        // FIXME: restore when search is implemented
        throw XCTSkip()

        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        var mockCollections = makeMockCollections()

        let mockTargets = [UUID().uuidString, UUID().uuidString].map {
            PackageCollectionsModel.PackageTarget(name: $0, moduleName: $0)
        }

        let mockProducts = [PackageCollectionsModel.PackageProduct(name: UUID().uuidString, type: .executable, targets: [mockTargets.first!]),
                            PackageCollectionsModel.PackageProduct(name: UUID().uuidString, type: .executable, targets: mockTargets)]

        let mockVersion = PackageCollectionsModel.Collection.Package.Version(version: TSCUtility.Version(1, 0, 0),
                                                                             packageName: UUID().uuidString,
                                                                             targets: mockTargets,
                                                                             products: mockProducts,
                                                                             toolsVersion: .currentToolsVersion,
                                                                             verifiedPlatforms: nil,
                                                                             verifiedSwiftVersions: nil,
                                                                             license: nil)

        let mockPackage = PackageCollectionsModel.Collection.Package(repository: RepositorySpecifier(url: "https://packages.mock/\(UUID().uuidString)"),
                                                                     summary: UUID().uuidString,
                                                                     versions: [mockVersion],
                                                                     readmeURL: nil)

        let mockCollection = PackageCollectionsModel.Collection(source: .init(type: .feed, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                name: UUID().uuidString,
                                                                description: UUID().uuidString,
                                                                keywords: [UUID().uuidString, UUID().uuidString],
                                                                packages: [mockPackage],
                                                                createdAt: Date())

        let mockCollection2 = PackageCollectionsModel.Collection(source: .init(type: .feed, url: URL(string: "https://feed.mock/\(UUID().uuidString)")!),
                                                                 name: UUID().uuidString,
                                                                 description: UUID().uuidString,
                                                                 keywords: [UUID().uuidString, UUID().uuidString],
                                                                 packages: [mockPackage],
                                                                 createdAt: Date())

        let expectedCollections = [mockCollection, mockCollection2]
        let expectedCollectionsIdentifers = expectedCollections.map { $0.identifier }.sorted()

        mockCollections.append(contentsOf: expectedCollections)

        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        try mockCollections.forEach { collection in
            _ = try await { callback in packageCollections.addCollection(collection.source, callback: callback) }
        }

        do {
            // search by exact target name
            let searchResult = try await { callback in packageCollections.findTargets(mockTargets.first!.name, searchType: .exactMatch, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.packages.map { $0.repository }, [mockPackage.repository], "packages should match")
            XCTAssertEqual(searchResult.items.first?.packages.flatMap { $0.collections }.sorted(), expectedCollectionsIdentifers, "collections should match")
        }

        do {
            // search by prefix target name
            let searchResult = try await { callback in packageCollections.findTargets(String(mockTargets.first!.name.prefix(mockTargets.first!.name.count - 1)), searchType: .prefix, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 1, "list count should match")
            XCTAssertEqual(searchResult.items.first?.packages.map { $0.repository }, [mockPackage.repository], "packages should match")
            XCTAssertEqual(searchResult.items.first?.packages.flatMap { $0.collections }.sorted(), expectedCollectionsIdentifers, "collections should match")
        }

        do {
            // empty search
            let searchResult = try await { callback in packageCollections.findTargets(UUID().uuidString, searchType: .exactMatch, callback: callback) }
            XCTAssertEqual(searchResult.items.count, 0, "list count should match")
        }
    }

    func testTargetsSearchPerformance() throws {
        // FIXME: restore when search is implemented
        throw XCTSkip()

        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollections = makeMockCollections(count: 1000)
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        try mockCollections.forEach { collection in
            _ = try await { callback in packageCollections.addCollection(collection.source, callback: callback) }
        }

        // search by pacakge name
        let start = Date()
        let targetName = mockCollections.last!.packages.last!.versions.last!.targets.last!.name
        let searchResult = try await { callback in packageCollections.findTargets(targetName, searchType: .exactMatch, callback: callback) }
        XCTAssert(searchResult.items.count > 0, "should get results")
        let delta = start.distance(to: Date())
        XCTAssert(delta < 1.0, "should search quickly, took \(delta)")
    }

    func testHappyRefresh() throws {
        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollections = makeMockCollections()
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        try mockCollections.forEach { collection in
            // save directly to storage to circumvent refresh on add
            _ = try await { callback in storage.collectionsProfiles.add(source: collection.source, order: nil, to: .default, callback: callback) }
        }
        _ = try await { callback in packageCollections.refreshCollections(callback: callback) }

        let list = try await { callback in packageCollections.listCollections(callback: callback) }
        XCTAssertEqual(list.count, mockCollections.count, "list count should match")
    }

    func testBrokenRefresh() throws {
        struct BrokenProvider: PackageCollectionProvider {
            let brokenSources: [PackageCollectionsModel.CollectionSource]
            let error: Error

            init(brokenSources: [PackageCollectionsModel.CollectionSource], error: Error) {
                self.brokenSources = brokenSources
                self.error = error
            }

            func get(_ source: PackageCollectionsModel.CollectionSource, callback: @escaping (Result<PackageCollectionsModel.Collection, Error>) -> Void) {
                if self.brokenSources.contains(source) {
                    callback(.failure(self.error))
                } else {
                    callback(.success(PackageCollectionsModel.Collection(source: source, name: "", description: nil, keywords: nil, packages: [], createdAt: Date())))
                }
            }
        }

        struct MyError: Error, Equatable {}

        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let expectedError = MyError()
        let goodSources = [PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "https://feed-\(UUID().uuidString)")!),
                           PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "https://feed-\(UUID().uuidString)")!)]
        let brokenSources = [PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "https://feed-\(UUID().uuidString)")!),
                             PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "https://feed-\(UUID().uuidString)")!)]
        let provider = BrokenProvider(brokenSources: brokenSources, error: expectedError)
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: provider]

        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        XCTAssertThrowsError(try await { callback in packageCollections.addCollection(brokenSources.first!, order: nil, to: .default, callback: callback) }, "expected error", { error in
            XCTAssertEqual(error as? MyError, expectedError, "expected error to match")
        })

        // save directly to storage to circumvent refresh on add
        try goodSources.forEach { source in
            _ = try await { callback in storage.collectionsProfiles.add(source: source, order: nil, to: .default, callback: callback) }
        }
        try brokenSources.forEach { source in
            _ = try await { callback in storage.collectionsProfiles.add(source: source, order: nil, to: .default, callback: callback) }
        }
        _ = try await { callback in storage.collectionsProfiles.add(source: .init(type: .feed, url: URL(string: "https://feed-\(UUID().uuidString)")!), order: nil, to: .default, callback: callback) }

        XCTAssertThrowsError(try await { callback in packageCollections.refreshCollections(callback: callback) }, "expected error", { error in
            if let error = error as? MultipleErrors {
                XCTAssertEqual(error.errors.count, brokenSources.count, "expected error to match")
                error.errors.forEach { error in
                    XCTAssertEqual(error as? MyError, expectedError, "expected error to match")
                }
            } else {
                XCTFail("expected error to match")
            }
        })

        // test isolation - broken feeds does not impact good ones
        let list = try await { callback in packageCollections.listCollections(in: .default, callback: callback) }
        XCTAssertEqual(list.count, goodSources.count + 1, "list count should match")
    }

    func testListTargets() throws {
        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollections = makeMockCollections()
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        do {
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 0, "list should be empty")
        }

        do {
            try mockCollections.forEach { collection in
                _ = try await { callback in packageCollections.addCollection(collection.source, order: nil, callback: callback) }
            }
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, mockCollections.count, "list count should match")
        }

        let targetsList = try await { callback in packageCollections.listTargets(callback: callback) }
        let expectedTargets = Set(mockCollections.flatMap { $0.packages.flatMap { $0.versions.flatMap { $0.targets.map { $0.name } } } })
        XCTAssertEqual(Set(targetsList.map { $0.target.name }), expectedTargets, "targets should match")

        let targetsPackagesList = Set(targetsList.flatMap { $0.packages })
        let expectedPackages = Set(mockCollections.flatMap { $0.packages.filter { !$0.versions.filter { !expectedTargets.isDisjoint(with: $0.targets.map { $0.name }) }.isEmpty } }.map { $0.reference })
        XCTAssertEqual(targetsPackagesList.count, expectedPackages.count, "pacakges should match")

        let targetsCollectionsList = Set(targetsList.flatMap { $0.packages.flatMap { $0.collections } })
        let expectedCollections = Set(mockCollections.filter { !$0.packages.filter { expectedPackages.contains($0.reference) }.isEmpty }.map { $0.identifier })
        XCTAssertEqual(targetsCollectionsList, expectedCollections, "collections should match")
    }

    func testListTargetsCustomProfile() throws {
        let configuration = PackageCollections.Configuration()
        let storage = makeMockStorage()
        defer { XCTAssertNoThrow(try storage.close()) }

        let mockCollections = makeMockCollections(count: 5)
        let providers = [PackageCollectionsModel.CollectionSourceType.feed: MockProvider(mockCollections)]
        let packageCollections = PackageCollections(configuration: configuration, storage: storage, providers: providers)

        let list = try await { callback in packageCollections.listCollections(callback: callback) }
        XCTAssertEqual(list.count, 0, "list should be empty")

        var profiles = [PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)"): [PackageCollectionsModel.Collection](),
                        PackageCollectionsModel.Profile(name: "profile-\(UUID().uuidString)"): [PackageCollectionsModel.Collection]()]

        try mockCollections.enumerated().forEach { index, collection in
            let profile = index % 2 == 0 ? Array(profiles.keys)[0] : Array(profiles.keys)[1]
            _ = try await { callback in packageCollections.addCollection(collection.source, order: nil, to: profile, callback: callback) }
            profiles[profile]?.append(collection)
        }

        do {
            let list = try await { callback in packageCollections.listCollections(callback: callback) }
            XCTAssertEqual(list.count, 0, "list should be empty")
        }

        try profiles.forEach { profile, collections in
            let list = try await { callback in packageCollections.listCollections(in: profile, callback: callback) }
            XCTAssertEqual(list.count, collections.count, "list count should match")

            let targetsList = try await { callback in packageCollections.listTargets(in: profile, callback: callback) }
            let expectedTargets = Set(collections.flatMap { $0.packages.flatMap { $0.versions.flatMap { $0.targets.map { $0.name } } } })
            XCTAssertEqual(Set(targetsList.map { $0.target.name }), expectedTargets, "targets should match")

            let targetsPackagesList = Set(targetsList.flatMap { $0.packages })
            let expectedPackages = Set(collections.flatMap { $0.packages.filter { !$0.versions.filter { !expectedTargets.isDisjoint(with: $0.targets.map { $0.name }) }.isEmpty } }.map { $0.reference })
            XCTAssertEqual(targetsPackagesList.count, expectedPackages.count, "packages should match")

            let targetsCollectionsList = Set(targetsList.flatMap { $0.packages.flatMap { $0.collections } })
            let expectedCollections = Set(collections.filter { !$0.packages.filter { expectedPackages.contains($0.reference) }.isEmpty }.map { $0.identifier })
            XCTAssertEqual(targetsCollectionsList, expectedCollections, "collections should match")
        }
    }

    func testSourceValidation() throws {
        let httpsSource = PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "https://feed.mock.io")!)
        XCTAssertNil(httpsSource.validate(), "not expecting errors")

        let httpsSource2 = PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "HTTPS://feed.mock.io")!)
        XCTAssertNil(httpsSource2.validate(), "not expecting errors")

        let httpsSource3 = PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "HttpS://feed.mock.io")!)
        XCTAssertNil(httpsSource3.validate(), "not expecting errors")

        let httpSource = PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "http://feed.mock.io")!)
        XCTAssertEqual(httpSource.validate()?.count, 1, "expecting errors")

        let otherProtocolSource = PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "ftp://feed.mock.io")!)
        XCTAssertEqual(otherProtocolSource.validate()?.count, 1, "expecting errors")

        let brokenUrlSource = PackageCollectionsModel.CollectionSource(type: .feed, url: URL(string: "blah")!)
        XCTAssertEqual(brokenUrlSource.validate()?.count, 1, "expecting errors")
    }
}
