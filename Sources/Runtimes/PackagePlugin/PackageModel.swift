//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// A single package in a graph of packages.
///
/// The package can either be the root package, or a dependency.
public struct Package {
    /// The unique identifier for the package.
    public let id: ID
    /// The type that represents a package identifier.
    public typealias ID = String

    /// The name of the package.
    ///
    /// Use the name for display purposes only.
    public let displayName: String

    /// The absolute path of the package directory in the local file system.
    @available(_PackageDescription, deprecated: 6.0, renamed: "directoryURL")
    public let directory: Path

    /// The file URL of the package directory in the local file system.
    @available(_PackageDescription, introduced: 6.0)
    public let directoryURL: URL

    /// The origin of the package.
    public let origin: PackageOrigin

    /// The tools version specified by the resolved version of the package.
    ///
    /// Behavior is often gated on the tools version to make sure older
    /// packages continue to work as intended.
    public let toolsVersion: ToolsVersion

    /// Any dependencies on other packages.
    ///
    /// The dependencies are included in the same order as
    /// specified in the package manifest.
    public let dependencies: [PackageDependency]

    /// Any regular products defined in this package, with the exception of plugin products.
    ///
    /// The products are specified in the same order as the package manifest.
    public let products: [Product]

    /// Any regular targets defined in this packagewith the exception of plugin targets.
    ///
    /// The targets are specified in the same order as the package manifest.
    public let targets: [Target]
}

/// The origin of a package.
public enum PackageOrigin {
    /// A root package.
    ///
    /// The root package is unversioned.
    case root

    /// A local package, referenced by path.
    ///
    /// A local package is unversioned.
    case local(path: String)

    /// A package from a Git repository, with a URL and with a textual
    /// description of the resolved version or branch name (for display
    /// purposes only), and the corresponding SCM revision.
    ///
    /// The
    /// revision is the Git commit hash and may be useful for plugins
    /// that generates source code that includes version information.
    case repository(url: String, displayVersion: String, scmRevision: String)

    /// A package from a registry, with an identity and with a textual
    /// description of the resolved version or branch name (for display
    /// purposes only).
    case registry(identity: String, displayVersion: String)
}

/// A version of Swift package manager on whose semantics a package relies.
public struct ToolsVersion {
    /// The major version.
    public let major: Int

    /// The minor version.
    public let minor: Int

    /// The patch version.
    public let patch: Int

    @_spi(PackagePluginInternal) public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

/// A resolved dependency of a package.
///
/// This is a separate entity in order to make it easier for future versions of the API to
/// add information about the dependency itself.
public struct PackageDependency {
    /// The package that is a dependency.
    public let package: Package

    init(package: Package) {
        self.package = package
    }
}

/// A single product defined in a package.
public protocol Product {
    /// Unique identifier for the product.
    var id: ID { get }
    /// The type that represents the identifier of a package product.
    typealias ID = String

    /// The name of the product, as defined in the package manifest.
    ///
    /// This name is unique among the products of the package in which it is defined.
    var name: String { get }

    /// The targets that directly comprise the product, in the order in which
    /// they are declared in the package manifest.
    ///
    /// The product contains the transitive closure of the these targets and their
    /// dependencies. Some kinds of products have further restrictions on the set of
    /// targets (for example, an executable product must have one and only one
    /// target that defines the main entry point for an executable).
    var targets: [Target] { get }
}

/// An executable product defined in a package.
public struct ExecutableProduct: Product {
    /// Unique identifier for the product.
    public let id: ID

    /// The name of the product, as defined in the package manifest.
    ///
    /// This name is unique among the products of the package in which it is defined.
    public let name: String

    /// The targets that directly comprise the product, in the order in which
    /// they are declared in the package manifest.
    ///
    /// The product contains the transitive closure of the these targets and their dependencies.
    /// For an `ExecutableProduct`, exactly one of the targets in this list must be an
    /// `ExecutableTarget`.
    public let targets: [Target]

    /// The target that contains the main entry point of the executable.
    ///
    /// Every executable product has exactly one main executable target. This target
    /// will always be one of the targets in the product's `targets` array.
    public let mainTarget: Target
}

/// A library product defined in a package.
public struct LibraryProduct: Product {
    /// Unique identifier for the product.
    public let id: ID

    /// The name of the product, as defined in the package manifest.
    ///
    /// This name is unique among the products of the package in which
    /// it is defined.
    public let name: String

    /// The targets that directly comprise the product, in the order in which
    /// they are declared in the package manifest.
    ///
    /// The product contains the transitive closure of the these targets
    /// and their dependencies.
    public let targets: [Target]

    /// A value that indicates whether the library is static, dynamic, or automatically determined.
    public let kind: Kind

    /// The kind of library product.
    public enum Kind {
        /// A static library, whose code is copied into its clients.
        case `static`

        /// Dynamic library, whose code is referenced by its clients.
        case dynamic

        /// The kind of library produced is unspecified and will be determined
        /// by the build system based on how the library is used.
        case automatic
    }
}

/// A single target defined in a package.
public protocol Target {
    /// Unique identifier for the target.
    var id: ID { get }
    /// The type that represents the ID of the target.
    typealias ID = String

    /// The name of the target, as defined in the package manifest.
    ///
    /// This name is unique among the targets of the package in which it is defined.
    var name: String { get }

    /// The absolute path of the target directory in the local file system.
    @available(_PackageDescription, deprecated: 6.1, renamed: "directoryURL")
    var directory: Path { get }

    /// The file URL of the target directory in the local file system.
    @available(_PackageDescription, introduced: 6.1)
    var directoryURL: URL { get }

    /// Any other targets on which this target depends, in the same order as
    /// they are specified in the package manifest.
    ///
    /// Conditional dependencies that do not apply are filtered out.
    var dependencies: [TargetDependency] { get }
}

/// A dependency of a target on a product or on another target.
public enum TargetDependency {
    /// A dependency on a target in the same package.
    case target(Target)

    /// A dependency on a product in another package.
    case product(Product)
}

/// A target consisting of a source code module.
///
/// The module contains either Swift or source files in one of
/// the C-based languages.
public protocol SourceModuleTarget: Target {
    /// The name of the module produced by the target.
    ///
    /// Derived from the target name, though future Swift package manager versions may
    /// allow this to be customized.
    var moduleName: String { get }

    /// The kind of module, describing whether it contains unit tests, contains
    /// the main entry point of an executable, or neither.
    var kind: ModuleKind { get }

    /// The source files that are associated with this target.
    ///
    /// Any files that have been excluded in the manifest are filtered out.
    var sourceFiles: FileList { get }

    /// Any custom linked libraries required by the module, as specified in the
    /// package manifest.
    var linkedLibraries: [String] { get }

    /// Any custom linked frameworks required by the module, as specified in the
    /// package manifest.
    var linkedFrameworks: [String] { get }

    /// The file URLs of any sources generated by other plugins applied to the given target before the plugin
    /// being executed.
    ///
    /// Note: Plugins are applied in order of declaration in the package manifest. Generated files are vended to the
    /// target the current plugin is being applied to, but not necessarily to other targets in the package graph.
    @available(_PackageDescription, introduced: 6.0)
    var pluginGeneratedSources: [URL] { get }

    /// The file URLs of any resources generated by other plugins that have been applied to the given target
    /// before the plugin currently being executed.
    ///
    /// Note: Plugins are applied in order of declaration in the package manifest. Generated files are vended to the
    /// target the current plugin is being applied to, but not necessarily to other targets in the package graph.
    @available(_PackageDescription, introduced: 6.0)
    var pluginGeneratedResources: [URL] { get }
}

/// The kind of module.
public enum ModuleKind {
    /// A module that contains generic code (not a test nor an executable).
    case generic
    /// A module that contains code for an executable's main module.
    case executable
    /// A module that contains code for a snippet.
    @available(_PackageDescription, introduced: 5.8)
    case snippet
    /// A module that contains unit tests.
    case test
    /// A module that contains code for a macro.
    @available(_PackageDescription, introduced: 5.9)
    case macro  // FIXME: This should really come from `CompilerPluginSupport` somehow, but we lack the infrastructure to allow that currently.
}

/// A target consisting of a source code module compiled using Swift.
public struct SwiftSourceModuleTarget: SourceModuleTarget {
    /// Unique identifier for the target.
    public let id: ID

    /// The name of the target, as defined in the package manifest.
    ///
    /// This name is unique among the targets of the package in which it is defined.
    public let name: String

    /// The kind of module, describing whether it contains unit tests, contains
    /// the main entry point of an executable, or neither.
    public let kind: ModuleKind

    /// The absolute path of the target directory in the local file system.
    @available(_PackageDescription, deprecated: 6.0, renamed: "directoryURL")
    public let directory: Path

    /// The file URL of the target directory in the local file system.
    @available(_PackageDescription, introduced: 6.0)
    public let directoryURL: URL

    /// Any other targets on which this target depends, in the same order as
    /// specified in the package manifest.
    ///
    /// Conditional dependencies that do not apply have already been filtered out.
    public let dependencies: [TargetDependency]

    /// The name of the module produced by the target.
    ///
    /// This is derived from the target name, though future Swift package manager
    /// versions may allow this to be customized.
    public let moduleName: String

    /// The source files associated with this target
    ///
    /// Any files that have been excluded in the manifest have already been filtered out.
    public let sourceFiles: FileList

    /// Any custom compilation conditions specified for the Swift target in the
    /// package manifest.
    public let compilationConditions: [String]

    /// Any custom linked libraries required by the module, as specified in the
    /// package manifest.
    public let linkedLibraries: [String]

    /// Any custom linked frameworks required by the module, as specified in the
    /// package manifest.
    public let linkedFrameworks: [String]

    /// The file URLs of any sources generated by other plugins that have been applied
    /// to the given target before the plugin being executed.
    @available(_PackageDescription, introduced: 6.0)
    public let pluginGeneratedSources: [URL]

    /// The file URLS of any resources generated by other plugins that have been applied
    /// to the given target before the plugin being executed.
    @available(_PackageDescription, introduced: 6.0)
    public let pluginGeneratedResources: [URL]
}

/// A target consisting of a source code module compiled using Clang.
public struct ClangSourceModuleTarget: SourceModuleTarget {
    /// Unique identifier for the target.
    public let id: ID

    /// The name of the target, as defined in the package manifest.
    ///
    /// This name is unique among the targets of the package in which it is defined.
    public let name: String

    /// The kind of module.
    ///
    /// The kind of module describes whether it contains unit tests,
    /// the main entry point of an executable, or neither.
    public let kind: ModuleKind

    /// The absolute path of the target directory in the local file system.
    @available(_PackageDescription, deprecated: 6.0, renamed: "directoryURL")
    public let directory: Path

    /// The file URL of the target directory in the local file system.
    @available(_PackageDescription, introduced: 6.0)
    public let directoryURL: URL

    /// Any other targets on which this target depends, in the same order as
    /// specified in the package manifest.
    ///
    /// Conditional dependencies that do not apply have already been filtered out.
    public let dependencies: [TargetDependency]

    /// The name of the module produced by the target.
    ///
    /// This is derived from the target name, though future Swift package manager
    /// versions may allow this to be customized.
    public let moduleName: String

    /// The source files that are associated with this target.
    ///
    /// Any files that have been excluded in the manifest have already been filtered out.
    public let sourceFiles: FileList

    /// Any preprocessor definitions specified for the Clang target.
    public let preprocessorDefinitions: [String]

    /// Any custom header search paths specified for the Clang target.
    public let headerSearchPaths: [String]

    /// The directory containing public C headers, if applicable.
    ///
    /// This will only be set for targets that have a directory of a public headers.
    @available(_PackageDescription, deprecated: 6.0, renamed: "publicHeadersDirectoryURL")
    public let publicHeadersDirectory: Path?

    /// The directory containing public C headers, if applicable.
    ///
    /// This will only be set for targets that have a directory of a public headers.
    @available(_PackageDescription, introduced: 6.0)
    public let publicHeadersDirectoryURL: URL?

    /// Any custom linked libraries required by the module, as specified in the
    /// package manifest.
    public let linkedLibraries: [String]

    /// Any custom linked frameworks required by the module, as specified in the
    /// package manifest.
    public let linkedFrameworks: [String]

    /// The file URLs of any sources generated by other plugins that have been applied
    /// to the given target before the plugin currently being executed.
    @available(_PackageDescription, introduced: 6.0)
    public let pluginGeneratedSources: [URL]

    /// The file URLs of any resources generated by other plugins that have been applied
    /// to the given target before the plugin currently being executed.
    @available(_PackageDescription, introduced: 6.0)
    public let pluginGeneratedResources: [URL]
}

/// A target describing an artifact that is distributed as a binary.
///
/// For example, a library or executable.
public struct BinaryArtifactTarget: Target {
    /// Unique identifier for the target.
    public let id: ID

    /// The name of the target, as defined in the package manifest.
    ///
    /// This name is unique among the targets of the package in which it is defined.
    public let name: String

    /// The absolute path of the target directory in the local file system.
    @available(_PackageDescription, deprecated: 6.0, renamed: "directoryURL")
    public let directory: Path

    /// The file URL of the target directory in the local file system.
    @available(_PackageDescription, introduced: 6.0)
    public let directoryURL: URL

    /// Any other targets on which this target depends, in the same order as
    /// specified in the package manifest.
    ///
    /// Conditional dependencies that do not apply have already been filtered out.
    public let dependencies: [TargetDependency]

    /// The kind of binary artifact.
    public let kind: Kind

    /// The original source of the binary artifact.
    public let origin: Origin

    /// The path location of the binary artifact in the local file system.
    @available(_PackageDescription, deprecated: 6.0, renamed: "artifactURL")
    public let artifact: Path

    /// The file URL of the location of the binary artifact in the local file system.
    @available(_PackageDescription, introduced: 6.0)
    public let artifactURL: URL

    /// A kind of binary artifact.
    public enum Kind {
        /// An XCFramework.
        case xcframework
        /// An artifact archive.
        case artifactsArchive
    }

    /// The original location of a binary artifact.
    public enum Origin: Equatable {
        /// An artifact that was available locally.
        case local

        /// An artifact that was downloaded from a remote URL.
        case remote(url: String)
    }
}

/// A target describing a system library that is expected to be
/// present on the host system.
public struct SystemLibraryTarget: Target {
    /// Unique identifier for the target.
    public let id: ID

    /// The name of the target, as defined in the package manifest.
    ///
    /// This name is unique among the targets of the package in which it is defined.
    public var name: String

    /// The absolute path of the target directory in the local file system.
    @available(_PackageDescription, deprecated: 6.0, renamed: "directoryURL")
    public var directory: Path

    /// The file URL of the target directory in the local file system.
    @available(_PackageDescription, introduced: 6.0)
    public var directoryURL: URL

    /// Any other targets on which this target depends, in the same order as
    /// specified in the package manifest.
    ///
    /// Conditional dependencies that do not apply have already been filtered out.
    public var dependencies: [TargetDependency]

    /// The name of the `pkg-config` file, if any, describing the library.
    public let pkgConfig: String?

    /// Flags from `pkg-config` to pass to Clang and SwiftC.
    ///
    /// Flags are passed to using `-Xcc`.
    public let compilerFlags: [String]

    /// Flags from `pkg-config` to pass to the platform linker.
    public let linkerFlags: [String]
}

/// Provides information about a list of files.
///
/// The order is not defined but is guaranteed to be stable.
/// This allows the implementation to be more efficient than a static file list.
public struct FileList {
    private var files: [File]

    @_spi(PackagePluginInternal) public init(_ files: [File]) {
        self.files = files
    }
}

extension FileList: Sequence {
    public struct Iterator: IteratorProtocol {
        private var files: ArraySlice<File>
        fileprivate init(files: ArraySlice<File>) {
            self.files = files
        }

        public mutating func next() -> File? {
            guard let nextInfo = self.files.popFirst() else {
                return nil
            }
            return nextInfo
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(files: ArraySlice(self.files))
    }
}

@available(_PackageDescription, introduced: 5.10)
extension FileList: RandomAccessCollection {
    public var startIndex: Int { 0 }
    public var endIndex: Int { self.files.endIndex }
    public subscript(i: Int) -> File { self.files[i] }
}

/// Information about a single file in a FileList.
public struct File {
    /// The path of the file.
    @available(_PackageDescription, deprecated: 6.0, renamed: "url")
    public var path: Path {
        return try! Path(url: url)
    }

    /// The URL of the file.
    @available(_PackageDescription, introduced: 6.0)
    public let url: URL

    /// The File type, as determined by Swift package manager.
    public let type: FileType

    @_spi(PackagePluginInternal) public init(url: URL, type: FileType) {
        self.url = url
        self.type = type
    }
}

/// Information about the type of a file.
///
/// Future cases will use availability annotations to make sure existing plugins
/// continue to work until they increase their required tools version.
public enum FileType {
    /// A source file.
    case source

    /// A header file.
    case header

    /// A resource file.
    ///
    /// A resource file may be either processed or copied.
    case resource

    /// A file not covered by any other rule.
    case unknown
}

/// Provides information about a list of paths.
///
/// The order is not defined but is guaranteed to be stable.
/// This allows the implementation to be more efficient than a static path list.
public struct PathList {
    private var paths: [URL]

    @_spi(PackagePluginInternal) public init(_ paths: [URL]) {
        self.paths = paths
    }
}
extension PathList: Sequence {
    public struct Iterator: IteratorProtocol {
        private var paths: ArraySlice<Path>
        fileprivate init(paths: ArraySlice<Path>) {
            self.paths = paths
        }
        mutating public func next() -> Path? {
            guard let nextInfo = self.paths.popFirst() else {
                return nil
            }
            return nextInfo
        }
    }
    public func makeIterator() -> Iterator {
        // FIXME: This iterator should be converted to URLs, too, but that doesn't seem to be possible without breaking source compatibility
        return Iterator(paths: ArraySlice(self.paths.map { try! Path(url: $0) }))
    }
}
