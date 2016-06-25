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
///
/// This protocol defines the lower level interface used to to access
/// repositories. High-level clients should access repositories via a
/// `CheckoutManager`.
public protocol RepositoryProvider {
    /// Fetch the complete repository at the given location to `path`.
    func fetch(repository: RepositorySpecifier, to path: String) throws

    /// Open the given repository.
    ///
    /// - parameters:
    ///   - repository: The specifier for the repository.
    ///   - path: The location of the repository on disk, at which the
    ///   repository has previously been created via `fetch`.
    func open(repository: RepositorySpecifier, at path: String) -> Repository
}

/// Abstract repository operations.
///
/// This interface provides access to an abstracted representation of a
/// repository which is ultimately owned by the a `CheckoutManager`. This
/// interface is designed in such a way as to provide the minimal facilities
/// required by the package manager to gather basic information about a
/// repository, but it does not aim to provide all of the interfaces one might
/// want for working with an editable checkout of a repository on disk.
///
/// The goal of this design is to allow the `CheckoutManager` a large degree of
/// flexibility in the storage and maintenance of its underlying repositories.
public protocol Repository {
    /// Get the list of tags in the repository.
    //
    // FIXME: Migrate this to a structured SwiftPM-specific type?
    var tags: [String] { get }
}
