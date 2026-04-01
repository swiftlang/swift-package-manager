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
    /// URL to download the source archive ZIP for a given tag.
    ///
    /// Uses the tag name rather than the commit SHA because GitHub generates
    /// different ZIP bytes for `/archive/{sha}.zip` vs `/archive/refs/tags/{tag}.zip`
    /// even for the same commit. Using tags consistently avoids spurious TOFU
    /// checksum mismatches. The race window between `git ls-remote` (which resolves
    /// the tag to a SHA) and this download is negligibly small (same process,
    /// sequential calls), and any tag movement is caught by TOFU on subsequent downloads.
    func archiveURL(for tag: String) -> URL

    func rawFileURL(for path: String, sha: String) -> URL

    /// Cache key for disk-based caches (metadata, manifests, tags).
    /// Typically `(owner, repository)` derived from the package URL.
    var cacheKey: (owner: String, repo: String) { get }
}

/// Attempts to create a source archive provider for the given URL.
/// Returns nil if no provider supports the URL.
public func sourceArchiveProvider(for url: SourceControlURL) -> (any SourceArchiveProvider)? {
    GitHubSourceArchiveProvider.make(for: url)
}
