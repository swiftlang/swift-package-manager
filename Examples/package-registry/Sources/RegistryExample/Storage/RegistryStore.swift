//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

public enum RegistryStoreError: Error, Equatable, Sendable {
    /// A release with the same ``PackageIdentifier`` and SemVer
    /// precedence as an existing release already exists. Surfaced as a
    /// `409 Conflict` problem by the publish endpoint (§4.6).
    case conflict
}

/// An in-memory, actor-isolated backing store for all published package
/// releases.
///
/// `RegistryStore` holds every ``StoredRelease`` keyed by its
/// ``PackageIdentifier`` and SemVer
/// ``PackageVersion/precedenceKey``. Because versions that differ only in
/// build metadata share the same precedence key, only one such variant
/// can be published per package.
///
/// The store powers all registry endpoints:
///
/// - §4.1 *List package releases*: ``list(_:)``.
/// - §4.2 *Fetch release metadata* and §4.4 *Download source archive*:
///   ``get(_:version:)``.
/// - §4.5 *Lookup package identifiers for a URL*:
///   ``identifiers(matchingURL:)``.
/// - §4.6 *Create a package release*: ``publish(_:)``.
///
/// Actor isolation serializes all reads and writes, so concurrent
/// requests see a consistent view of the registry without additional
/// locking.
public actor RegistryStore {
    private var releases: [PackageIdentifier: [String: StoredRelease]] = [:]

    /// Creates an empty registry store.
    public init() {}

    /// Inserts a new release into the store.
    ///
    /// The release is indexed by its
    /// ``PackageVersion/precedenceKey``, so two releases that differ only
    /// in build metadata are treated as the same release and the second
    /// `publish` call throws.
    ///
    /// - Parameter release: The fully populated ``StoredRelease`` to
    ///   commit.
    /// - Throws: ``RegistryStoreError/conflict`` if a release with the
    ///   same identifier and precedence key already exists.
    public func publish(_ release: StoredRelease) throws {
        var forPackage = releases[release.identifier] ?? [:]
        let key = release.version.precedenceKey
        guard forPackage[key] == nil else {
            throw RegistryStoreError.conflict
        }
        forPackage[key] = release
        releases[release.identifier] = forPackage
    }

    /// Lists every release published for a given package, ordered from
    /// highest to lowest SemVer precedence.
    ///
    /// The first element (when present) is therefore the latest release
    /// and is suitable for use as the `latest-version` link target
    /// required by §4.1 and §4.2.
    ///
    /// - Parameter identifier: The package to list releases for.
    /// - Returns: The releases in descending precedence order, or `nil`
    ///   if the package has never been published.
    public func list(_ identifier: PackageIdentifier) -> [StoredRelease]? {
        guard let forPackage = releases[identifier] else { return nil }
        return forPackage.values.sorted { $0.version > $1.version }
    }

    /// Fetches a specific release.
    ///
    /// - Parameters:
    ///   - identifier: The package identifier.
    ///   - version: The exact version of the release to fetch. Versions
    ///     differing only in build metadata are treated as equivalent.
    /// - Returns: The matching ``StoredRelease``, or `nil` if no release
    ///   with that precedence key has been published.
    public func get(_ identifier: PackageIdentifier, version: PackageVersion) -> StoredRelease? {
        releases[identifier]?[version.precedenceKey]
    }

    /// Finds the package identifiers associated with a given repository
    /// URL (§4.5).
    ///
    /// A package identifier is considered a match if any of its
    /// published releases has a metadata ``PackageRelease/repositoryURLs``
    /// entry that is equal to `url` when compared case-insensitively.
    ///
    /// - Parameter url: The URL to look up, for example
    ///   `"https://github.com/mona/LinkedList"`.
    /// - Returns: The matching identifiers, sorted by their
    ///   case-normalized ``PackageIdentifier/storageKey``. Returns an
    ///   empty array if no releases declare a matching
    ///   `repositoryURLs` entry.
    public func identifiers(matchingURL url: String) -> [PackageIdentifier] {
        let needle = url.lowercased()
        var matched: Set<PackageIdentifier> = []
        for (id, versions) in releases {
            for release in versions.values {
                guard let urls = release.metadata?.repositoryURLs else { continue }
                if urls.contains(where: { $0.absoluteString.lowercased() == needle }) {
                    matched.insert(id)
                    break
                }
            }
        }
        return matched.sorted { $0.storageKey < $1.storageKey }
    }

    /// Searches published packages for those matching `query`.
    ///
    /// Each package is represented by its highest-precedence release, the same
    /// one ``list(_:)`` returns first; its metadata supplies the summary,
    /// author, and license. A package matches when the query hits its identity,
    /// description, or author, subject to any qualifier terms. Results are
    /// sorted by ``PackageIdentifier/storageKey`` so pagination is stable.
    ///
    /// - Parameters:
    ///   - query: The parsed query. An empty query matches nothing.
    ///   - limit: The maximum number of hits to return.
    ///   - offset: The number of leading hits to skip.
    /// - Returns: The requested page of hits and the total number of matching
    ///   packages (before `offset`/`limit` are applied).
    public func search(_ query: SearchQuery, limit: Int, offset: Int) -> (hits: [SearchHit], total: Int) {
        guard !query.isEmpty else { return ([], 0) }
        let sorted = releases.compactMap { identifier, versions -> SearchHit? in
            guard let latest = versions.values.max(by: { $0.version < $1.version }) else {
                return nil
            }
            let metadata = latest.metadata
            guard query.matches(
                scope: identifier.scope,
                name: identifier.name,
                description: metadata?.description,
                author: metadata?.author?.name
            ) else { return nil }
            return SearchHit(
                identifier: identifier,
                summary: metadata?.description,
                latestVersion: latest.version.description,
                author: metadata?.author?.name,
                licenseURL: metadata?.licenseURL
            )
        }.sorted { $0.identifier.storageKey < $1.identifier.storageKey }
        guard offset < sorted.count else { return ([], sorted.count) }
        let end = min(offset + limit, sorted.count)
        return (Array(sorted[offset..<end]), sorted.count)
    }
}

/// A single package match returned by ``RegistryStore/search(_:limit:offset:)``.
///
/// The fields are derived from the package's highest-precedence release; all
/// but ``identifier`` may be absent when the release carries no metadata.
public struct SearchHit: Sendable {
    /// The matching package's identifier.
    public let identifier: PackageIdentifier
    /// The package's free-form description, if any.
    public let summary: String?
    /// The version string of the highest-precedence release.
    public let latestVersion: String?
    /// The author's name, if any.
    public let author: String?
    /// The URL of the release's license document, if any.
    public let licenseURL: URL?
}