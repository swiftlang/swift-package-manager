/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Specifies a repository address.
public struct RepositorySpecifier {
    /// The URL of the repository.
    public let url: String

    /// Create a specifier.
    public init(url: String) {
        self.url = url
    }
    
    /// A unique identifier for this specifier.
    ///
    /// This identifier is suitable for use in a file system path, and
    /// unique for each repository.
    public var fileSystemIdentifier: String {
        // FIXME: Need to do something better here. In particular, we should use
        // a stable hash function since this interacts with the CheckoutManager
        // persistence.
        return url.basename + "-" + String(url.hashValue)
    }
}

/// A repository provider.
public protocol RepositoryProvider {
    /// Fetch the complete repository at the given location to `path`.
    func fetch(repository: RepositorySpecifier, to path: String) throws
}
