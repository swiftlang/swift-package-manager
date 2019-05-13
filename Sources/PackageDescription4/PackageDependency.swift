/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Package.Dependency {

    /// Add a package dependency that is required from the given minimum version,
    /// going up to the next major version. 
    ///
    /// This is the recommend way to specify a remote package dependency because
    /// it allows you to specify the minimum version you require and gives
    /// explicit opt-in for new major versions, but otherwise provides maximal
    /// flexibility on which version is used. This helps to prevent conflicts in
    /// your package dependency graph.
    ///
    /// For example, specifying
    ///
    ///    .package(url: "https://example.com/example-package.git", from: "1.2.3"),
    ///
    /// will allow the Swift package manager to select a version like a "1.2.3",
    /// "1.2.4" or "1.3.0" but not "2.0.0".
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - version: The minimum version requirement.
    public static func package(
        url: String,
        from version: Version
    ) -> Package.Dependency {
        return .package(url: url, .upToNextMajor(from: version))
    }

    /// Add a remote package dependency given a version requirement.
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - requirement: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    public static func package(
        url: String,
        _ requirement: Package.Dependency.Requirement
    ) -> Package.Dependency {
        precondition(!requirement.isLocalPackage, "Use `.package(path:)` API to declare a local package dependency")
        return .init(url: url, requirement: requirement)
    }

    /// Add a package dependency starting with a specific minimum version, up to
    /// but not including a specific maximum version.
    ///
    /// For example
    ///
    ///     .package(url: "https://example.com/example-package.git", "1.2.3"..<"1.2.6"),
    ///
    /// will allow the Swift package manager to pick versions 1.2.3, 1.2.4, 1.2.5, but not 1.2.6.
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - range: The custom version range requirement.
    public static func package(
        url: String,
        _ range: Range<Version>
    ) -> Package.Dependency {
      #if PACKAGE_DESCRIPTION_4
        return .init(url: url, requirement: .rangeItem(range))
      #else
        return .init(url: url, requirement: ._rangeItem(range))
      #endif
    }

    /// Add a package dependency starting with a specific minimum version, going
    /// up to and including a specific maximum version.
    ///
    /// For example
    ///
    ///     .package(url: "https://example.com/example-package.git", "1.2.3"..."1.2.6"),
    ///
    /// will allow the Swift package manager to pick versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - range: The closed version range requirement.
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
        return .package(url: url, range.lowerBound..<upperBound)
    }

  #if !PACKAGE_DESCRIPTION_4
    /// Add a dependency to a local package on the filesystem.
    ///
    /// The package dependency is used as-is and no source control access is
    /// performed. Local package dependencies are especially useful during
    /// development of a new package or when working on multiple tightly-coupled
    /// packages.
    ///
    /// - Parameter path: The path of the package.
    public static func package(
        path: String
    ) -> Package.Dependency {
        return .init(url: path, requirement: ._localPackageItem)
    }
  #endif
}

// Mark common APIs used by mistake as unavailable to provide better error messages.
extension Package.Dependency {
    @available(*, unavailable, message: "use package(url:_:) with the .exact(Version) initializer instead")
    public static func package(url: String, version: Version) -> Package.Dependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) with the .branch(String) initializer instead")
    public static func package(url: String, branch: String) -> Package.Dependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) with the .revision(String) initializer instead")
    public static func package(url: String, revision: String) -> Package.Dependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) without the range label instead")
    public static func package(url: String, range: Range<Version>) -> Package.Dependency {
        fatalError()
    }
}
