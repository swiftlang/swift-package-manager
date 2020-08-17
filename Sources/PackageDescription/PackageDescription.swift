/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if canImport(Glibc)
import Glibc
#elseif os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
import Darwin.C
#elseif os(Windows)
import ucrt
import struct WinSDK.HANDLE
#endif
import Foundation

/// The configuration of a Swift package.
///
/// Pass configuration options as parameters to your package's initializer
/// statement to provide the name of the package, its targets, products,
/// dependencies, and other configuration options.
///
/// By convention, you need to define the properties of a package in a single
/// nested initializer statement. Don’t modify it after initialization. The
/// following package manifest shows the initialization of a simple package
/// object for the MyLibrary Swift package:
///
///     // swift-tools-version:5.3
///     import PackageDescription
///
///     let package = Package(
///         name: "MyLibrary",
///         platforms: [
///             .macOS(.v10_15),
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
/// The package manifest must begin with the string `// swift-tools-version:``,
/// followed by a version number such as `// swift-tools-version:5.3.
///
/// The Swift tools version declares:
///
///     - The version of the PackageDescription framework
///     - The Swift language compatibility version to process the manifest
///     - The required minimum version of the Swift tools to use the package
///
/// Each version of Swift can introduce updates to the PackageDescription
/// library, but the previous API version is available to packages that declare
/// a prior tools version. This behavior allows you take advantage of new
/// releases of Swift, the Swift tools, and the PackageDescription framework,
/// without having to update your package manifest and without losing access to
/// existing packages.
public final class Package {

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

        /// An enum that represents the requirement for a package dependency.
        ///
        /// The dependency requirement can be defined as one of three different version requirements:
        ///
        /// **A version-based requirement.**
        ///
        /// Decide whether your project accepts updates to a package dependency up
        /// to the next major version or up to the next minor version. To be more
        /// restrictive, select a specific version range or an exact version.
        /// Major versions tend to have more significant changes than minor
        /// versions, and may require you to modify your code when they update.
        /// The version rule requires Swift packages to conform to semantic
        /// versioning. To learn more about the semantic versioning standard,
        /// visit [semver.org](https://semver.org).
        ///
        /// Selecting the version requirement is the recommended way to add a package dependency. It allows you to create a balance between restricting changes and obtaining improvements and features.
        ///
        /// **A branch-based requirement**
        ///
        /// Select the name of the branch for your package dependency to follow.
        /// Use branch-based dependencies when you're developing multiple packages
        /// in tandem or when you don't want to publish versions of your package dependencies.
        ///
        /// Note that packages which use branch-based dependency requirements
        /// can't be added as dependencies to packages that use version-based dependency
        /// requirements; you should remove branch-based dependency requirements
        /// before publishing a version of your package.
        ///
        /// **A commit-based requirement**
        ///
        /// Select the commit hash for your package dependency to follow.
        /// Choosing this option isn't recommended, and should be limited to
        /// exceptional cases. While pinning your package dependency to a specific
        /// commit ensures that the package dependency doesn't change and your
        /// code remains stable, you don't receive any updates at all. If you worry about
        /// the stability of a remote package, consider one of the more
        /// restrictive options of the version-based requirement.
        ///
        /// Note that packages which use commit-based dependency requirements
        /// can't be added as dependencies to packages that use version-based
        /// dependency requirements; you should remove commit-based dependency
        /// requirements before publishing a version of your package.
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

        /// The name of the package, or `nil` to deduce the name using the
        /// package's Git URL.
        public let name: String?

        /// The Git URL of the package dependency.
        public let url: String

        /// The dependency requirement of the package dependency.
        public let requirement: Requirement

        /// Initializes and returns a newly allocated requirement with the specified url and requirements.
        init(name: String?, url: String, requirement: Requirement) {
            self.name = name
            self.url = url
            self.requirement = requirement
        }
    }

    /// The name of the Swift package.
    public var name: String

  #if !PACKAGE_DESCRIPTION_4
    /// The list of supported platforms with a custom deployment target.
    @available(_PackageDescription, introduced: 5)
    public var platforms: [SupportedPlatform]? {
        get { return _platforms }
        set { _platforms = newValue }
    }
  #endif
    private var _platforms: [SupportedPlatform]?

    /// The default localization for resources.
    @available(_PackageDescription, introduced: 5.3)
    public var defaultLocalization: LanguageTag? {
        get { return _defaultLocalization }
        set { _defaultLocalization = newValue }
    }
    private var _defaultLocalization: LanguageTag?

    /// The name to use for C modules.
    ///
    /// If present, the Swift Package Manager searches for a `<name>.pc` file
    /// to get the required additional flags for a system target.
    public var pkgConfig: String?

    /// An array of providers for a system target.
    public var providers: [SystemPackageProvider]?

    /// The list of targets that are part of this package.
    public var targets: [Target]

    /// The list of products that this package vends and that clients can use.
    public var products: [Product]

    /// The list of package dependencies.
    public var dependencies: [Dependency]

  #if PACKAGE_DESCRIPTION_4
    /// The list of Swift versions that this package is compatible with.
    public var swiftLanguageVersions: [Int]?
  #else
    /// The list of Swift versions that this package is compatible with.
    public var swiftLanguageVersions: [SwiftVersion]?
  #endif

    /// The C language standard to use for all C targets in this package.
    public var cLanguageStandard: CLanguageStandard?

    /// The C++ language standard to use for all C++ targets in this package.
    public var cxxLanguageStandard: CXXLanguageStandard?

  #if PACKAGE_DESCRIPTION_4
    /// Initializes a Swift package with configuration options you provide.
    ///
    /// - Parameters:
    ///     - name: The name of the Swift package, or `nil`, if you want the Swift Package Manager to deduce the
    ///           name from the package’s Git URL.
    ///     - pkgConfig: The name to use for C modules. If present, the Swift 
    ///           Package Manager searches for a `<name>.pc` file to get the
    ///           additional flags required for a system target.
    ///     - providers: The package providers for a system package.
    ///     - products: The list of products that this package vends and that clients can use.
    ///     - dependencies: The list of package dependencies.
    ///     - targets: The list of targets that are part of this package.
    ///     - swiftLanguageVersions: The list of Swift versions that this package is compatible with.
    ///     - cLanguageStandard: The C language standard to use for all C targets in this package.
    ///     - cxxLanguageStandard: The C++ language standard to use for all C++ targets in this package.
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
    /// Initializes a Swift package with configuration options you provide.
    ///
    /// - Parameters:
    ///     - name: The name of the Swift package, or `nil`, if you want the Swift Package Manager to deduce the
    ///           name from the package’s Git URL.
    ///     - pkgConfig: The name to use for C modules. If present, the Swift 
    ///           Package Manager searches for a `<name>.pc` file to get the
    ///           additional flags required for a system target.
    ///     - products: The list of products that this package makes available for clients to use.
    ///     - dependencies: The list of package dependencies.
    ///     - targets: The list of targets that are part of this package.
    ///     - swiftLanguageVersions: The list of Swift versions that this package is compatible with.
    ///     - cLanguageStandard: The C language standard to use for all C targets in this package.
    ///     - cxxLanguageStandard: The C++ language standard to use for all C++ targets in this package.
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

    /// Initializes a Swift package with configuration options you provide.
    ///
    /// - Parameters:
    ///     - name: The name of the Swift package, or `nil`, if you want the Swift Package Manager to deduce the
    ///           name from the package’s Git URL.
    ///     - platforms: The list of supported platforms that have a custom deployment target.
    ///     - pkgConfig: The name to use for C modules. If present, the Swift 
    ///           Package Manager searches for a `<name>.pc` file to get the
    ///           additional flags required for a system target.
    ///     - products: The list of products that this package makes available for clients to use.
    ///     - dependencies: The list of package dependencies.
    ///     - targets: The list of targets that are part of this package.
    ///     - swiftLanguageVersions: The list of Swift versions that this package is compatible with.
    ///     - cLanguageStandard: The C language standard to use for all C targets in this package.
    ///     - cxxLanguageStandard: The C++ language standard to use for all C++ targets in this package.
    @available(_PackageDescription, introduced: 5, obsoleted: 5.3)
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

    /// Initializes a Swift package with configuration options you provide.
    ///
    /// - Parameters:
    ///     - name: The name of the Swift package, or `nil`, if you want the Swift Package Manager to deduce the
    ///           name from the package’s Git URL.
    ///     - defaultLocalization: The default localization for resources.
    ///     - platforms: The list of supported platforms that have a custom deployment target.
    ///     - pkgConfig: The name to use for C modules. If present, the Swift 
    ///           Package Manager searches for a `<name>.pc` file to get the
    ///           additional flags required for a system target.
    ///     - products: The list of products that this package vends and that clients can use.
    ///     - dependencies: The list of package dependencies.
    ///     - targets: The list of targets that are part of this package.
    ///     - swiftLanguageVersions: The list of Swift versions that this package is compatible with.
    ///     - cLanguageStandard: The C language standard to use for all C targets in this package.
    ///     - cxxLanguageStandard: The C++ language standard to use for all C++ targets in this package.
    @available(_PackageDescription, introduced: 5.3)
    public init(
        name: String,
        defaultLocalization: LanguageTag? = nil,
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
        self._defaultLocalization = defaultLocalization
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
        // Add a custom exit handler to cause the package's JSON representation
        // to be dumped at exit, if requested.  Emitting it to a separate file
        // descriptor from stdout keeps any of the manifest's stdout output from
        // interfering with it.
        //
        // FIXME: This doesn't belong here, but for now is the mechanism we use
        // to get the interpreter to dump the package when attempting to load a
        // manifest.
        //
        // Warning:  The `-fileno` flag is a contract between PackageDescription
        // and libSwiftPM, and since different versions of the two can be used
        // together, it isn't safe to rename or remove it.
        //
        // Note: `-fileno` is not viable on Windows.  Instead, we pass the file
        // handle through the `-handle` option.
#if os(Windows)
        if let index = CommandLine.arguments.firstIndex(of: "-handle") {
          if let handle = Int(CommandLine.arguments[index + 1], radix: 16) {
            dumpPackageAtExit(self, to: handle)
          }
        }
#else
        if let optIdx = CommandLine.arguments.firstIndex(of: "-fileno") {
            if let jsonOutputFileDesc = Int32(CommandLine.arguments[optIdx + 1]) {
                dumpPackageAtExit(self, to: jsonOutputFileDesc)
            }
        }
#endif
    }
}

/// A wrapper around an IETF language tag.
///
/// To learn more about the IETF worldwide standard for language tags, see [RFC5646](https://tools.ietf.org/html/rfc5646).
public struct LanguageTag: Hashable {

    /// An IETF language tag.
    public let tag: String

    /// Creates a language tag from its IETF string representation.
    public init(_ tag: String) {
        self.tag = tag
    }
}

extension LanguageTag: RawRepresentable {
    public var rawValue: String { tag }

    public init?(rawValue: String) {
        tag = rawValue
    }
}

extension LanguageTag: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        tag = value
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

extension LanguageTag: CustomStringConvertible {

    /// A textual description of the language tag.
    public var description: String { tag }
}

/// The system package providers used in this Swift package.
public enum SystemPackageProvider {

  #if PACKAGE_DESCRIPTION_4
    case brewItem([String])
    case aptItem([String])
  #else
    case _brewItem([String])
    case _aptItem([String])
    case _yumItem([String])
  #endif

    /// Creates a system package provider with a list of installable packages
    /// for users of the HomeBrew package manager on macOS.
    ///
    /// - Parameters:
    ///     - packages: The list of package names.
    public static func brew(_ packages: [String]) -> SystemPackageProvider {
      #if PACKAGE_DESCRIPTION_4
        return .brewItem(packages)
      #else
        return ._brewItem(packages)
      #endif
    }

    /// Creates a system package provider with a list of installable packages
    /// for users of the apt-get package manager on Ubuntu Linux.
    ///
    /// - Parameters:
    ///     - packages: The list of package names.
    public static func apt(_ packages: [String]) -> SystemPackageProvider {
      #if PACKAGE_DESCRIPTION_4
        return .aptItem(packages)
      #else
        return ._aptItem(packages)
      #endif
    }

#if PACKAGE_DESCRIPTION_4
// yum is not supported
#else
    /// Creates a system package provider with a list of installable packages
    /// for users of the yum package manager on Red Hat Enterprise Linux or CentOS.
    ///
    /// - Parameters:
    ///     - packages: The list of package names.
    @available(_PackageDescription, introduced: 5.3)
    public static func yum(_ packages: [String]) -> SystemPackageProvider {
        return ._yumItem(packages)
    }
#endif
}

// MARK: Package JSON serialization

extension Package: Encodable {
    private enum CodingKeys: CodingKey {
        case name
        case defaultLocalization
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
        if let defaultLocalization = _defaultLocalization {
            try container.encode(defaultLocalization.tag, forKey: .defaultLocalization)
        }
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
        case yum
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
        case ._yumItem(let packages):
            try container.encode(Name.yum, forKey: .name)
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
        case condition
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
        case ._targetItem(let name, let condition):
            try container.encode(Kind.target, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(condition, forKey: .condition)
        case ._productItem(let name, let package, let condition):
            try container.encode(Kind.product, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(package, forKey: .package)
            try container.encode(condition, forKey: .condition)
        case ._byNameItem(let name, let condition):
            try container.encode(Kind.byName, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(condition, forKey: .condition)
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

#if os(Windows)
private var dumpInfo: (package: Package, handle: Int)?
private func dumpPackageAtExit(_ package: Package, to handle: Int) {
  let dump: @convention(c) () -> Void = {
    guard let dumpInfo = dumpInfo else { return }

    let hFile: HANDLE = HANDLE(bitPattern: dumpInfo.handle)!
    // NOTE: `_open_osfhandle` transfers ownership of the HANDLE to the file
    // descriptor.  DO NOT invoke `CloseHandle` on `hFile`.
    let fd: CInt = _open_osfhandle(Int(bitPattern: hFile), _O_APPEND)
    // NOTE: `_fdopen` transfers ownership of the file descriptor to the
    // `FILE *`.  DO NOT invoke `_close` on the `fd`.
    guard let fp = _fdopen(fd, "w") else {
      _close(fd)
      return
    }
    defer { fclose(fp) }

    fputs(manifestToJSON(dumpInfo.package), fp)
  }

  dumpInfo = (package, handle)
  atexit(dump)
}
#else
private var dumpInfo: (package: Package, fileDesc: Int32)?
private func dumpPackageAtExit(_ package: Package, to fileDesc: Int32) {
    func dump() {
        guard let dumpInfo = dumpInfo else { return }
        guard let fd = fdopen(dumpInfo.fileDesc, "w") else { return }
        fputs(manifestToJSON(dumpInfo.package), fd)
        fclose(fd)
    }
    dumpInfo = (package, fileDesc)
    atexit(dump)
}
#endif
