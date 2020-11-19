/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

public protocol PackageCollectionsSourcesStorage {
    /// Lists all `PackageCollectionSource`s in the given profile.
    ///
    /// - Parameters:
    ///   - callback: The closure to invoke when result becomes available
    func list(callback: @escaping (Result<[PackageCollectionsModel.CollectionSource], Error>) -> Void)

    /// Adds source to the given profile.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to add
    ///   - order: Optional. The order that the source should take after being added to the profile.
    ///            By default the new source is appended to the end (i.e., the least relevant order).
    ///   - callback: The closure to invoke when result becomes available
    func add(source: PackageCollectionsModel.CollectionSource,
             order: Int?,
             callback: @escaping (Result<Void, Error>) -> Void)

    /// Removes source from the given profile.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to remove
    ///   - profile: The `Profile` to remove source
    ///   - callback: The closure to invoke when result becomes available
    func remove(source: PackageCollectionsModel.CollectionSource,
                callback: @escaping (Result<Void, Error>) -> Void)

    /// Moves source to a different order within the given profile.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource` to move
    ///   - order: The order that the source should take in the profile.
    ///   - callback: The closure to invoke when result becomes available
    func move(source: PackageCollectionsModel.CollectionSource,
              to order: Int,
              callback: @escaping (Result<Void, Error>) -> Void)

    /// Checks if a source is already in a profile.
    ///
    /// - Parameters:
    ///   - source: The `PackageCollectionSource`
    ///   - callback: The closure to invoke when result becomes available
    func exists(source: PackageCollectionsModel.CollectionSource,
                callback: @escaping (Result<Bool, Error>) -> Void)
}
