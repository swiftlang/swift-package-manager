/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// MARK: - file system

extension Package.Dependency {
    /// Adds a package dependency to a local package on the filesystem.
    ///
    /// The Swift Package Manager uses the package dependency as-is
    /// and does not perform any source control access. Local package dependencies
    /// are especially useful during development of a new package or when working
    /// on multiple tightly coupled packages.
    ///
    /// - Parameter path: The path of the package.
    @available(_PackageDescription, obsoleted: 5.2)
    public static func package(
        path: String
    ) -> Package.Dependency {
        return .init(name: nil, url: path, requirement: .localPackageItem)
    }

    /// Adds a package dependency to a local package on the filesystem.
    ///
    /// The Swift Package Manager uses the package dependency as-is
    /// and doesn't perform any source control access. Local package dependencies
    /// are especially useful during development of a new package or when working
    /// on multiple tightly coupled packages.
    ///
    /// - Parameters
    ///   - name: The name of the Swift package or `nil` to deduce the name from path.
    ///   - path: The local path to the package.
    @available(_PackageDescription, introduced: 5.2)
    public static func package(
        name: String? = nil,
        path: String
    ) -> Package.Dependency {
        return .init(name: name, url: path, requirement: .localPackageItem)
    }
}


// MARK: - source control

extension Package.Dependency {
    /// Adds a package dependency that uses the version requirement, starting with the given minimum version,
    /// going up to the next major version.
    ///
    /// This is the recommended way to specify a remote package dependency.
    /// It allows you to specify the minimum version you require, allows updates that include bug fixes
    /// and backward-compatible feature updates, but requires you to explicitly update to a new major version of the dependency.
    /// This approach provides the maximum flexibility on which version to use,
    /// while making sure you don't update to a version with breaking changes,
    /// and helps to prevent conflicts in your dependency graph.
    ///
    /// The following example allows the Swift Package Manager to select a version
    /// like a  `1.2.3`, `1.2.4`, or `1.3.0`, but not `2.0.0`.
    ///
    ///    .package(url: "https://example.com/example-package.git", from: "1.2.3"),
    ///
    /// - Parameters:
    ///     - name: The name of the package, or nil to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - version: The minimum version requirement.
    @available(_PackageDescription, obsoleted: 5.2)
    public static func package(
        url: String,
        from version: Version
    ) -> Package.Dependency {
        return .package(name: nil, url: url, .upToNextMajor(from: version))
    }

    /// Adds a package dependency that uses the version requirement, starting with the given minimum version,
    /// going up to the next major version.
    ///
    /// This is the recommended way to specify a remote package dependency.
    /// It allows you to specify the minimum version you require, allows updates that include bug fixes
    /// and backward-compatible feature updates, but requires you to explicitly update to a new major version of the dependency.
    /// This approach provides the maximum flexibility on which version to use,
    /// while making sure you don't update to a version with breaking changes,
    /// and helps to prevent conflicts in your dependency graph.
    ///
    /// The following example allows the Swift Package Manager to select a version
    /// like a  `1.2.3`, `1.2.4`, or `1.3.0`, but not `2.0.0`.
    ///
    ///    .package(url: "https://example.com/example-package.git", from: "1.2.3"),
    ///
    /// - Parameters:
    ///     - name: The name of the package, or nil to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - version: The minimum version requirement.
    @available(_PackageDescription, introduced: 5.2)
    public static func package(
        name: String? = nil,
        url: String,
        from version: Version
    ) -> Package.Dependency {
        return .package(name: name, url: url, .upToNextMajor(from: version))
    }
    
    /// Adds a remote package dependency given a branch requirement.
    ///
    ///    .package(url: "https://example.com/example-package.git", branch: "main"),
    ///
    /// - Parameters:
    ///     - name: The name of the package, or nil to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - branch: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    @available(_PackageDescription, introduced: 5.5)
    public static func package(
        name: String? = nil,
        url: String,
        branch: String
    ) -> Package.Dependency {
        return .package(name: name, url: url, .branch(branch))
    }
  
    /// Adds a remote package dependency given a revision requirement.
    ///
    ///    .package(url: "https://example.com/example-package.git", revision: "aa681bd6c61e22df0fd808044a886fc4a7ed3a65"),
    ///
    /// - Parameters:
    ///     - name: The name of the package, or nil to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - revision: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    @available(_PackageDescription, introduced: 5.5)
    public static func package(
        name: String? = nil,
        url: String,
        revision: String
    ) -> Package.Dependency {
        return .package(name: name, url: url, .revision(revision))
    }

    /// Adds a package dependency starting with a specific minimum version, up to
    /// but not including a specified maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions `1.2.3`, `1.2.4`, `1.2.5`, but not `1.2.6`.
    ///
    ///     .package(url: "https://example.com/example-package.git", "1.2.3"..<"1.2.6"),
    ///
    /// - Parameters:
    ///     - name: The name of the package, or nil to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - range: The custom version range requirement.
    @available(_PackageDescription, obsoleted: 5.2)
    public static func package(
        url: String,
        _ range: Range<Version>
    ) -> Package.Dependency {
        return .package(name: nil, url: url, .rangeItem(range))
    }

    /// Adds a package dependency starting with a specific minimum version, up to
    /// but not including a specified maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions `1.2.3`, `1.2.4`, `1.2.5`, but not `1.2.6`.
    ///
    ///     .package(url: "https://example.com/example-package.git", "1.2.3"..<"1.2.6"),
    ///
    /// - Parameters:
    ///     - name: The name of the package, or `nil` to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - range: The custom version range requirement.
    @available(_PackageDescription, introduced: 5.2)
    public static func package(
        name: String? = nil,
        url: String,
        _ range: Range<Version>
    ) -> Package.Dependency {
        return .package(name: name, url: url, .rangeItem(range))
    }

    /// Adds a package dependency starting with a specific minimum version, going
    /// up to and including a specific maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.
    ///
    ///     .package(url: "https://example.com/example-package.git", "1.2.3"..."1.2.6"),
    ///
    /// - Parameters:
    ///     - name: The name of the package, or `nil` to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - range: The closed version range requirement.
    @available(_PackageDescription, obsoleted: 5.2)
    public static func package(
        url: String,
        _ range: ClosedRange<Version>
    ) -> Package.Dependency {
        // Increase upperbound's patch version by one.
        let upper = range.upperBound
        let upperBound = Version(
            upper.major, upper.minor, upper.patch + 1,
            prereleaseIdentifiers: upper.prereleaseIdentifiers,
            buildMetadataIdentifiers: upper.buildMetadataIdentifiers)
        return .package(name: nil, url: url, .rangeItem(range.lowerBound..<upperBound))
    }

    /// Adds a package dependency starting with a specific minimum version, going
    /// up to and including a specific maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.
    ///
    ///     .package(url: "https://example.com/example-package.git", "1.2.3"..."1.2.6"),
    ///
    /// - Parameters:
    ///     - name: The name of the package, or `nil` to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - range: The closed version range requirement.
    @available(_PackageDescription, introduced: 5.2)
    public static func package(
        name: String? = nil,
        url: String,
        _ range: ClosedRange<Version>
    ) -> Package.Dependency {
        // Increase upperbound's patch version by one.
        let upper = range.upperBound
        let upperBound = Version(
            upper.major, upper.minor, upper.patch + 1,
            prereleaseIdentifiers: upper.prereleaseIdentifiers,
            buildMetadataIdentifiers: upper.buildMetadataIdentifiers)
        return .package(name: name, url: url, .rangeItem(range.lowerBound..<upperBound))
    }

    /// Adds a remote package dependency given a version requirement.
    ///
    /// - Parameters:
    ///     - name: The name of the package, or nil to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - requirement: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    @available(_PackageDescription, obsoleted: 5.2)
    public static func package(
        url: String,
        _ requirement: Package.Dependency.Requirement
    ) -> Package.Dependency {
        precondition(!requirement.isLocalPackage, "Use `.package(path:)` API to declare a local package dependency")
        return .init(name: nil, url: url, requirement: requirement)
    }

    /// Adds a remote package dependency with a given version requirement.
    ///
    /// - Parameters:
    ///     - name: The name of the package, or `nil` to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - requirement: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    @available(_PackageDescription, introduced: 5.2)
    public static func package(
        name: String? = nil,
        url: String,
        _ requirement: Package.Dependency.Requirement
    ) -> Package.Dependency {
        precondition(!requirement.isLocalPackage, "Use `.package(path:)` API to declare a local package dependency")
        return .init(name: name, url: url, requirement: requirement)
    }
}

// MARK: - registry

extension Package.Dependency {
    /// Adds a package dependency that uses the version requirement, starting with the given minimum version,
    /// going up to the next major version.
    ///
    /// This is the recommended way to specify a remote package dependency.
    /// It allows you to specify the minimum version you require, allows updates that include bug fixes
    /// and backward-compatible feature updates, but requires you to explicitly update to a new major version of the dependency.
    /// This approach provides the maximum flexibility on which version to use,
    /// while making sure you don't update to a version with breaking changes,
    /// and helps to prevent conflicts in your dependency graph.
    ///
    /// The following example allows the Swift Package Manager to select a version
    /// like a  `1.2.3`, `1.2.4`, or `1.3.0`, but not `2.0.0`.
    ///
    ///    .package(identity: "scope/name", from: "1.2.3"),
    ///
    /// - Parameters:
    ///     - identity: The identity of the package.
    ///     - version: The minimum version requirement.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        identity: String,
        from version: Version
    ) -> Package.Dependency {
        return .package(identity: identity, .upToNextMajor(from: version))
    }

    /// Adds a remote package dependency given a branch requirement.
    ///
    ///    .package(identity: "scope/name", branch: "main"),
    ///
    /// - Parameters:
    ///     - identity: The identity of the package..
    ///     - branch: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        identity: String,
        branch: String
    ) -> Package.Dependency {
        return .package(identity: identity,  .branch(branch))
    }

    /// Adds a remote package dependency given a revision requirement.
    ///
    ///    .package(identity: "scope/name", revision: "aa681bd6c61e22df0fd808044a886fc4a7ed3a65"),
    ///
    /// - Parameters:
    ///     - identity: The identity of the package.
    ///     - revision: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        identity: String,
        revision: String
    ) -> Package.Dependency {
        return .package(identity: identity, .revision(revision))
    }

    /// Adds a package dependency starting with a specific minimum version, up to
    /// but not including a specified maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions `1.2.3`, `1.2.4`, `1.2.5`, but not `1.2.6`.
    ///
    ///     .package(identity: "scope/name", "1.2.3"..<"1.2.6"),
    ///
    /// - Parameters:
    ///     - identity: The identity of the package.
    ///     - range: The custom version range requirement.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        identity: String,
        _ range: Range<Version>
    ) -> Package.Dependency {
        return .package(identity: identity, .rangeItem(range))
    }

    /// Adds a package dependency starting with a specific minimum version, going
    /// up to and including a specific maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.
    ///
    ///     .package(identity: "scope/name", "1.2.3"..."1.2.6"),
    ///
    /// - Parameters:
    ///     - identity: The identity of the package.
    ///     - range: The closed version range requirement.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        identity: String,
        _ range: ClosedRange<Version>
    ) -> Package.Dependency {
        // Increase upperbound's patch version by one.
        let upper = range.upperBound
        let upperBound = Version(
            upper.major, upper.minor, upper.patch + 1,
            prereleaseIdentifiers: upper.prereleaseIdentifiers,
            buildMetadataIdentifiers: upper.buildMetadataIdentifiers)
        return .package(identity: identity, .rangeItem(range.lowerBound..<upperBound))
    }

    /// Adds a remote package dependency with a given version requirement.
    ///
    /// - Parameters:
    ///     - identity: The identity of the package.
    ///     - requirement: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        identity: String,
        _ requirement: Package.Dependency.Requirement
    ) -> Package.Dependency {
        precondition(!requirement.isLocalPackage, "Use `.package(path:)` API to declare a local package dependency")
        return .init(identity: identity, requirement: requirement)
    }
}


// MARK: - common APIs used by mistake as unavailable to provide better error messages.

extension Package.Dependency {
    @available(*, unavailable, message: "use package(url:_:) with the .exact(Version) initializer instead")
    public static func package(url: String, version: Version) -> Package.Dependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) without the range label instead")
    public static func package(url: String, range: Range<Version>) -> Package.Dependency {
        fatalError()
    }
}
