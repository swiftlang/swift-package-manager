/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// MARK: - file system

extension Package {
    /// A package dependency of a Swift package.
    ///
    /// A package dependency consists of a Git URL to the source of the package,
    /// and a requirement for the version of the package.
    ///
    /// The Swift Package Manager performs a process called *dependency resolution* to
    /// figure out the exact version of the package dependencies that an app or other
    /// Swift package can use. The `Package.resolved` file records the results of the
    /// dependency resolution and lives in the top-level directory of a Swift package.
    /// If you add the Swift package as a package dependency to an app for an Apple platform,
    /// you can find the `Package.resolved` file inside your `.xcodeproj` or `.xcworkspace`.
    public class Dependency: Encodable {

        public enum Kind: Encodable {
            case fileSystem(name: String?, path: String)
            case sourceControl(name: String?, location: String, requirement: SourceControlRequirement)
            case registry(identity: String, requirement: RegistryRequirement)
        }

        @available(_PackageDescription, introduced: 999)
        public let kind: Kind

        /// The name of the package, or `nil` to deduce the name using the package's Git URL.
        @available(*, deprecated, message: "use kind instead")
        public var name: String? {
            get {
                switch self.kind {
                case .fileSystem(name: let name, path: _):
                    return name
                case .sourceControl(name: let name, location: _, requirement: _):
                    return name
                case .registry:
                    return nil
                }
            }
        }

        @available(*, deprecated, message: "use kind instead")
        public var url: String? {
            get {
                switch self.kind {
                case .fileSystem(name: _, path: let path):
                    return path
                case .sourceControl(name: _, location: let location, requirement: _):
                    return location
                case .registry:
                    return nil
                }
            }
        }

        /// The dependency requirement of the package dependency.
        @available(*, deprecated, message: "use kind instead")
        public var requirement: Requirement {
            get {
                switch self.kind {
                case .fileSystem:
                    return .localPackageItem
                case .sourceControl(name: _, location: _, requirement: let requirement):
                    switch requirement {
                    case .branch(let branch):
                        return .branchItem(branch)
                    case .exact(let version):
                        return .exactItem(version)
                    case .range(let range):
                        return .rangeItem(range)
                    case .revision(let revision):
                        return .revisionItem(revision)
                    }
                case .registry(identity: _, requirement: let requirement):
                    switch requirement {
                    case .exact(let version):
                        return .exactItem(version)
                    case .range(let range):
                        return .rangeItem(range)
                    }
                }
            }
        }

        /// Initializes and returns a newly allocated requirement with the specified url and requirements.
        @available(_PackageDescription, deprecated: 999)
        convenience init(name: String?, url: String, requirement: Requirement) {
            switch requirement {
            case .localPackageItem:
                self.init(name: name, path: url)
            case .branchItem(let branch):
                self.init(name: name, location: url, requirement: .branch(branch))
            case .exactItem(let version):
                self.init(name: name, location: url, requirement: .exact(version))
            case .revisionItem(let revision):
                self.init(name: name, location: url, requirement: .revision(revision))
            case .rangeItem(let range):
                self.init(name: name, location: url, requirement: .range(range))
            }
        }

        @available(_PackageDescription, introduced: 999)
        init(kind: Kind) {
            self.kind = kind
        }

        @available(_PackageDescription, introduced: 999)
        convenience init(name: String?, path: String) {
            self.init(kind: .fileSystem(name: name, path: path))
        }

        @available(_PackageDescription, introduced: 999)
        convenience init(name: String?, location: String, requirement: SourceControlRequirement) {
            self.init(kind: .sourceControl(name: name, location: location, requirement: requirement))
        }

        /// Initializes and returns a newly allocated requirement with the specified identity and requirements.
        @available(_PackageDescription, introduced: 999)
        convenience init(identity: String, requirement: RegistryRequirement) {
            self.init(kind: .registry(identity: identity, requirement: requirement))
        }
    }
}

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
        return .package(name: nil, path: path)
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
        return .init(name: name, path: path)
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
        return .package(name: nil, url: url, from: version)
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
        return .package(name: name, url: url, requirement: .branch(branch))
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
        return .package(name: name, url: url, requirement: .revision(revision))
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
        return .package(name: nil, url: url, range)
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
        return .package(name: name, url: url, requirement: .range(range))
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
        return .package(name: nil, url: url, range)
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
        return .package(name: name, url: url, range.lowerBound ..< upperBound)
    }

    /// Adds a package dependency that uses the exact version requirement.
    ///
    /// This is the recommended way to specify a remote package dependency.
    /// It allows you to specify the minimum version you require, allows updates that include bug fixes
    /// and backward-compatible feature updates, but requires you to explicitly update to a new major version of the dependency.
    /// This approach provides the maximum flexibility on which version to use,
    /// while making sure you don't update to a version with breaking changes,
    /// and helps to prevent conflicts in your dependency graph.
    ///
    /// The following example instruct the Swift Package Manager to use version `1.2.3`.
    ///
    ///    .package(identity: "scope.name", exact: "1.2.3"),
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - version: The minimum version requirement.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        url: String,
        exact version: Version
    ) -> Package.Dependency {
        return .package(name: nil, url: url, exact: version)
    }

    /// Adds a package dependency that uses the exact version requirement.
    ///
    /// This is the recommended way to specify a remote package dependency.
    /// It allows you to specify the minimum version you require, allows updates that include bug fixes
    /// and backward-compatible feature updates, but requires you to explicitly update to a new major version of the dependency.
    /// This approach provides the maximum flexibility on which version to use,
    /// while making sure you don't update to a version with breaking changes,
    /// and helps to prevent conflicts in your dependency graph.
    ///
    /// The following example instruct the Swift Package Manager to use version `1.2.3`.
    ///
    ///    .package(identity: "scope.name", exact: "1.2.3"),
    ///
    /// - Parameters:
    ///     - name: The name of the package, or `nil` to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - version: The minimum version requirement.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        name: String? = nil,
        url: String,
        exact version: Version
    ) -> Package.Dependency {
        return .init(name: name, location: url, requirement: .exact(version))
    }

    /// Adds a remote package dependency given a version requirement.
    ///
    /// - Parameters:
    ///     - name: The name of the package, or nil to deduce it from the URL.
    ///     - url: The valid Git URL of the package.
    ///     - requirement: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    @available(_PackageDescription, obsoleted: 5.2, deprecated: 999)
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
    @available(_PackageDescription, introduced: 5.2, deprecated: 999)
    public static func package(
        name: String? = nil,
        url: String,
        _ requirement: Package.Dependency.Requirement
    ) -> Package.Dependency {
        precondition(!requirement.isLocalPackage, "Use `.package(path:)` API to declare a local package dependency")
        return .init(name: name, url: url, requirement: requirement)
    }

    // intentionally private to hide enum detail
    @available(_PackageDescription, introduced: 999)
    private static func package(
        name: String? = nil,
        url: String,
        requirement: Package.Dependency.SourceControlRequirement
    ) -> Package.Dependency {
        return .init(name: name, location: url, requirement: requirement)
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
    ///    .package(identity: "scope.name", from: "1.2.3"),
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

    /// Adds a package dependency that uses the exact version requirement.
    ///
    /// This is the recommended way to specify a remote package dependency.
    /// It allows you to specify the minimum version you require, allows updates that include bug fixes
    /// and backward-compatible feature updates, but requires you to explicitly update to a new major version of the dependency.
    /// This approach provides the maximum flexibility on which version to use,
    /// while making sure you don't update to a version with breaking changes,
    /// and helps to prevent conflicts in your dependency graph.
    ///
    /// The following example instruct the Swift Package Manager to use version `1.2.3`.
    ///
    ///    .package(identity: "scope.name", exact: "1.2.3"),
    ///
    /// - Parameters:
    ///     - identity: The identity of the package.
    ///     - version: The minimum version requirement.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        identity: String,
        exact version: Version
    ) -> Package.Dependency {
        return .package(identity: identity, requirement: .exact(version))
    }

    /// Adds a package dependency starting with a specific minimum version, up to
    /// but not including a specified maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions `1.2.3`, `1.2.4`, `1.2.5`, but not `1.2.6`.
    ///
    ///     .package(identity: "scope.name", "1.2.3"..<"1.2.6"),
    ///
    /// - Parameters:
    ///     - identity: The identity of the package.
    ///     - range: The custom version range requirement.
    @available(_PackageDescription, introduced: 999)
    public static func package(
        identity: String,
        _ range: Range<Version>
    ) -> Package.Dependency {
        return .package(identity: identity, requirement: .range(range))
    }

    /// Adds a package dependency starting with a specific minimum version, going
    /// up to and including a specific maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.
    ///
    ///     .package(identity: "scope.name", "1.2.3"..."1.2.6"),
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
        return .package(identity: identity, range.lowerBound ..< upperBound)
    }

    // intentionally private to hide enum detail
    @available(_PackageDescription, introduced: 999)
    private static func package(
        identity: String,
        requirement: Package.Dependency.RegistryRequirement
    ) -> Package.Dependency {
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
