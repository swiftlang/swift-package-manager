/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(Linux)
import Glibc
#elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import Darwin.C
#elseif os(Windows)
import ucrt
#endif
import Foundation

/// The `Package` type is used to configure the name, products, targets,
/// dependencies and various other parts of the package.
///
/// By convention, the properties of a `Package` are defined in a single nested
/// initializer statement, and not modified after initialization. For example:
///
///     // swift-tools-version:5.0
///     import PackageDesc ription
///
///     let package = Package(
///         name: "MyLibrary",
///         platforms: [
///             .macOS(.v10_14),
///         ],
///         products: [
///             .library(name: "MyLibrary", targets: ["MyLibrary"]),
///         ],
///         dependencies: [
///             .package(url: "https://url/of/another/package/named/Utility", from: "1.0.0"),
///         ],
///         targets: [
///             .target(name: "MyLibrary", dependencies: ["Utility"]),
///             .testTarget(name: "MyLibraryTests", dependencies: ["MyLibrary"]),
///         ]
///     )
///
/// # About the Swift Tools Version
///
/// A Package.swift manifest file must begin with the string `//
/// swift-tools-version:` followed by a version number specifier.
///
/// Examples:
///
///     // swift-tools-version:3.0.2
///     // swift-tools-version:3.1
///     // swift-tools-version:4.0
///     // swift-tools-version:5.0
///
/// The Swift tools version declares the version of the `PackageDescription`
/// library, the minimum version of the Swift tools and Swift language
/// compatibility version to process the manifest, and the minimum version of the
/// Swift tools that are needed to use the Swift package. Each version of Swift
/// can introduce updates to the `PackageDescription` library, but the previous
/// API version will continue to be available to packages which declare a prior
/// tools version. This behavior lets you take advantage of new releases of
/// Swift, the Swift tools, and the `PackageDescription` library, without having
/// to update your package's manifest or losing access to existing packages.
public final class Package {

      /// A package dependency consists of a Git URL to the source of the package,
      /// and a requirement for the version of the package that can be used.
      ///
      /// The Swift Package Manager performs a process called dependency resolution to
      /// figure out the exact version of the package dependencies that can be used in
      /// your package. The results of the dependency resolution are recorded in the
      /// `Package.resolved` file which will be placed in the top-level directory of
      /// your package.
      public class Dependency: Encodable {

        /// The dependency requirement can be defined as one of three different version requirements.
        ///
        /// 1. Version-based Requirement
        ///
        ///     A requirement which restricts what version of a dependency your
        ///     package can use based on its available versions. When a new package
        ///     version is published, it should increment the major version component
        ///     if it has backwards-incompatible changes. It should increment the
        ///     minor version component if it adds new functionality in
        ///     a backwards-compatible manner. And it should increment the patch
        ///     version if it makes backwards-compatible bugfixes. To learn more about
        ///     the syntax of semantic versioning syntax, see `Version` or visit
        ///     https://semver.org (https://semver.org/).
        ///
        /// 2. Branch-based Requirement
        ///
        ///     Specify the name of a branch that a dependency will follow. This is
        ///     useful when developing multiple packages which are closely related,
        ///     allowing you to keep them in sync during development. Note that
        ///     packages which use branch-based dependency requirements cannot be
        ///     depended-upon by packages which use version-based dependency
        ///     requirements; you should remove branch-based dependency requirements
        ///     before publishing a version of your package.
        ///
        /// 3. Commit-based Requirement
        ///
        ///     A requirement that restricts a dependency to a specific commit
        ///     hash. This is useful if you want to pin your package to a specific
        ///     commit hash of a dependency. Note that packages which use
        ///     commit-based dependency requirements cannot be depended-upon by
        ///     packages which use version-based dependency requirements; you
        ///     should remove commit-based dependency requirements before
        ///     publishing a version of your package.
        public enum Requirement {
          #if PACKAGE_DESCRIPTION_4
            case exactItem(Version)
            case rangeItem(Range<Version>)
            case revisionItem(String)
            case branchItem(String)
            case localPackageItem
          #else
            case _exactItem(Version)
            case _rangeItem(Range<Version>)
            case _revisionItem(String)
            case _branchItem(String)
            case _localPackageItem
          #endif

            var isLocalPackage: Bool {
              #if PACKAGE_DESCRIPTION_4
                if case .localPackageItem = self { return true }
              #else
                if case ._localPackageItem = self { return true }
              #endif
                return false
            }
        }

        /// The url of the dependency.
        public let url: String

        /// The dependency requirement.
        public let requirement: Requirement

        /// Create a dependency.
        init(url: String, requirement: Requirement) {
            self.url = url
            self.requirement = requirement
        }
    }

    /// The name of the package.
    public var name: String

  #if !PACKAGE_DESCRIPTION_4
    /// The list of platforms supported by this package.
    @available(_PackageDescription, introduced: 5)
    public var platforms: [SupportedPlatform]? {
        get { return _platforms }
        set { _platforms = newValue }
    }
  #endif
    private var _platforms: [SupportedPlatform]?

    /// pkgconfig name to use for C Modules. If present, swiftpm will try to
    /// search for <name>.pc file to get the additional flags needed for the
    /// system target.
    public var pkgConfig: String?

    /// Providers array for System target
    public var providers: [SystemPackageProvider]?

    /// The list of targets.
    public var targets: [Target]

    /// The list of products vended by this package.
    public var products: [Product]

    /// The list of dependencies.
    public var dependencies: [Dependency]

  #if PACKAGE_DESCRIPTION_4
    /// The list of swift versions, this package is compatible with.
    public var swiftLanguageVersions: [Int]?
  #else
    /// The list of swift versions, this package is compatible with.
    public var swiftLanguageVersions: [SwiftVersion]?
  #endif

    /// The C language standard to use for all C targets in this package.
    public var cLanguageStandard: CLanguageStandard?

    /// The C++ language standard to use for all C++ targets in this package.
    public var cxxLanguageStandard: CXXLanguageStandard?

  #if PACKAGE_DESCRIPTION_4
    /// Construct a package.
    public init(
        name: String,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil,
        products: [Product] = [],
        dependencies: [Dependency] = [],
        targets: [Target] = [],
        swiftLanguageVersions: [Int]? = nil,
        cLanguageStandard: CLanguageStandard? = nil,
        cxxLanguageStandard: CXXLanguageStandard? = nil
    ) {
        self.name = name
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.products = products
        self.dependencies = dependencies
        self.targets = targets
        self.swiftLanguageVersions = swiftLanguageVersions
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        registerExitHandler()
    }
  #else
    @available(_PackageDescription, introduced: 4.2, obsoleted: 5)
    public init(
        name: String,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil,
        products: [Product] = [],
        dependencies: [Dependency] = [],
        targets: [Target] = [],
        swiftLanguageVersions: [SwiftVersion]? = nil,
        cLanguageStandard: CLanguageStandard? = nil,
        cxxLanguageStandard: CXXLanguageStandard? = nil
    ) {
        self.name = name
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.products = products
        self.dependencies = dependencies
        self.targets = targets
        self.swiftLanguageVersions = swiftLanguageVersions
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        registerExitHandler()
    }

    /// Construct a package.
    @available(_PackageDescription, introduced: 5)
    public init(
        name: String,
        platforms: [SupportedPlatform]? = nil,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil,
        products: [Product] = [],
        dependencies: [Dependency] = [],
        targets: [Target] = [],
        swiftLanguageVersions: [SwiftVersion]? = nil,
        cLanguageStandard: CLanguageStandard? = nil,
        cxxLanguageStandard: CXXLanguageStandard? = nil
    ) {
        self.name = name
        self._platforms = platforms
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.products = products
        self.dependencies = dependencies
        self.targets = targets
        self.swiftLanguageVersions = swiftLanguageVersions
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        registerExitHandler()
    }
  #endif

    private func registerExitHandler() {
        // Add custom exit handler to cause package to be dumped at exit, if
        // requested.
        //
        // FIXME: This doesn't belong here, but for now is the mechanism we use
        // to get the interpreter to dump the package when attempting to load a
        // manifest.
        if CommandLine.argc > 0,
           let fileNoOptIndex = CommandLine.arguments.index(of: "-fileno"),
           let fileNo = Int32(CommandLine.arguments[fileNoOptIndex + 1]) {
            dumpPackageAtExit(self, fileNo: fileNo)
        }
    }
}

/// Represents system package providers.
public enum SystemPackageProvider {

  #if PACKAGE_DESCRIPTION_4
    case brewItem([String])
    case aptItem([String])
  #else
    case _brewItem([String])
    case _aptItem([String])
  #endif

    /// Declare the list of packages installable using the homebrew package
    /// manager on macOS.
    public static func brew(_ packages: [String]) -> SystemPackageProvider {
      #if PACKAGE_DESCRIPTION_4
        return .brewItem(packages)
      #else
        return ._brewItem(packages)
      #endif
    }

    /// Declare the list of packages installable using the apt-get package
    /// manager on Ubuntu.
    public static func apt(_ packages: [String]) -> SystemPackageProvider {
      #if PACKAGE_DESCRIPTION_4
        return .aptItem(packages)
      #else
        return ._aptItem(packages)
      #endif
    }
}

// MARK: Package JSON serialization

extension Package: Encodable {
    private enum CodingKeys: CodingKey {
        case name
        case platforms
        case pkgConfig
        case providers
        case products
        case dependencies
        case targets
        case swiftLanguageVersions
        case cLanguageStandard
        case cxxLanguageStandard
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)

      #if !PACKAGE_DESCRIPTION_4
        if let platforms = self._platforms {
            try container.encode(platforms, forKey: .platforms)
        }
      #endif

        try container.encode(pkgConfig, forKey: .pkgConfig)
        try container.encode(providers, forKey: .providers)
        try container.encode(products, forKey: .products)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(targets, forKey: .targets)
      #if PACKAGE_DESCRIPTION_4
        let slv = swiftLanguageVersions?.map({ String($0) })
        try container.encode(slv, forKey: .swiftLanguageVersions)
      #else
        try container.encode(swiftLanguageVersions, forKey: .swiftLanguageVersions)
      #endif
        try container.encode(cLanguageStandard, forKey: .cLanguageStandard)
        try container.encode(cxxLanguageStandard, forKey: .cxxLanguageStandard)
    }
}

extension SystemPackageProvider: Encodable {
    private enum CodingKeys: CodingKey {
        case name
        case values
    }

    private enum Name: String, Encodable {
        case brew
        case apt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
      #if PACKAGE_DESCRIPTION_4
        switch self {
        case .brewItem(let packages):
            try container.encode(Name.brew, forKey: .name)
            try container.encode(packages, forKey: .values)
        case .aptItem(let packages):
            try container.encode(Name.apt, forKey: .name)
            try container.encode(packages, forKey: .values)
        }
      #else
        switch self {
        case ._brewItem(let packages):
            try container.encode(Name.brew, forKey: .name)
            try container.encode(packages, forKey: .values)
        case ._aptItem(let packages):
            try container.encode(Name.apt, forKey: .name)
            try container.encode(packages, forKey: .values)
        }
      #endif
    }
}

extension Target.Dependency: Encodable {
    private enum CodingKeys: CodingKey {
        case type
        case name
        case package
    }

    private enum Kind: String, Codable {
        case target
        case product
        case byName = "byname"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
      #if PACKAGE_DESCRIPTION_4
        switch self {
        case .targetItem(let name):
            try container.encode(Kind.target, forKey: .type)
            try container.encode(name, forKey: .name)
        case .productItem(let name, let package):
            try container.encode(Kind.product, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(package, forKey: .package)
        case .byNameItem(let name):
            try container.encode(Kind.byName, forKey: .type)
            try container.encode(name, forKey: .name)
        }
      #else
        switch self {
        case ._targetItem(let name):
            try container.encode(Kind.target, forKey: .type)
            try container.encode(name, forKey: .name)
        case ._productItem(let name, let package):
            try container.encode(Kind.product, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(package, forKey: .package)
        case ._byNameItem(let name):
            try container.encode(Kind.byName, forKey: .type)
            try container.encode(name, forKey: .name)
        }
      #endif
    }
}

// MARK: Package Dumping

func manifestToJSON(_ package: Package) -> String {
    struct Output: Encodable {
        let package: Package
        let errors: [String]
    }

    let encoder = JSONEncoder()
    let data = try! encoder.encode(Output(package: package, errors: errors))
    return String(data: data, encoding: .utf8)!
}

var errors: [String] = []
private var dumpInfo: (package: Package, fileNo: Int32)?
private func dumpPackageAtExit(_ package: Package, fileNo: Int32) {
    func dump() {
        guard let dumpInfo = dumpInfo else { return }
        guard let fd = fdopen(dumpInfo.fileNo, "w") else { return }
        fputs(manifestToJSON(dumpInfo.package), fd)
        fclose(fd)
    }
    dumpInfo = (package, fileNo)
    atexit(dump)
}
