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

/// The description for a complete package.
public final class Package {

    /// Represents a package dependency.
    public class Dependency: Encodable {

        /// The dependency requirement.
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
    public var platforms: [SupportedPlatform]?
  #endif

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
    /// Construct a package.
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
        self.platforms = platforms
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
        if let platforms = self.platforms {
            // The platforms API was introduced in manifest version 5.
            let versionedPlatforms = VersionedValue(platforms, api: "platforms", versions: [.v5])
            try container.encode(versionedPlatforms, forKey: .platforms)
        }
      #endif

        try container.encode(pkgConfig, forKey: .pkgConfig)
        try container.encode(providers, forKey: .providers)
        try container.encode(products, forKey: .products)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(targets, forKey: .targets)
      #if PACKAGE_DESCRIPTION_4
        let slv = swiftLanguageVersions?.map({ VersionedValue(String($0), api: "") })
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
