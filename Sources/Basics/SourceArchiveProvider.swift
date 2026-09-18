//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// A provider that constructs host-specific URLs for downloading source archives
/// and raw file content from a code hosting service.
public protocol SourceArchiveProvider: Sendable {
    /// URL to download the source archive ZIP for a given commit SHA.
    ///
    /// Uses the commit SHA rather than the tag name to eliminate the race
    /// condition where a tag could be moved between `git ls-remote` (which
    /// resolves the tag to a SHA) and the archive download.
    func archiveURL(forSHA sha: String) -> URL

    func rawFileURL(for path: String, sha: String) -> URL

    /// The hostname of the code hosting service (e.g. `"github.com"`).
    /// Used to namespace on-disk paths so that packages from different
    /// hosts never collide.
    var host: String { get }

    /// Cache key for disk-based caches (metadata, manifests, tags).
    /// Typically `(owner, repository)` derived from the package URL.
    var cacheKey: (owner: String, repo: String) { get }
}

/// Attempts to create a source archive provider for the given URL.
/// Returns nil if no provider supports the URL.
public func sourceArchiveProvider(for url: SourceControlURL) -> (any SourceArchiveProvider)? {
    GitHubSourceArchiveProvider.make(for: url)
}
