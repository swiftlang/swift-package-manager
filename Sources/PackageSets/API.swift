/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import SourceControl

public protocol PackageSetsProtocol {
    // MARK: - Package set profile APIs

    /// Lists package set profiles.
    ///
    /// The result of this API does not include `PackageSet` data. All other APIs in this
    /// protocol require the context of a profile. Implementations should support a "default"
    /// profile such that the `profile` API parameter can be optional.
    ///
    /// - Parameters:
    ///   - callback: The closure to invoke when result becomes available
    func listProfiles(callback: @escaping (Result<[PackageSetsModel.Profile], Error>) -> Void)

    // MARK: - Package set APIs

    /// Returns packages organized into groups.
    ///
    /// Package sets are not mutually exclusive; a package may belong to more than one group. As such,
    /// the ordering of `PackageSet`s should be preserved and respected during conflict resolution.
    ///
    /// - Parameters:
    ///   - identifers: Optional. If specified, only `PackageSet`s with matching identifiers will be returned.
    ///   - profile: Optional. The `PackageSetProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func listPackageSets(
        identifers: Set<PackageSetsModel.PackageSetIdentifier>?,
        in profile: PackageSetsModel.Profile?,
        callback: @escaping (Result<[PackageSetsModel.PackageSet], Error>) -> Void
    )

    /// Refreshes all configured package sets.
    ///
    /// - Parameters:
    ///   - profile: Optional. The `PackageSetProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke after triggering a refresh for the configured package sets.
    func refreshPackageSets(
        in profile: PackageSetsModel.Profile?,
        callback: @escaping (Result<[PackageSetsModel.PackageSetSource], Error>) -> Void
    )

    /// Adds a package set.
    ///
    /// - Parameters:
    ///   - source: The package set's source
    ///   - order: Optional. The order that the `PackageSet` should take after being added to the list.
    ///            By default the new group is appended to the end (i.e., the least relevant order).
    ///   - profile: Optional. The `PackageSetProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke with the updated `PackageSet`s
    func addPackageSet(
        _ source: PackageSetsModel.PackageSetSource,
        order: Int?,
        to profile: PackageSetsModel.Profile?,
        callback: @escaping (Result<PackageSetsModel.PackageSet, Error>) -> Void
    )

    /// Removes a package set.
    ///
    /// - Parameters:
    ///   - source: The package set's source
    ///   - profile: Optional. The `PackageSetProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke with the updated `PackageSet`s
    func removePackageSet(
        _ source: PackageSetsModel.PackageSetSource,
        from profile: PackageSetsModel.Profile?,
        callback: @escaping (Result<Void, Error>) -> Void
    )

    /// Moves a package set to a different order.
    ///
    /// - Parameters:
    ///   - id: The identifier of the `PackageSet` to be moved
    ///   - order: The new order that the `PackageSet` should be positioned after the move
    ///   - profile: Optional. The `PackageSetProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke with the updated `PackageSet`s
    func movePackageSet(
        _ source: PackageSetsModel.PackageSetSource,
        to order: Int,
        in profile: PackageSetsModel.Profile?,
        callback: @escaping (Result<Void, Error>) -> Void
    )

    /// Returns information about a package set. The set is not required to be in the configured list. If
    /// not found locally, the group will be fetched from the source.
    ///
    /// - Parameters:
    ///   - source: The package set's source
    ///   - callback: The closure to invoke with the `PackageSet`
    func getPackageSet(
        _ source: PackageSetsModel.PackageSetSource,
        callback: @escaping (Result<PackageSetsModel.PackageSet, Error>) -> Void
    )

    // MARK: - Package APIs

    /// Returns metadata for the package identified by the given `PackageReference`, along with the
    /// identifiers of `PackageSet`s where the package is found.
    ///
    /// A failure is returned if the package is not found.
    ///
    /// - Parameters:
    ///   - reference: The package reference
    ///   - profile: Optional. The `PackageSetProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func getPackageMetadata(
        _ reference: PackageReference,
        profile: PackageSetsModel.Profile?,
        callback: @escaping (Result<(PackageSetsModel.Package, [PackageSetsModel.PackageSetIdentifier]), Error>) -> Void
    )

    // MARK: - Target (Module) APIs

    /// List all known targets.
    ///
    /// A target name may be found in different packages and/or different versions of a package, and a package
    /// may belong to multiple package sets. This API's result items will be consolidated by target then package,
    /// with the package's versions list filtered to only include those that contain the target.
    ///
    /// - Parameters:
    ///   - sets: Optional. If specified, only list targets within these groups.
    ///   - profile: Optional. The `PackageSetProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func listTargets(
        sets: Set<PackageSetsModel.PackageSetIdentifier>?,
        in profile: PackageSetsModel.Profile?,
        callback: @escaping (Result<[PackageSetsModel.Target], Error>) -> Void
    )

    // MARK: - Search APIs

    /// Finds and returns packages that match the query.
    ///
    /// If applicable, for example when we search by package name which might change between versions,
    /// the versions list in the result will be filtered to only include those matching the query.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - groups: Optional. If specified, only search within these groups.
    ///   - profile: Optional. The `PackageSetProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func findPackages(
        _ query: PackageSetsModel.SearchQuery,
        sets: Set<PackageSetsModel.PackageSetIdentifier>?,
        profile: PackageSetsModel.Profile?,
        callback: @escaping (Result<PackageSetsModel.PackageSearchResult, Error>) -> Void
    )

    /// Finds targets by name and returns the corresponding packages.
    ///
    /// This API's result items will be consolidated by target then package, with the
    /// package's versions list filtered to only include those that contain the target.
    ///
    /// - Parameters:
    ///   - query: The search query
    ///   - searchType: Optional. Target names must either match exactly or contain the prefix.
    ///                 For more flexibility, use the `findPackages` API instead.
    ///   - groups: Optional. If specified, only search within these groups.
    ///   - profile: Optional. The `PackageSetProfile` context. By default the `default` profile is used.
    ///   - callback: The closure to invoke when result becomes available
    func findTargets(
        _ query: String,
        searchType: PackageSetsModel.TargetSearchType?,
        sets: Set<PackageSetsModel.PackageSetIdentifier>?,
        profile: PackageSetsModel.Profile?,
        callback: @escaping (Result<PackageSetsModel.TargetSearchResult, Error>) -> Void
    )
}
