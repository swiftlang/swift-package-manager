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
    func list() async throws -> [PackageCollectionsModel.CollectionSource]

    /// Adds the given source.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to add
    ///   - order: Optional. The order that the source should take after being added.
    ///            By default the new source is appended to the end (i.e., the least relevant order).
    func add(source: PackageCollectionsModel.CollectionSource,
             order: Int?) async throws

    /// Removes the given source.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to remove
    ///   - profile: The `Profile` to remove source
    func remove(source: PackageCollectionsModel.CollectionSource) async throws

    /// Moves source to a different order.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to move
    ///   - order: The order that the source should take.
    func move(source: PackageCollectionsModel.CollectionSource, to order: Int) async throws

    /// Checks if a source has already been added.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource`
    func exists(source: PackageCollectionsModel.CollectionSource) async throws -> Bool

    /// Updates the given source.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to update
    func update(source: PackageCollectionsModel.CollectionSource) async throws
}
