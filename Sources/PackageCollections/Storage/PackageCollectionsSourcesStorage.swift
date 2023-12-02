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

import Basics

public protocol PackageCollectionsSourcesStorage {
    /// Lists all `PackageCollectionSource`s.
    ///
    /// - Parameters:
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func list(callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void)

    /// Adds the given source.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to add
    ///   - order: Optional. The order that the source should take after being added.
    ///            By default the new source is appended to the end (i.e., the least relevant order).
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func add(source: PackageCollectionsModel.CollectionSource,
             order: Int?,
             callback: @escaping (Result<Void, Error>) -> Void)

    /// Removes the given source.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to remove
    ///   - profile: The `Profile` to remove source
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func remove(source: PackageCollectionsModel.CollectionSource,
                callback: @escaping (Result<Void, Error>) -> Void)

    /// Moves source to a different order.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to move
    ///   - order: The order that the source should take.
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func move(source: PackageCollectionsModel.CollectionSource,
              to order: Int,
              callback: @escaping (Result<Void, Error>) -> Void)

    /// Checks if a source has already been added.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource`
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func exists(source: PackageCollectionsModel.CollectionSource,
                callback: @escaping (Result<Bool, Error>) -> Void)

    /// Updates the given source.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to update
    ///   - callback: The closure to invoke when result becomes available
    @available(*, noasync, message: "Use the async alternative")
    func update(source: PackageCollectionsModel.CollectionSource,
                callback: @escaping (Result<Void, Error>) -> Void)
}

public extension PackageCollectionsSourcesStorage {
    func list() async throws -> [PackageCollectionsModel.CollectionSource] {
        try await safe_async {
            self.list(callback: $0)
        }
    }

    func add(source: PackageCollectionsModel.CollectionSource,
             order: Int? = nil) async throws {
        try await safe_async {
            self.add(source: source, order: order, callback: $0)
        }
    }

    func remove(source: PackageCollectionsModel.CollectionSource) async throws {
        try await safe_async {
            self.remove(source: source, callback: $0)
        }
    }

    func move(source: PackageCollectionsModel.CollectionSource, to order: Int) async throws {
        try await safe_async {
            self.move(source: source, to:order, callback: $0)
        }
    }

    func exists(source: PackageCollectionsModel.CollectionSource) async throws -> Bool {
        try await safe_async {
            self.exists(source: source, callback: $0)
        }
    }

    func update(source: PackageCollectionsModel.CollectionSource) async throws {
        try await safe_async {
            self.update(source: source, callback: $0)
        }
    }
}
